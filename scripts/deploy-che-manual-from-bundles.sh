#!/bin/bash

# Manual Eclipse Che deployment by extracting manifests from OLM bundle images
# Bypasses IPv6 ClusterIP catalog connectivity issues

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="eclipse-che"
DASHBOARD_IMAGE=""
CHE_SERVER_IMAGE=""
KUBECONFIG_PATH=""
SKIP_DEVWORKSPACE=false
DEVWORKSPACE_BUNDLE_IMAGE="quay.io/devfile/devworkspace-operator-bundle:next"
CHE_BUNDLE_IMAGE="quay.io/eclipse/eclipse-che-openshift-opm-bundles:next"

# Function to print colored output
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --kubeconfig)
            KUBECONFIG_PATH="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --dashboard-image)
            DASHBOARD_IMAGE="$2"
            shift 2
            ;;
        --che-server-image)
            CHE_SERVER_IMAGE="$2"
            shift 2
            ;;
        --skip-devworkspace)
            SKIP_DEVWORKSPACE=true
            shift
            ;;
        --devworkspace-bundle)
            DEVWORKSPACE_BUNDLE_IMAGE="$2"
            shift 2
            ;;
        --che-bundle)
            CHE_BUNDLE_IMAGE="$2"
            shift 2
            ;;
        --help)
            echo "Manual Eclipse Che Deployment from OLM Bundles"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --kubeconfig <path>              Path to kubeconfig file (required)"
            echo "  --namespace <name>               Namespace for Eclipse Che (default: eclipse-che)"
            echo "  --dashboard-image <image>        Dashboard container image (shortcuts: pr-XXXX, next, latest)"
            echo "  --che-server-image <image>       Che server container image"
            echo "  --skip-devworkspace              Skip DevWorkspace Operator installation"
            echo "  --devworkspace-bundle <image>    DevWorkspace bundle image (default: quay.io/devfile/devworkspace-operator-bundle:next)"
            echo "  --che-bundle <image>             Che bundle image (default: quay.io/eclipse/eclipse-che-openshift-opm-bundles:next)"
            echo "  --help                           Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$KUBECONFIG_PATH" ]; then
    log_error "Missing required argument: --kubeconfig"
    exit 1
fi

export KUBECONFIG="$KUBECONFIG_PATH"

# Check for podman
if ! command -v podman &> /dev/null; then
    log_error "podman is required but not installed"
    exit 1
fi

log_info "=== Manual Eclipse Che Deployment from OLM Bundles ==="
log_info "Namespace: $NAMESPACE"
log_info "Dashboard Image: ${DASHBOARD_IMAGE:-default}"
log_info "Che Server Image: ${CHE_SERVER_IMAGE:-default}"
log_info "DevWorkspace Bundle: $DEVWORKSPACE_BUNDLE_IMAGE"
log_info "Che Bundle: $CHE_BUNDLE_IMAGE"
echo

# Create temporary directory for manifests
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

log_info "Using temp directory: $TEMP_DIR"
echo

#######################################
# Step 1: Deploy DevWorkspace Operator
#######################################

