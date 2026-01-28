#!/bin/bash
#
# Copyright (c) 2026 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#   Red Hat, Inc. - initial API and implementation
#

# Deploy Eclipse Che or CodeReady Workspaces on local/test clusters
#
# This script deploys Eclipse Che or CRW on OpenShift clusters including:
# - OpenShift Local (CRC) - IPv4 only, ARM64-compatible
# - SNO (Single Node OpenShift) - Can have IPv6
# - Cluster-bot IPv6 clusters
# - Any OpenShift 4.x cluster
#
# Prerequisites:
# - oc CLI configured and connected to an OpenShift cluster
# - chectl installed (for chectl deployment method)
#
# Usage:
#   ./deploy-local.sh [options]
#
# Options:
#   --crw                        Deploy CodeReady Workspaces instead of Eclipse Che
#   --dashboard-image <image>    Dashboard image (supports shortcuts: pr-XXXX, next, latest)
#   --namespace <namespace>      Namespace (default: eclipse-che for upstream, openshift-workspaces for CRW)
#   --skip-devworkspace          Skip DevWorkspace operator installation (if already installed)
#   --arm64-gateway              Use ARM64-compatible gateway images (for CRC on Apple Silicon)
#   --cleanup                    Delete existing deployment before installing
#   --help                       Show this help message
#
# Examples:
#   # Deploy Eclipse Che with pr-1442 dashboard
#   ./deploy-local.sh --dashboard-image pr-1442
#
#   # Deploy CRW with latest dashboard
#   ./deploy-local.sh --crw --dashboard-image latest
#
#   # Deploy on CRC (ARM64 Mac)
#   ./deploy-local.sh --dashboard-image pr-1442 --arm64-gateway
#
#   # Clean deploy of CRW
#   ./deploy-local.sh --crw --cleanup --dashboard-image next

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEPLOY_CRW=false
DASHBOARD_IMAGE=""
NAMESPACE=""
SKIP_DEVWORKSPACE=false
ARM64_GATEWAY=false
CLEANUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --crw)
            DEPLOY_CRW=true
            shift
            ;;
        --dashboard-image)
            DASHBOARD_IMAGE="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --skip-devworkspace)
            SKIP_DEVWORKSPACE=true
            shift
            ;;
        --arm64-gateway)
            ARM64_GATEWAY=true
            shift
            ;;
        --cleanup)
            CLEANUP=true
            shift
            ;;
        --help)
            grep '^#' "$0" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Set defaults based on product
if [ "${DEPLOY_CRW}" = "true" ]; then
    NAMESPACE="${NAMESPACE:-openshift-workspaces}"
    PRODUCT_NAME="CodeReady Workspaces"
    OPERATOR_NAME="codeready-workspaces"
    # Default CRW dashboard uses Red Hat registry
    if [ -z "${DASHBOARD_IMAGE}" ]; then
        DASHBOARD_IMAGE="registry.redhat.io/codeready-workspaces/crw-2-rhel8-dashboard:latest"
    fi
else
    NAMESPACE="${NAMESPACE:-eclipse-che}"
    PRODUCT_NAME="Eclipse Che"
    OPERATOR_NAME="eclipse-che"
    # Default Eclipse Che dashboard
    if [ -z "${DASHBOARD_IMAGE}" ]; then
        DASHBOARD_IMAGE="quay.io/eclipse/che-dashboard:next"
    fi
fi

