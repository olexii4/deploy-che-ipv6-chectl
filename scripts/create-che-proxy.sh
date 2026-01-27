#!/bin/bash
#
# Create HTTP Proxy Pod for Che Access
#
# This creates a proxy pod inside the cluster that can access Che,
# then you port-forward to this proxy to access Che from your laptop.
#
# This is a workaround for when:
# - VPN credentials don't work
# - Route is not directly accessible
# - You need OAuth to work (unlike direct port-forward)
#

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="${1:-eclipse-che}"

echo -e "${BLUE}Creating HTTP proxy pod for Che access...${NC}"
echo ""

# Get Che route hostname
ROUTE_HOST=$(oc get route che -n ${NAMESPACE} -o jsonpath='{.spec.host}')
CHE_URL=$(oc get checluster eclipse-che -n ${NAMESPACE} -o jsonpath='{.status.cheURL}')

echo "Che URL: ${CHE_URL}"
echo "Route Host: ${ROUTE_HOST}"
echo ""

# Create proxy pod using nginx
cat <<EOF | oc apply -n ${NAMESPACE} -f -
apiVersion: v1
kind: Pod
metadata:
  name: che-proxy
  labels:
    app: che-proxy
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    ports:
    - containerPort: 8080
      name: http
    volumeMounts:
    - name: nginx-config
      mountPath: /etc/nginx/nginx.conf
      subPath: nginx.conf
  volumes:
  - name: nginx-config
    configMap:
      name: che-proxy-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: che-proxy-config
data:
  nginx.conf: |
    events {
        worker_connections 1024;
    }
    http {
        server {
            listen 8080;

            location / {
                # Proxy to Che service (internal cluster access)
                proxy_pass https://che-host.${NAMESPACE}.svc.cluster.local:8080;
                proxy_ssl_verify off;

                # Preserve original host for OAuth redirects
                proxy_set_header Host ${ROUTE_HOST};
                proxy_set_header X-Real-IP \$remote_addr;
                proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto https;
                proxy_set_header X-Forwarded-Host ${ROUTE_HOST};

                # WebSocket support
                proxy_http_version 1.1;
                proxy_set_header Upgrade \$http_upgrade;
                proxy_set_header Connection "upgrade";
            }
        }
    }
EOF

echo ""
echo -e "${YELLOW}Waiting for proxy pod to be ready...${NC}"
oc wait --for=condition=Ready pod/che-proxy -n ${NAMESPACE} --timeout=60s

echo ""
echo -e "${GREEN}✓ Proxy pod created successfully${NC}"
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Access Che via Proxy Pod                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Run this command to start port-forward:"
echo ""
echo -e "${GREEN}  oc port-forward -n ${NAMESPACE} pod/che-proxy 8080:8080${NC}"
echo ""
echo "Then access Che at:"
echo ""
echo -e "${GREEN}  http://localhost:8080/dashboard/${NC}"
echo ""
echo -e "${YELLOW}Note: OAuth might still have issues with this approach.${NC}"
echo -e "${YELLOW}If OAuth fails, this won't work either.${NC}"
echo ""
echo "To remove the proxy pod:"
echo "  oc delete pod/che-proxy configmap/che-proxy-config -n ${NAMESPACE}"
echo ""