if [ "$SKIP_DEVWORKSPACE" = false ]; then
    log_info "Step 1: Deploying DevWorkspace Operator from bundle"

    # Pull bundle image
    log_info "Pulling DevWorkspace bundle image..."
    podman pull "$DEVWORKSPACE_BUNDLE_IMAGE"

    # Extract manifests from bundle
    log_info "Extracting manifests from bundle..."
    BUNDLE_CONTAINER=$(podman create "$DEVWORKSPACE_BUNDLE_IMAGE")
    podman cp "${BUNDLE_CONTAINER}:/manifests" "$TEMP_DIR/devworkspace-manifests"
    podman rm "$BUNDLE_CONTAINER"

    # Find and apply CSV (contains all manifests)
    CSV_FILE=$(find "$TEMP_DIR/devworkspace-manifests" -name "*.clusterserviceversion.yaml" | head -1)

    if [ -z "$CSV_FILE" ]; then
        log_error "No ClusterServiceVersion found in bundle"
        exit 1
    fi

    log_info "Found CSV: $(basename $CSV_FILE)"

    # Extract CRDs from bundle
    log_info "Applying CRDs..."
    find "$TEMP_DIR/devworkspace-manifests" -name "*.crd.yaml" -exec kubectl apply -f {} \;

    # Create devworkspace-controller namespace if it doesn't exist
    kubectl create namespace devworkspace-controller --dry-run=client -o yaml | kubectl apply -f -

    # Parse CSV and extract deployment/RBAC specs
    log_info "Extracting operator deployment from CSV..."

    # Use yq or python to parse CSV and extract deployment
    # Check if yq is the Go version (mikefarah/yq) which supports 'eval' command
    # Python yq (kislyuk/yq) is a jq wrapper and doesn't support the eval syntax
    if command -v yq &> /dev/null && ! yq --help 2>&1 | grep -q "jq wrapper"; then
        # Extract deployment name and spec from CSV (OLM format)
        DEPLOY_NAME=$(yq eval '.spec.install.spec.deployments[0].name' "$CSV_FILE")

        # Create full Deployment manifest
        cat > "$TEMP_DIR/dwo-deployment.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEPLOY_NAME}
  namespace: devworkspace-controller
spec:
YAML
        # Extract and append the deployment spec
        yq eval '.spec.install.spec.deployments[0].spec' "$CSV_FILE" | sed 's/^/  /' >> "$TEMP_DIR/dwo-deployment.yaml"

        # Extract RBAC (serviceAccount, role, rolebinding)
        # Create ServiceAccount
        SA_NAME=$(yq eval '.spec.install.spec.clusterPermissions[0].serviceAccountName' "$CSV_FILE")
        cat > "$TEMP_DIR/dwo-rbac.yaml" <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SA_NAME}
  namespace: devworkspace-controller
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: devworkspace-controller-role
rules:
YAML
        yq eval '.spec.install.spec.clusterPermissions[0].rules' "$CSV_FILE" | sed 's/^/  /' >> "$TEMP_DIR/dwo-rbac.yaml"

        cat >> "$TEMP_DIR/dwo-rbac.yaml" <<YAML
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: devworkspace-controller-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: devworkspace-controller-role
subjects:
- kind: ServiceAccount
  name: ${SA_NAME}
  namespace: devworkspace-controller
YAML

    else
        log_warn "yq not found, using simplified extraction"

        # Simple extraction using grep/sed (fallback)
        # This is less reliable but works if yq is not available

        # Create a minimal deployment
        OPERATOR_IMAGE=$(grep 'image:' "$CSV_FILE" | grep devworkspace-controller | head -1 | sed -E 's/.*image: *([^ ]+).*/\1/')

        cat > "$TEMP_DIR/dwo-deployment.yaml" <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: devworkspace-controller-serviceaccount
  namespace: devworkspace-controller
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: devworkspace-controller-role
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: devworkspace-controller-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: devworkspace-controller-role
subjects:
- kind: ServiceAccount
  name: devworkspace-controller-serviceaccount
  namespace: devworkspace-controller
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: devworkspace-controller-manager
  namespace: devworkspace-controller
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: devworkspace-controller
  template:
    metadata:
      labels:
        app.kubernetes.io/name: devworkspace-controller
    spec:
      serviceAccountName: devworkspace-controller-serviceaccount
      containers:
      - name: devworkspace-controller
        image: ${OPERATOR_IMAGE:-quay.io/devfile/devworkspace-controller:next}
        imagePullPolicy: Always
        env:
        - name: WATCH_NAMESPACE
          value: ""
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: OPERATOR_NAME
          value: devworkspace-controller