# Process dashboard image shortcuts (pr-XXXX, next, latest)
if [[ -n "$DASHBOARD_IMAGE" ]]; then
    if [[ "$DASHBOARD_IMAGE" =~ ^pr-[0-9]+$ ]]; then
        # Convert pr-XXXX to full image path
        if [ "${DEPLOY_CRW}" = "true" ]; then
            echo -e "${YELLOW}Warning: Dashboard image shortcut '$DASHBOARD_IMAGE' may not work with --crw flag${NC}"
            echo -e "${YELLOW}         Consider using full CRW dashboard image path instead${NC}"
        fi
        DASHBOARD_IMAGE="quay.io/eclipse/che-dashboard:$DASHBOARD_IMAGE"
    elif [[ "$DASHBOARD_IMAGE" == "next" || "$DASHBOARD_IMAGE" == "latest" ]]; then
        # Convert next/latest to full image path
        if [ "${DEPLOY_CRW}" = "true" ]; then
            DASHBOARD_IMAGE="registry.redhat.io/codeready-workspaces/crw-2-rhel8-dashboard:${DASHBOARD_IMAGE}"
        else
            DASHBOARD_IMAGE="quay.io/eclipse/che-dashboard:$DASHBOARD_IMAGE"
        fi
    fi
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Deploy ${PRODUCT_NAME} on Local/Test Cluster             ${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  Product:          ${PRODUCT_NAME}"
echo -e "  Namespace:        ${NAMESPACE}"
echo -e "  Dashboard image:  ${DASHBOARD_IMAGE}"
echo -e "  ARM64 Gateway:    ${ARM64_GATEWAY}"
echo -e "  Skip DevWorkspace: ${SKIP_DEVWORKSPACE}"
echo -e "  Cleanup:          ${CLEANUP}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Step 1: Checking prerequisites${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

if ! command -v oc &>/dev/null; then
    echo -e "${RED}✗ oc CLI not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ oc CLI found${NC}"

if ! command -v chectl &>/dev/null; then
    echo -e "${YELLOW}⚠ chectl not found - will use direct CheCluster creation${NC}"
    CHECTL_AVAILABLE=false
else
    echo -e "${GREEN}✓ chectl found: $(chectl --version)${NC}"
    CHECTL_AVAILABLE=true
fi

# Check cluster access
if ! oc whoami &>/dev/null; then
    echo -e "${RED}✗ Not logged into OpenShift cluster${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Logged into OpenShift as $(oc whoami)${NC}"

# Detect cluster type
CLUSTER_API=$(oc whoami --show-server)
if [[ "$CLUSTER_API" == *"crc.testing"* ]]; then
    CLUSTER_TYPE="CRC (OpenShift Local)"
    echo -e "${BLUE}  Detected: ${CLUSTER_TYPE}${NC}"
elif [[ "$CLUSTER_API" == *"metalkube.org"* ]]; then
    CLUSTER_TYPE="Cluster-bot"
    echo -e "${BLUE}  Detected: ${CLUSTER_TYPE}${NC}"
else
    CLUSTER_TYPE="Unknown"
    echo -e "${BLUE}  Cluster: ${CLUSTER_API}${NC}"
fi

# Check if cluster has IPv6
echo ""
echo -e "${YELLOW}Step 2: Checking cluster networking${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

SERVICE_NETWORK=$(oc get network.config.openshift.io cluster -o jsonpath='{.spec.serviceNetwork[0]}' 2>/dev/null || echo "")
if [[ "$SERVICE_NETWORK" == fd* ]] || [[ "$SERVICE_NETWORK" == *:* ]]; then
    echo -e "${GREEN}✓ IPv6 service network detected: ${SERVICE_NETWORK}${NC}"
    HAS_IPV6=true
else
    echo -e "${YELLOW}⚠ IPv4 service network: ${SERVICE_NETWORK}${NC}"
    HAS_IPV6=false
fi

# Cleanup if requested
if [ "${CLEANUP}" = "true" ]; then
    echo ""
    echo -e "${YELLOW}Step 3: Cleaning up existing deployment${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

    oc delete checluster ${OPERATOR_NAME} -n ${NAMESPACE} --ignore-not-found=true
    echo -e "${YELLOW}Waiting for pods to terminate...${NC}"
    sleep 10

    TIMEOUT=60
    ELAPSED=0
    while oc get pods -n ${NAMESPACE} 2>/dev/null | grep -q "che\|dashboard\|gateway"; do
        if [ $ELAPSED -ge $TIMEOUT ]; then
            echo -e "${RED}Warning: Timeout waiting for pods to terminate${NC}"
            break
        fi
        echo "  Waiting... ($ELAPSED/$TIMEOUT)"
        sleep 3
        ELAPSED=$((ELAPSED + 3))
    done

    echo -e "${GREEN}✓ Cleanup complete${NC}"
fi

# Install operator if needed
echo ""
echo -e "${YELLOW}Step 4: Installing ${PRODUCT_NAME} Operator${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

# Create namespace
oc create namespace ${NAMESPACE} --dry-run=client -o yaml | oc apply -f -
echo -e "${GREEN}✓ Namespace ${NAMESPACE} ready${NC}"

# Check if CRD exists
if ! oc get crd checlusters.org.eclipse.che &>/dev/null; then
    if [ "${CHECTL_AVAILABLE}" = "true" ]; then
        echo -e "${YELLOW}Installing operator using chectl...${NC}"

        CHECTL_FLAGS="--platform=openshift --installer=olm --chenamespace=${NAMESPACE}"
        if [ "${SKIP_DEVWORKSPACE}" = "true" ]; then
            CHECTL_FLAGS="${CHECTL_FLAGS} --skip-devworkspace-operator"
        fi

        chectl server:deploy ${CHECTL_FLAGS} || true

        # Wait for CRD
        for i in {1..60}; do
            if oc get crd checlusters.org.eclipse.che &>/dev/null; then
                echo -e "${GREEN}✓ Operator installed${NC}"
                break
            fi
            echo "  Waiting for CRD... ($i/60)"
            sleep 5
        done
    else
        echo -e "${RED}✗ Operator not installed and chectl not available${NC}"
        echo -e "${YELLOW}Please install chectl or the operator manually${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ ${PRODUCT_NAME} operator already installed${NC}"
fi

# Wait for operator pod
echo -e "${YELLOW}Waiting for operator pod...${NC}"
for i in {1..40}; do
    if oc get pods -n ${NAMESPACE} -l app.kubernetes.io/component=che-operator 2>/dev/null | grep -q "Running"; then
        echo -e "${GREEN}✓ Operator pod is running${NC}"
        break
    fi
    echo "  Waiting... ($i/40)"
    sleep 3
done

# Deploy CheCluster
echo ""
echo -e "${YELLOW}Step 5: Deploying ${PRODUCT_NAME}${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

echo -e "${YELLOW}Generating CheCluster configuration...${NC}"
CHECLUSTER_TEMP=$(mktemp)

# Base CheCluster
cat > "$CHECLUSTER_TEMP" << EOF
apiVersion: org.eclipse.che/v2
kind: CheCluster
metadata:
  name: ${OPERATOR_NAME}
  namespace: ${NAMESPACE}
spec:
  components:
    dashboard:
      deployment:
        containers:
          - image: '${DASHBOARD_IMAGE}'
            imagePullPolicy: Always
            name: che-dashboard
    metrics:
      enable: false
EOF

# Add ARM64 gateway images if requested
if [ "${ARM64_GATEWAY}" = "true" ]; then
    cat >> "$CHECLUSTER_TEMP" << 'EOF'
  networking:
    auth:
      gateway:
        deployment:
          containers:
            - name: oauth-proxy
              image: registry.redhat.io/openshift4/ose-oauth-proxy:v4.14
            - name: kube-rbac-proxy
              image: registry.redhat.io/openshift4/ose-kube-rbac-proxy:v4.14
        configLabels:
          app: che
          component: che-gateway-config
EOF
fi

echo -e "${YELLOW}Applying CheCluster...${NC}"
oc apply -f "$CHECLUSTER_TEMP"
rm -f "$CHECLUSTER_TEMP"

echo -e "${GREEN}✓ CheCluster created${NC}"

# Wait for deployments
echo ""
echo -e "${YELLOW}Step 6: Waiting for deployments${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

echo -e "${YELLOW}Waiting for dashboard deployment...${NC}"
for i in {1..60}; do
    if oc get deployment/che-dashboard -n ${NAMESPACE} &>/dev/null; then
        echo -e "${GREEN}✓ Dashboard deployment created${NC}"
        break
    fi
    echo "  Waiting... ($i/60)"
    sleep 3
done

echo -e "${YELLOW}Waiting for che-server deployment...${NC}"
for i in {1..60}; do
    if oc get deployment/che -n ${NAMESPACE} &>/dev/null; then
        echo -e "${GREEN}✓ Che server deployment created${NC}"
        break
    fi
    echo "  Waiting... ($i/60)"
    sleep 3
done

echo -e "${YELLOW}Waiting for gateway deployment...${NC}"
for i in {1..60}; do
    if oc get deployment/che-gateway -n ${NAMESPACE} &>/dev/null; then
        echo -e "${GREEN}✓ Gateway deployment created${NC}"
        break
    fi
    echo "  Waiting... ($i/60)"
    sleep 3
done

# Wait for pods to be ready
echo ""
echo -e "${YELLOW}Step 7: Waiting for pods to be ready${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

echo -e "${YELLOW}This may take 5-10 minutes...${NC}"
sleep 20

echo -e "${YELLOW}Waiting for che-server...${NC}"
oc rollout status deployment/che -n ${NAMESPACE} --timeout=10m || echo -e "${RED}Warning: timeout${NC}"

echo -e "${YELLOW}Waiting for dashboard...${NC}"
oc rollout status deployment/che-dashboard -n ${NAMESPACE} --timeout=5m || echo -e "${RED}Warning: timeout${NC}"

echo -e "${YELLOW}Waiting for gateway...${NC}"
oc rollout status deployment/che-gateway -n ${NAMESPACE} --timeout=5m || echo -e "${RED}Warning: timeout${NC}"

echo -e "${GREEN}✓ All deployments ready${NC}"

# Display status
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Deployment Status${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo ""
oc get pods -n ${NAMESPACE}
echo ""

# Get route URL
ROUTE_URL=$(oc get route che -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo "Not available")

echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                 🎉 Deployment Complete! 🎉                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Access URLs:${NC}"
if [ "$ROUTE_URL" != "Not available" ]; then
    echo -e "  ${YELLOW}Main:${NC}      https://$ROUTE_URL"
    echo -e "  ${YELLOW}Dashboard:${NC} https://$ROUTE_URL/dashboard/"
else
    echo -e "  ${RED}Route not ready yet${NC}"
fi
echo ""

echo -e "${BLUE}Images in use:${NC}"
CHE_IMAGE=$(oc get deployment/che -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "N/A")
DASHBOARD_IMAGE_ACTUAL=$(oc get deployment/che-dashboard -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "N/A")

echo -e "  ${YELLOW}Che Server:${NC}    $CHE_IMAGE"
echo -e "  ${YELLOW}Dashboard:${NC}     $DASHBOARD_IMAGE_ACTUAL"
echo ""

echo -e "${BLUE}Cluster Info:${NC}"
echo -e "  ${YELLOW}Type:${NC}         $CLUSTER_TYPE"
echo -e "  ${YELLOW}IPv6:${NC}         $HAS_IPV6"
echo -e "  ${YELLOW}Namespace:${NC}    $NAMESPACE"
echo ""

echo -e "${BLUE}Useful commands:${NC}"
echo -e "  ${YELLOW}Check pods:${NC}         oc get pods -n ${NAMESPACE}"
echo -e "  ${YELLOW}Dashboard logs:${NC}     oc logs -f deployment/che-dashboard -n ${NAMESPACE}"
echo -e "  ${YELLOW}Che server logs:${NC}    oc logs -f deployment/che -n ${NAMESPACE}"
echo -e "  ${YELLOW}Gateway logs:${NC}       oc logs -f deployment/che-gateway -n ${NAMESPACE}"
echo ""

echo -e "${GREEN}✓ Deployment completed successfully!${NC}"
