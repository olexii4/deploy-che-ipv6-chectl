#!/bin/bash

# Diagnostic and fix script for IPv6 CatalogSource connectivity issues
# This script tests and applies the hostNetwork workaround

set -e

KUBECONFIG="${1:-}"
if [ -z "$KUBECONFIG" ]; then
    echo "Usage: $0 <kubeconfig-path>"
    exit 1
fi

export KUBECONFIG

echo "=== IPv6 Catalog Connectivity Diagnostics ==="
echo

# 1. Check current catalog status
echo "1. Current CatalogSource Status:"
kubectl get catalogsource -n openshift-marketplace

echo
echo "2. Check Catalog Services and Endpoints:"
for catalog in devworkspace-operator eclipse-che; do
    if kubectl get catalogsource -n openshift-marketplace $catalog &>/dev/null; then
        echo "  Catalog: $catalog"
        SVC_IP=$(kubectl get svc -n openshift-marketplace $catalog -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "N/A")
        ENDPOINT=$(kubectl get endpoints -n openshift-marketplace $catalog -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "N/A")
        echo "    Service ClusterIP: $SVC_IP"
        echo "    Pod Endpoint: $ENDPOINT"
        
        # Test connectivity if service exists
        if [ "$SVC_IP" != "N/A" ]; then
            echo "    Testing connectivity to $SVC_IP:50051..."
            if timeout 5 kubectl run -n openshift-marketplace --rm -i --restart=Never grpc-test-$catalog \
                --image=quay.io/grpc-ecosystem/grpc-health-probe:latest \
                -- grpc_health_probe -addr=$SVC_IP:50051 &>/dev/null; then
                echo "    ✅ Connection successful"
            else
                echo "    ❌ Connection failed (timeout)"
            fi
        fi
        echo
    fi
done

echo "3. Current Subscription Status:"
kubectl get subscription -n openshift-operators devworkspace-operator -o jsonpath='{.status.conditions[?(@.type=="BundleUnpacking")]}' 2>/dev/null | jq . || echo "Subscription not found or no status"

echo
echo "=== Proposed Fix: Use HostNetwork for CatalogSources ==="
echo
read -p "Apply hostNetwork patch to CatalogSources? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Skipping patch. Exiting."
    exit 0
fi

echo "Applying hostNetwork patch..."

# Delete existing subscription first
echo "1. Deleting existing subscription..."
kubectl delete subscription -n openshift-operators devworkspace-operator --ignore-not-found=true

# Delete and recreate catalogs with hostNetwork
echo "2. Recreating CatalogSources with hostNetwork..."

# DevWorkspace Operator catalog
kubectl delete catalogsource -n openshift-marketplace devworkspace-operator --ignore-not-found=true
cat <<YAML | kubectl apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: devworkspace-operator
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: quay.io/devfile/devworkspace-operator-index:next
  publisher: Red Hat
  displayName: DevWorkspace Operator
  updateStrategy:
    registryPoll:
      interval: 15m
  grpcPodConfig:
    securityContextConfig: restricted
    nodeSelector:
      kubernetes.io/os: linux
    hostNetwork: true
YAML

# Eclipse Che catalog
kubectl delete catalogsource -n openshift-marketplace eclipse-che --ignore-not-found=true
cat <<YAML | kubectl apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: eclipse-che
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: quay.io/eclipse/eclipse-che-openshift-opm-catalog:next
  publisher: Eclipse Che
  displayName: Eclipse Che Operator
  updateStrategy:
    registryPoll:
      interval: 15m
  grpcPodConfig:
    securityContextConfig: restricted
    nodeSelector:
      kubernetes.io/os: linux
    hostNetwork: true
YAML

echo
echo "3. Waiting for catalog pods to be ready (with hostNetwork)..."
kubectl wait --for=condition=ready pod -n openshift-marketplace -l olm.catalogSource=devworkspace-operator --timeout=120s
kubectl wait --for=condition=ready pod -n openshift-marketplace -l olm.catalogSource=eclipse-che --timeout=120s

echo
echo "4. Testing connectivity with hostNetwork..."
sleep 5

for catalog in devworkspace-operator eclipse-che; do
    POD=$(kubectl get pod -n openshift-marketplace -l olm.catalogSource=$catalog -o jsonpath='{.items[0].metadata.name}')
    POD_IP=$(kubectl get pod -n openshift-marketplace $POD -o jsonpath='{.status.podIP}')
    echo "  Testing $catalog pod $POD at $POD_IP..."
    
    if kubectl run -n openshift-marketplace --rm -i --restart=Never grpc-test-$catalog \
        --image=quay.io/grpc-ecosystem/grpc-health-probe:latest \
        -- grpc_health_probe -addr=$POD_IP:50051; then
        echo "  ✅ Direct pod connection successful"
    else
        echo "  ❌ Direct pod connection failed"
    fi
    echo
done

echo "=== HostNetwork Patch Applied ==="
echo
echo "Next steps:"
echo "1. Run chectl deployment again with the patched catalogs"
echo "2. Monitor if OLM can now resolve the subscription"
echo
echo "Command to retry deployment:"
echo "  ./scripts/deploy-che-ipv6.sh --kubeconfig $KUBECONFIG --dashboard-image pr-1442"