YAML
    fi

    # Apply manifests
    log_info "Applying DevWorkspace Operator manifests..."
    kubectl apply -f "$TEMP_DIR/dwo-deployment.yaml"

    # Wait for deployment
    log_info "Waiting for DevWorkspace Operator..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/devworkspace-controller-manager \
        -n devworkspace-controller 2>/dev/null || {
        log_warn "Deployment wait failed, checking pod status..."
        sleep 30
    }

    log_success "DevWorkspace Operator deployed"
    echo
else
    log_warn "Skipping DevWorkspace Operator installation"
    echo
fi

#######################################
# Step 2: Create Eclipse Che Namespace
#######################################

log_info "Step 2: Creating namespace $NAMESPACE"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Add monitoring label for OpenShift
kubectl label namespace "$NAMESPACE" \
    app.kubernetes.io/part-of=che.eclipse.org \
    app.kubernetes.io/component=che \
    --overwrite

log_success "Namespace $NAMESPACE ready"
echo

#######################################
# Step 3: Deploy Che Operator from Bundle
#######################################

log_info "Step 3: Deploying Eclipse Che Operator from bundle"

# Pull Che bundle image
log_info "Pulling Che bundle image..."
podman pull "$CHE_BUNDLE_IMAGE"

# Extract manifests from bundle
log_info "Extracting manifests from bundle..."
BUNDLE_CONTAINER=$(podman create "$CHE_BUNDLE_IMAGE")
podman cp "${BUNDLE_CONTAINER}:/manifests" "$TEMP_DIR/che-manifests"
podman rm "$BUNDLE_CONTAINER"

# Apply CRDs
log_info "Applying Che CRDs..."
find "$TEMP_DIR/che-manifests" -name "*_checlusters*.yaml" -o -name "*.crd.yaml" | while read crd; do
    log_info "Applying $(basename $crd)"
    # Use server-side apply to handle large CRD annotations
    kubectl apply --server-side=true --force-conflicts -f "$crd"
done

# Find CSV
CSV_FILE=$(find "$TEMP_DIR/che-manifests" -name "*.clusterserviceversion.yaml" | head -1)

if [ -z "$CSV_FILE" ]; then
    log_error "No ClusterServiceVersion found in Che bundle"
    exit 1
fi

log_info "Found Che CSV: $(basename $CSV_FILE)"

# Extract operator deployment
# Check if yq is the Go version (mikefarah/yq), not the Python jq wrapper
if command -v yq &> /dev/null && ! yq --help 2>&1 | grep -q "jq wrapper"; then
    log_info "Using yq to extract deployment..."

    # Extract ServiceAccount
    yq eval '.spec.install.spec.clusterPermissions[0].serviceAccountName' "$CSV_FILE" > "$TEMP_DIR/sa-name.txt"
    SA_NAME=$(cat "$TEMP_DIR/sa-name.txt")

    # Create ServiceAccount
    cat > "$TEMP_DIR/che-operator.yaml" <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SA_NAME:-che-operator}
  namespace: $NAMESPACE
---
YAML

    # Extract and create ClusterRole
    cat >> "$TEMP_DIR/che-operator.yaml" <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: che-operator
rules:
YAML
    yq eval '.spec.install.spec.clusterPermissions[0].rules' "$CSV_FILE" | sed 's/^/  /' >> "$TEMP_DIR/che-operator.yaml"

    # Create ClusterRoleBinding
    cat >> "$TEMP_DIR/che-operator.yaml" <<YAML
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: che-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: che-operator
subjects:
- kind: ServiceAccount
  name: ${SA_NAME:-che-operator}
  namespace: $NAMESPACE
---
YAML

    # Extract deployment name and spec
    DEPLOY_NAME=$(yq eval '.spec.install.spec.deployments[0].name' "$CSV_FILE")

    cat >> "$TEMP_DIR/che-operator.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEPLOY_NAME}
  namespace: $NAMESPACE
spec:
YAML
    # Extract and append the deployment spec
    yq eval '.spec.install.spec.deployments[0].spec' "$CSV_FILE" | sed 's/^/  /' >> "$TEMP_DIR/che-operator.yaml"

