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

# IPv6 Test Infrastructure Deployment for Eclipse Che
#
# This script deploys test infrastructure on IPv6-only OpenShift clusters
# to validate Eclipse Che Dashboard PR-1442 IPv6 URL support.
#
# Infrastructure deployed:
# - Devfile HTTP server (serving sample devfiles via IPv6)
# - Git HTTP server (serving test repositories via IPv6)
# - Sample repositories and devfiles
#
# Prerequisites:
# - OpenShift cluster with IPv6 networking
# - oc CLI configured with cluster access
# - Eclipse Che deployed with PR-1442 dashboard
#
# Usage:
#   ./test-ipv6-validation.sh [options]
#
# Options:
#   --namespace <ns>      Test infrastructure namespace (default: che-test)
#   --che-namespace <ns>  Che namespace (default: eclipse-che)
#   --cleanup            Remove test infrastructure
#   --help               Show this help message

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
NAMESPACE="che-test"
CHE_NAMESPACE="eclipse-che"
CLEANUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --che-namespace)
            CHE_NAMESPACE="$2"
            shift 2
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

# Cleanup mode
if [ "$CLEANUP" == "true" ]; then
    echo -e "${YELLOW}Cleaning up test infrastructure...${NC}"
    oc delete namespace ${NAMESPACE} --ignore-not-found=true
    echo -e "${GREEN}✓ Test infrastructure removed${NC}"
    exit 0
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    Deploying IPv6 Test Infrastructure for Che Dashboard   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Step 1: Checking prerequisites${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: oc command not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ oc CLI found${NC}"

if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged into OpenShift cluster${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Logged into cluster as $(oc whoami)${NC}"

# Check if cluster has IPv6
IPV6_SERVICE=$(oc get network.config.openshift.io cluster -o jsonpath='{.status.serviceNetwork[1]}' 2>/dev/null || echo "")
if [ -z "$IPV6_SERVICE" ]; then
    echo -e "${YELLOW}⚠ Warning: Cluster may not have IPv6 networking${NC}"
else
    echo -e "${GREEN}✓ Cluster has IPv6 service network: ${IPV6_SERVICE}${NC}"
fi

echo ""

# Create namespace
echo -e "${YELLOW}Step 2: Creating test namespace${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

oc create namespace ${NAMESPACE} --dry-run=client -o yaml | oc apply -f -
echo -e "${GREEN}✓ Namespace ${NAMESPACE} ready${NC}"
echo ""

# Create sample devfiles
echo -e "${YELLOW}Step 3: Creating sample devfiles${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

cat <<'EOF' | oc apply -n ${NAMESPACE} -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nodejs-devfile
data:
  devfile.yaml: |
    schemaVersion: 2.2.0
    metadata:
      name: nodejs-hello-world
      displayName: Node.js Hello World
      description: Simple Node.js application for testing IPv6
      tags: ["NodeJS", "Express", "IPv6"]
      projectType: "nodejs"
    components:
      - name: nodejs
        container:
          image: registry.access.redhat.com/ubi8/nodejs-18:latest
          memoryLimit: 1024Mi
          mountSources: true
          endpoints:
            - name: http-3000
              targetPort: 3000
    commands:
      - id: install
        exec:
          component: nodejs
          commandLine: npm install
          workingDir: ${PROJECT_SOURCE}
      - id: run
        exec:
          component: nodejs
          commandLine: npm start
          workingDir: ${PROJECT_SOURCE}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: python-devfile
data:
  devfile.yaml: |
    schemaVersion: 2.2.0
    metadata:
      name: python-hello-world
      displayName: Python Hello World
      description: Simple Python application for testing IPv6
      tags: ["Python", "Flask", "IPv6"]
      projectType: "python"
    components:
      - name: python
        container:
          image: registry.access.redhat.com/ubi8/python-39:latest
          memoryLimit: 1024Mi
          mountSources: true
          endpoints:
            - name: http-8080
              targetPort: 8080
    commands:
      - id: install
        exec:
          component: python
          commandLine: pip install -r requirements.txt
          workingDir: ${PROJECT_SOURCE}
      - id: run
        exec:
          component: python
          commandLine: python app.py
          workingDir: ${PROJECT_SOURCE}
EOF

echo -e "${GREEN}✓ Sample devfiles created${NC}"
echo ""

# Create sample repositories
echo -e "${YELLOW}Step 4: Creating sample git repositories${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

cat <<'EOF' | oc apply -n ${NAMESPACE} -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nodejs-repo
data:
  package.json: |
    {
      "name": "nodejs-hello-world",
      "version": "1.0.0",
      "description": "Simple Node.js app for IPv6 testing",
      "main": "server.js",
      "scripts": {
        "start": "node server.js"
      },
      "dependencies": {
        "express": "^4.18.0"
      }
    }
  server.js: |
    const express = require('express');
    const app = express();
    const port = 3000;

    app.get('/', (req, res) => {
      res.send('Hello from IPv6 Node.js application!');
    });

    app.listen(port, () => {
      console.log(`Server running on port ${port}`);
    });
  README.md: |
    # Node.js Hello World - IPv6 Test

    This is a simple Node.js application for testing Eclipse Che with IPv6.

    ## Run
    ```
    npm install
    npm start
    ```
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: python-repo
data:
  app.py: |
    from flask import Flask
    app = Flask(__name__)

    @app.route('/')
    def hello():
        return 'Hello from IPv6 Python application!'

    if __name__ == '__main__':
        app.run(host='0.0.0.0', port=8080)
  requirements.txt: |
    Flask==3.0.0
  README.md: |
    # Python Hello World - IPv6 Test

    This is a simple Python application for testing Eclipse Che with IPv6.

    ## Run
    ```
    pip install -r requirements.txt
    python app.py
    ```
EOF

echo -e "${GREEN}✓ Sample repositories created${NC}"
echo ""

# Deploy devfile HTTP server
echo -e "${YELLOW}Step 5: Deploying devfile HTTP server${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

cat <<EOF | oc apply -n ${NAMESPACE} -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: devfile-server
  labels:
    app: devfile-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: devfile-server
  template:
    metadata:
      labels:
        app: devfile-server
    spec:
      containers:
      - name: server
        image: python:3.11-alpine
        command:
          - sh
          - -c
          - |
            # Create directory structure
            mkdir -p /devfiles/nodejs /devfiles/python

            # Copy devfiles from ConfigMaps
            cp /config/nodejs/devfile.yaml /devfiles/nodejs/devfile.yaml
            cp /config/python/devfile.yaml /devfiles/python/devfile.yaml

            # Create index
            cat > /devfiles/index.json <<'INDEX'
            [
              {
                "name": "nodejs-hello-world",
                "displayName": "Node.js Hello World",
                "description": "Simple Node.js application for IPv6 testing",
                "type": "stack",
                "tags": ["NodeJS", "Express", "IPv6"],
                "url": "/devfiles/nodejs/devfile.yaml"
              },
              {
                "name": "python-hello-world",
                "displayName": "Python Hello World",
                "description": "Simple Python application for IPv6 testing",
                "type": "stack",
                "tags": ["Python", "Flask", "IPv6"],
                "url": "/devfiles/python/devfile.yaml"
              }
            ]
            INDEX

            # Start HTTP server on all interfaces (:: for IPv4 and IPv6)
            cd /devfiles
            echo "Starting devfile HTTP server on port 8080..."
            python3 -m http.server 8080 --bind ::
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        volumeMounts:
        - name: nodejs-devfile
          mountPath: /config/nodejs
        - name: python-devfile
          mountPath: /config/python
        resources:
          limits:
            memory: 128Mi
          requests:
            memory: 64Mi
      volumes:
      - name: nodejs-devfile
        configMap:
          name: nodejs-devfile
      - name: python-devfile
        configMap:
          name: python-devfile
---
apiVersion: v1
kind: Service
metadata:
  name: devfile-server
  labels:
    app: devfile-server
spec:
  type: ClusterIP
  ipFamilyPolicy: PreferDualStack
  ipFamilies:
    - IPv6
    - IPv4
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
    name: http
  selector:
    app: devfile-server
EOF

echo -e "${GREEN}✓ Devfile server deployed${NC}"
echo ""

# Deploy git HTTP server
echo -e "${YELLOW}Step 6: Deploying git HTTP server${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

cat <<EOF | oc apply -n ${NAMESPACE} -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: git-server
  labels:
    app: git-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: git-server
  template:
    metadata:
      labels:
        app: git-server
    spec:
      containers:
      - name: server
        image: alpine/git:latest
        command:
          - sh
          - -c
          - |
            # Install lighttpd for HTTP server
            apk add --no-cache lighttpd

            # Create git repositories
            mkdir -p /repos/nodejs-hello-world.git
            mkdir -p /repos/python-hello-world.git

            # Initialize nodejs repository
            cd /repos/nodejs-hello-world.git
            git init --bare
            git config --local http.receivepack true
            git config --local http.uploadpack true

            # Create working copy and commit files
            TEMP_DIR=\$(mktemp -d)
            cd \$TEMP_DIR
            git init
            cp /config/nodejs/* .
            git add .
            git commit -m "Initial commit"
            git push file:///repos/nodejs-hello-world.git master
            cd /

            # Initialize python repository
            cd /repos/python-hello-world.git
            git init --bare
            git config --local http.receivepack true
            git config --local http.uploadpack true

            # Create working copy and commit files
            TEMP_DIR=\$(mktemp -d)
            cd \$TEMP_DIR
            git init
            cp /config/python/* .
            git add .
            git commit -m "Initial commit"
            git push file:///repos/python-hello-world.git master
            cd /

            # Update git server info
            cd /repos/nodejs-hello-world.git
            git update-server-info
            cd /repos/python-hello-world.git
            git update-server-info

            # Configure lighttpd
            cat > /etc/lighttpd/lighttpd.conf <<'LIGHTTPD'
            server.modules = (
                "mod_access",
                "mod_alias",
                "mod_cgi",
                "mod_setenv"
            )

            server.document-root = "/repos"
            server.port = 8080
            server.bind = "::"

            mimetype.assign = (
                ".git" => "application/x-git"
            )

            \$HTTP["url"] =~ "^/[^/]+\.git/git-upload-pack" {
                cgi.assign = ( "" => "/usr/libexec/git-core/git-http-backend" )
                setenv.add-environment = (
                    "GIT_PROJECT_ROOT" => "/repos",
                    "GIT_HTTP_EXPORT_ALL" => "1"
                )
            }

            \$HTTP["url"] =~ "^/[^/]+\.git/git-receive-pack" {
                cgi.assign = ( "" => "/usr/libexec/git-core/git-http-backend" )
                setenv.add-environment = (
                    "GIT_PROJECT_ROOT" => "/repos",
                    "GIT_HTTP_EXPORT_ALL" => "1"
                )
            }

            \$HTTP["url"] =~ "^/[^/]+\.git/info/refs" {
                cgi.assign = ( "" => "/usr/libexec/git-core/git-http-backend" )
                setenv.add-environment = (
                    "GIT_PROJECT_ROOT" => "/repos",
                    "GIT_HTTP_EXPORT_ALL" => "1"
                )
            }
            LIGHTTPD

            # Start lighttpd
            echo "Starting git HTTP server on port 8080..."
            lighttpd -D -f /etc/lighttpd/lighttpd.conf
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        volumeMounts:
        - name: nodejs-repo
          mountPath: /config/nodejs
        - name: python-repo
          mountPath: /config/python
        resources:
          limits:
            memory: 256Mi
          requests:
            memory: 128Mi
      volumes:
      - name: nodejs-repo
        configMap:
          name: nodejs-repo
      - name: python-repo
        configMap:
          name: python-repo
---
apiVersion: v1
kind: Service
metadata:
  name: git-server
  labels:
    app: git-server
spec:
  type: ClusterIP
  ipFamilyPolicy: PreferDualStack
  ipFamilies:
    - IPv6
    - IPv4
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
    name: http
  selector:
    app: git-server
EOF

echo -e "${GREEN}✓ Git server deployed${NC}"
echo ""

# Wait for deployments
echo -e "${YELLOW}Step 7: Waiting for services to be ready${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

echo "Waiting for devfile-server..."
oc rollout status deployment/devfile-server -n ${NAMESPACE} --timeout=120s
echo -e "${GREEN}✓ Devfile server ready${NC}"

echo "Waiting for git-server..."
oc rollout status deployment/git-server -n ${NAMESPACE} --timeout=120s
echo -e "${GREEN}✓ Git server ready${NC}"

echo ""

# Get service IPs
echo -e "${YELLOW}Step 8: Retrieving service information${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

DEVFILE_IPV6=$(oc get service devfile-server -n ${NAMESPACE} -o jsonpath='{.spec.clusterIPs[0]}')
DEVFILE_IPV4=$(oc get service devfile-server -n ${NAMESPACE} -o jsonpath='{.spec.clusterIPs[1]}' 2>/dev/null || echo "N/A")
GIT_IPV6=$(oc get service git-server -n ${NAMESPACE} -o jsonpath='{.spec.clusterIPs[0]}')
GIT_IPV4=$(oc get service git-server -n ${NAMESPACE} -o jsonpath='{.spec.clusterIPs[1]}' 2>/dev/null || echo "N/A")

echo -e "${BLUE}Service Information:${NC}"
echo ""
echo "Devfile Server:"
echo "  IPv6 Address: ${DEVFILE_IPV6}"
echo "  IPv4 Address: ${DEVFILE_IPV4}"
echo "  Service Name: devfile-server.${NAMESPACE}.svc.cluster.local"
echo ""
echo "Git Server:"
echo "  IPv6 Address: ${GIT_IPV6}"
echo "  IPv4 Address: ${GIT_IPV4}"
echo "  Service Name: git-server.${NAMESPACE}.svc.cluster.local"
echo ""

# Test URLs
echo -e "${YELLOW}Step 9: Testing service accessibility${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

# Test devfile server
echo "Testing devfile server..."
TEST_POD=$(oc run test-curl --image=curlimages/curl:latest --rm -i --restart=Never -n ${NAMESPACE} -- curl -s "http://[${DEVFILE_IPV6}]:8080/index.json" 2>&1 || echo "")
if echo "$TEST_POD" | grep -q "nodejs-hello-world"; then
    echo -e "${GREEN}✓ Devfile server responding on IPv6${NC}"
else
    echo -e "${YELLOW}⚠ Could not verify devfile server on IPv6${NC}"
fi

# Test git server
echo "Testing git server..."
TEST_POD=$(oc run test-curl --image=curlimages/curl:latest --rm -i --restart=Never -n ${NAMESPACE} -- curl -s "http://[${GIT_IPV6}]:8080/nodejs-hello-world.git/info/refs?service=git-upload-pack" 2>&1 || echo "")
if echo "$TEST_POD" | grep -q "git-upload-pack"; then
    echo -e "${GREEN}✓ Git server responding on IPv6${NC}"
else
    echo -e "${YELLOW}⚠ Could not verify git server on IPv6${NC}"
fi

echo ""

# Display test URLs
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Test Infrastructure Deployed Successfully!             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}IPv6 Test URLs for Eclipse Che Factory:${NC}"
echo ""
echo "Node.js Hello World (via IPv6):"
echo "  http://[${GIT_IPV6}]:8080/nodejs-hello-world.git"
echo "  with devfile: http://[${GIT_IPV6}]:8080/nodejs-hello-world.git?df=http://[${DEVFILE_IPV6}]:8080/devfiles/nodejs/devfile.yaml"
echo ""
echo "Python Hello World (via IPv6):"
echo "  http://[${GIT_IPV6}]:8080/python-hello-world.git"
echo "  with devfile: http://[${GIT_IPV6}]:8080/python-hello-world.git?df=http://[${DEVFILE_IPV6}]:8080/devfiles/python/devfile.yaml"
echo ""

echo -e "${BLUE}Testing with Che Dashboard:${NC}"
echo ""
echo "1. Get Che URL:"
echo "   CHE_URL=\$(oc get checluster eclipse-che -n ${CHE_NAMESPACE} -o jsonpath='{.status.cheURL}')"
echo "   echo \$CHE_URL"
echo ""
echo "2. Open factory URL in browser:"
echo "   \${CHE_URL}/#http://[${GIT_IPV6}]:8080/nodejs-hello-world.git"
echo ""
echo "3. Verify workspace creation succeeds with IPv6 URL"
echo ""

echo -e "${BLUE}Cleanup:${NC}"
echo "  ./test-ipv6-validation.sh --cleanup"
echo ""

echo -e "${GREEN}✓ Ready for IPv6 testing!${NC}"
