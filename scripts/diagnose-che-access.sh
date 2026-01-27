#!/bin/bash
#
# Diagnose Eclipse Che Access Issues
#
# This script helps diagnose why you cannot access Eclipse Che dashboard
# and provides specific solutions based on the failure mode.
#

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="${1:-eclipse-che}"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Diagnosing Eclipse Che Access Issues              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Get Che URL and route
CHE_URL=$(oc get checluster eclipse-che -n ${NAMESPACE} -o jsonpath='{.status.cheURL}' 2>/dev/null || echo "")
ROUTE_HOST=$(oc get route che -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [ -z "$CHE_URL" ]; then
    echo -e "${RED}Error: Could not get Che URL. Is Che deployed?${NC}"
    exit 1
fi

echo -e "${BLUE}Che Information:${NC}"
echo "  Che URL:   ${CHE_URL}"
echo "  Route Host: ${ROUTE_HOST}"
echo ""

# Test 1: Check from within cluster
echo -e "${YELLOW}Test 1: Checking Che access from within cluster...${NC}"
CLUSTER_TEST=$(oc run che-test-access --image=curlimages/curl:latest --rm -i --restart=Never -n ${NAMESPACE} -- \
    curl -sL -w "%{http_code}" -o /dev/null --max-time 10 "${CHE_URL}" 2>&1 || echo "failed")

if [[ "$CLUSTER_TEST" == "200" ]] || [[ "$CLUSTER_TEST" == "302" ]] || [[ "$CLUSTER_TEST" == "301" ]]; then
    echo -e "${GREEN}✓ Che is accessible from within cluster (HTTP ${CLUSTER_TEST})${NC}"
    echo -e "${YELLOW}  → This means Che deployment is working${NC}"
    echo -e "${YELLOW}  → Problem is network access from your laptop${NC}"
else
    echo -e "${RED}✗ Che is NOT accessible from within cluster${NC}"
    echo -e "${YELLOW}  → This indicates a deployment or route problem${NC}"
    echo ""
    echo "Check pods:"
    oc get pods -n ${NAMESPACE}
    exit 1
fi
echo ""

# Test 2: DNS resolution from laptop
echo -e "${YELLOW}Test 2: Checking DNS resolution from your laptop...${NC}"
if host "${ROUTE_HOST}" >/dev/null 2>&1; then
    RESOLVED_IP=$(host "${ROUTE_HOST}" | grep "has address\|has IPv6 address" | head -1)
    echo -e "${GREEN}✓ Route hostname resolves: ${RESOLVED_IP}${NC}"
else
    echo -e "${RED}✗ Route hostname does NOT resolve from your laptop${NC}"
    echo -e "${YELLOW}  → DNS resolution failure (common with cluster-bot)${NC}"
    echo ""
    echo -e "${BLUE}SOLUTION: Use SOCKS proxy via SSH bastion${NC}"
    echo "  This is required for cluster-bot clusters"
    echo ""
fi
echo ""

# Test 3: Network connectivity from laptop
echo -e "${YELLOW}Test 3: Checking network connectivity from your laptop...${NC}"
if timeout 5 bash -c "curl -sL --max-time 5 -o /dev/null '${CHE_URL}' 2>&1" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Can connect to ${CHE_URL}${NC}"
    echo -e "${GREEN}  → Network access is working!${NC}"
else
    echo -e "${RED}✗ Cannot connect to ${CHE_URL} from your laptop${NC}"
    echo -e "${YELLOW}  → Network is blocked or route is not publicly accessible${NC}"
    echo ""
fi
echo ""

# Test 4: Check OAuth configuration
echo -e "${YELLOW}Test 4: Checking OAuth redirect URIs...${NC}"
KEYCLOAK_URL=$(oc get checluster eclipse-che -n ${NAMESPACE} -o jsonpath='{.status.keycloakURL}' 2>/dev/null || echo "")
if [ -n "$KEYCLOAK_URL" ]; then
    echo "  Keycloak URL: ${KEYCLOAK_URL}"
    echo -e "${YELLOW}  Note: OAuth redirect URIs must match the access URL${NC}"
else
    echo -e "${YELLOW}  Using OpenShift OAuth (no separate Keycloak)${NC}"
fi
echo ""

# Show route details
echo -e "${YELLOW}Route Configuration:${NC}"
oc get route che -n ${NAMESPACE} -o yaml | grep -A5 "spec:" | grep -E "host:|tls:|termination:"
echo ""

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                     SOLUTIONS                              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}SOLUTION 1: SOCKS Proxy (Recommended for cluster-bot)${NC}"
echo ""
echo "If you have SSH access to a bastion/VPN server that can reach the cluster:"
echo ""
echo "  # Set up SOCKS proxy"
echo "  ssh -D 1080 -N user@<bastion-host>"
echo ""
echo "  # Configure Firefox (best for SOCKS)"
echo "  # Settings → Network Settings → Manual proxy"
echo "  # SOCKS Host: 127.0.0.1, Port: 1080, SOCKS v5"
echo "  # ✓ Proxy DNS when using SOCKS v5"
echo ""
echo "  # Then open in Firefox:"
echo "  ${CHE_URL}/dashboard/"
echo ""

echo -e "${GREEN}SOLUTION 2: /etc/hosts + SSH Tunnel${NC}"
echo ""
echo "If SOCKS doesn't work, use SSH tunnel with /etc/hosts:"
echo ""
echo "  # Get route IP from cluster"
echo "  ROUTE_IP=\$(oc get pod -n openshift-ingress -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default -o jsonpath='{.items[0].status.podIP}')"
echo ""
echo "  # Add to /etc/hosts (requires sudo)"
echo "  echo \"\${ROUTE_IP} ${ROUTE_HOST}\" | sudo tee -a /etc/hosts"
echo ""
echo "  # Create SSH tunnel to cluster node (if you have node SSH access)"
echo "  ssh -L 443:<ROUTE_IP>:443 user@<cluster-node>"
echo ""
echo "  # Access at:"
echo "  https://${ROUTE_HOST}/dashboard/"
echo ""

echo -e "${GREEN}SOLUTION 3: OpenShift Console Link${NC}"
echo ""
echo "Access Che via OpenShift Console (if console is accessible):"
echo ""
echo "  # Get console URL"
echo "  oc whoami --show-console"
echo ""
echo "  # Navigate to: Networking → Routes → ${NAMESPACE} → che"
echo "  # Click the route URL"
echo ""

echo -e "${GREEN}SOLUTION 4: Request Cluster with Public Access${NC}"
echo ""
echo "For testing that requires external access, request a different cluster type:"
echo ""
echo "  # Launch cluster with AWS (typically has public routes)"
echo "  launch 4.20.2 aws,ipv6"
echo ""

echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