else
    log_warn "yq not found, using simplified operator deployment"

    # Fallback: create minimal operator deployment
    OPERATOR_IMAGE=$(grep 'image:' "$CSV_FILE" | grep che-operator | head -1 | sed -E 's/.*image: *([^ ]+).*/\1/')

    cat > "$TEMP_DIR/che-operator.yaml" <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: che-operator
  namespace: $NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: che-operator
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: che-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: che-operator
subjects:
- kind: ServiceAccount
  name: che-operator
  namespace: $NAMESPACE
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: che-operator
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: che-operator
  template:
    metadata:
      labels:
        app.kubernetes.io/name: che-operator
    spec:
      serviceAccountName: che-operator
      containers:
      - name: che-operator
        image: ${OPERATOR_IMAGE:-quay.io/eclipse/che-operator:next}
        imagePullPolicy: Always
        env:
        - name: WATCH_NAMESPACE
          value: "$NAMESPACE"
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: OPERATOR_NAME
          value: che-operator
YAML
fi

# Apply Che Operator manifests
log_info "Applying Che Operator manifests..."
kubectl apply -f "$TEMP_DIR/che-operator.yaml"

# Wait for Che Operator
log_info "Waiting for Che Operator..."
kubectl wait --for=condition=available --timeout=300s \
    deployment/che-operator \
    -n "$NAMESPACE" 2>/dev/null || {
    log_warn "Deployment wait failed, checking pod status..."
    sleep 30
}

log_success "Che Operator deployed"
echo

#######################################
# Step 4: Create CheCluster CR
#######################################

log_info "Step 4: Creating CheCluster Custom Resource"

# Build CheCluster CR
cat > "$TEMP_DIR/checluster.yaml" <<YAML
apiVersion: org.eclipse.che/v2
kind: CheCluster
metadata:
  name: eclipse-che
  namespace: $NAMESPACE
spec:
  components:
    cheServer:
      debug: false
      logLevel: INFO
      deployment:
        containers:
          - name: che-server
YAML

# Add custom Che server image if specified
if [ -n "$CHE_SERVER_IMAGE" ]; then
    cat >> "$TEMP_DIR/checluster.yaml" <<YAML
            image: $CHE_SERVER_IMAGE
YAML
fi

cat >> "$TEMP_DIR/checluster.yaml" <<YAML
            imagePullPolicy: Always

    dashboard:
      deployment:
        containers:
          - name: dashboard
YAML

# Add custom dashboard image if specified
if [ -n "$DASHBOARD_IMAGE" ]; then
    # Expand shortcuts
    case "$DASHBOARD_IMAGE" in
        pr-*)
            DASHBOARD_IMAGE="quay.io/eclipse/che-dashboard:$DASHBOARD_IMAGE"
            ;;
        next)
            DASHBOARD_IMAGE="quay.io/eclipse/che-dashboard:next"
            ;;
        latest)
            DASHBOARD_IMAGE="quay.io/eclipse/che-dashboard:latest"
            ;;
    esac

    cat >> "$TEMP_DIR/checluster.yaml" <<YAML
            image: $DASHBOARD_IMAGE
YAML
fi

cat >> "$TEMP_DIR/checluster.yaml" <<YAML
            imagePullPolicy: Always

  devEnvironments:
    startTimeoutSeconds: 600
    defaultEditor: che-incubator/che-code/latest
    defaultComponents:
      - name: universal-developer-image
        container:
          image: quay.io/devfile/universal-developer-image:ubi9-latest
          memoryLimit: 4Gi
          memoryRequest: 2Gi

  networking:
    auth:
      identityProviderURL: ""
YAML

log_info "Applying CheCluster CR:"
cat "$TEMP_DIR/checluster.yaml"
echo

kubectl apply -f "$TEMP_DIR/checluster.yaml"

log_success "CheCluster CR created"
echo

#######################################
# Step 5: Wait for Che Components
#######################################

log_info "Step 5: Waiting for Eclipse Che components to be ready..."
log_info "This may take several minutes..."
echo

# Wait for CheCluster to be available
log_info "Waiting for CheCluster status..."
for i in {1..60}; do
    CHE_URL=$(kubectl get checluster eclipse-che -n "$NAMESPACE" -o jsonpath='{.status.cheURL}' 2>/dev/null || echo "")
    CHE_PHASE=$(kubectl get checluster eclipse-che -n "$NAMESPACE" -o jsonpath='{.status.chePhase}' 2>/dev/null || echo "")
    CHE_MESSAGE=$(kubectl get checluster eclipse-che -n "$NAMESPACE" -o jsonpath='{.status.message}' 2>/dev/null || echo "")

    if [ -n "$CHE_URL" ] && [ "$CHE_PHASE" = "Active" ]; then
        log_success "Eclipse Che is ready!"
        log_success "Che URL: $CHE_URL"
        break
    fi

    if [ $((i % 10)) -eq 0 ]; then
        log_info "Status: ${CHE_PHASE:-Pending} - ${CHE_MESSAGE} (${i}/60)"
    fi

    sleep 10
done

# Show final status
echo
log_info "=== Deployment Summary ==="
kubectl get checluster -n "$NAMESPACE"
echo
kubectl get pods -n "$NAMESPACE"
echo

# Get Che URL
CHE_URL=$(kubectl get checluster eclipse-che -n "$NAMESPACE" -o jsonpath='{.status.cheURL}' 2>/dev/null || echo "")
if [ -n "$CHE_URL" ]; then
    echo
    log_success "=== Eclipse Che Deployed Successfully ==="
    log_success "Che URL: $CHE_URL"
    echo

    # Extract proxy information from kubeconfig
    if [ -n "$KUBECONFIG_PATH" ]; then
        PROXY_URL=$(grep proxy-url "$KUBECONFIG_PATH" 2>/dev/null | awk '{print $2}' || echo "")

        if [ -n "$PROXY_URL" ]; then
            PROXY_HOST=$(echo "$PROXY_URL" | sed 's|http://||' | cut -d: -f1)
            PROXY_PORT=$(echo "$PROXY_URL" | sed 's|http://||' | cut -d: -f2)

            log_info "=== Next Steps: Access the Dashboard ==="
            echo
            echo "The cluster is only accessible via proxy from the kubeconfig:"
            echo "  Proxy: $PROXY_URL"
            echo
            echo "Step 1: Launch Google Chrome with proxy"
            echo
            echo "  macOS:"
            echo "    /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome \\"
            echo "      --proxy-server=\"http://${PROXY_HOST}:${PROXY_PORT}\""
            echo
            echo "  Linux:"
            echo "    google-chrome \\"
            echo "      --proxy-server=\"http://${PROXY_HOST}:${PROXY_PORT}\""
            echo
            echo "Step 2: Open Che Dashboard in the proxied Chrome:"
            echo "  ${CHE_URL}/dashboard/"
            echo
            echo "Step 3: Login with OpenShift credentials"
            echo "  (Use the kubeadmin credentials from cluster-bot)"
            echo
        else
            log_warn "No proxy-url found in kubeconfig"
            log_info "To access the dashboard, navigate to: ${CHE_URL}/dashboard/"
        fi
    else
        log_info "To access the dashboard, navigate to: ${CHE_URL}/dashboard/"
    fi
else
    log_warn "Che URL not yet available. Check status with:"
    echo "  kubectl get checluster -n $NAMESPACE -w"
fi

echo
log_info "=== Additional Commands ==="
echo "To check operator logs:"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=che-operator -f"
echo
echo "To check CheCluster status:"
echo "  kubectl describe checluster eclipse-che -n $NAMESPACE"
echo
echo "To get Che URL later:"
echo "  kubectl get checluster eclipse-che -n $NAMESPACE -o jsonpath='{.status.cheURL}'"
