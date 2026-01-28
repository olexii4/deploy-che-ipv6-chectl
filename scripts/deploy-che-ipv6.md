<!--
Copyright (c) 2026 Red Hat, Inc.
This program and the accompanying materials are made
available under the terms of the Eclipse Public License 2.0
which is available at https://www.eclipse.org/legal/epl-2.0/

SPDX-License-Identifier: EPL-2.0

Contributors:
  Red Hat, Inc. - initial API and implementation
-->

# Deploy Eclipse Che with IPv6 Support on OpenShift

This guide provides instructions for deploying Eclipse Che with IPv6 support on OpenShift clusters using chectl.

**Dashboard Image:** `quay.io/eclipse/che-dashboard:pr-1442`
**Feature:** IPv6 URL validation and dual-stack network support
**Related Issue:** [#23674](https://github.com/eclipse-che/che/issues/23674)
**Target Platform:** OpenShift 4.20.2+ with IPv6 support

---

## Table of Contents

- [Overview](#overview)
- [Creating IPv6 OpenShift Cluster](#creating-ipv6-openshift-cluster)
- [Prerequisites](#prerequisites)
- [Deployment Steps](#deployment-steps)
- [Configuration](#configuration)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

---

## Overview

This deployment guide covers Eclipse Che with IPv6 support enhancements for OpenShift:

✅ **Backend dual-stack support** - Server binds to `::` (IPv4 and IPv6)
✅ **IPv6 URL validation** - Dashboard accepts URLs like `http://[::1]:8080/repo.git`
✅ **Container registry IPv6** - Registry URLs support IPv6 addresses
✅ **Git repository IPv6** - Factory URLs support IPv6 Git repositories
✅ **IPv4-mapped IPv6** - Support for addresses like `::ffff:192.168.1.1`

### Code Changes Summary

The PR-1442 implements the following IPv6 enhancements:

1. **Backend Server** (`packages/dashboard-backend/src/server.ts`)
   - Changed host binding from `0.0.0.0` to `::` for dual-stack support

2. **URL Validation** (`packages/dashboard-frontend/src/services/factory-location-adapter/index.ts`)
   - Updated regex: `/^(http(s)?:\/\/)((\w[\w.-]*)|(\[[0-9a-fA-F:.]+\]))(:\d+)?([-a-zA-Z0-9@:%._+~#=/[\]?&{}, ]*)$/`
   - Support for IPv6 addresses in square brackets: `http://[2001:db8::1]/repo.git`
   - Support for IPv4-mapped IPv6: `http://[::ffff:10.217.0.98]:8080/repo.git`

3. **Git Client** (`packages/dashboard-backend/src/services/gitClient/index.ts`)
   - Updated URL regex to handle IPv6 addresses: added `\[` and `\]` to character class

4. **Container Registry** (`pages/UserPreferences/ContainerRegistriesTab/RegistryUrl/index.tsx`)
   - Registry URL validation supports IPv6 format: `^http[s]?://((\\w[\\w.-]*)|([[0-9a-fA-F:]+]))(:\\d+)?(/.*)?$`

---

## Creating IPv6 OpenShift Cluster

### Option 1: OpenShift CI Cluster Bot (Recommended for Testing)

Access the OpenShift CI cluster bot via Slack to provision a temporary IPv6 cluster.

**Recommended Command for Eclipse Che Testing:**
```bash
launch 4.20.2 metal,ipv6
```

**Why This Configuration:**
- ✅ **IPv6-only networking** - Pure IPv6 environment for thorough IPv6 URL validation testing
- ✅ **Standard cluster** - Adequate resources for Eclipse Che + workspaces
- ✅ **Metal platform** - Stable baremetal environment for comprehensive testing
- ✅ **OpenShift 4.20.2** - Latest stable release with IPv6 improvements


**After Launch:**

1. The bot will respond with cluster credentials and kubeconfig
2. Save the kubeconfig to a file:
   ```bash
   cat > ~/ostest-kubeconfig.yaml << 'EOF'
   # Paste the kubeconfig content from cluster bot here
   # (includes proxy-url for cluster access)
   EOF
   ```

3. Verify cluster access:
   ```bash
   export KUBECONFIG=~/ostest-kubeconfig.yaml
   oc get nodes
   oc whoami
   ```

   Or use the `--kubeconfig` flag with deployment scripts (recommended):
   ```bash
   ./scripts/deploy-che-ipv6-chectl.sh --kubeconfig ~/ostest-kubeconfig.yaml
   ```

5. **Cluster Lifetime:** Cluster bot clusters are temporary (typically 4-6 hours)

### Option 2: OpenShift Local (CRC) - Limited IPv6 Support

> ⚠️ **Warning:** CRC does not support IPv6 networking (IPv4-only). Use CRC only for testing URL validation features, not for actual IPv6 connectivity.

```bash
# Start CRC
crc start

# Configure oc
eval $(crc oc-env)

# Login
oc login -u kubeadmin https://api.crc.testing:6443
```

**CRC Limitations:**
- ✅ IPv6 URL validation works
- ✅ Backend binds to `::` (dual-stack ready)
- ❌ No IPv6 services (cluster is IPv4-only)
- ❌ Cannot test actual IPv6 connectivity

For comprehensive IPv6 testing, use cluster bot with `metal,ipv6` or cloud platforms.

---

## Prerequisites

### Required Tools

**1. oc CLI** - OpenShift command-line tool
```bash
# Verify installation
oc version

# Download if needed
# https://mirror.openshift.com/pub/openshift-v4/clients/ocp/
```

**2. chectl** - Eclipse Che CLI tool
```bash
# Install using installer script
bash <(curl -sL https://che-incubator.github.io/chectl/install.sh)

# Or using npm
npm install -g chectl

# Verify installation
chectl version
```

**3. Cluster Access**

Ensure you have:
- Valid kubeconfig for your OpenShift cluster
- Cluster-admin permissions (or sufficient RBAC for Che deployment)
- Network access to cluster API and routes

### Verify OpenShift Cluster IPv6 Support

```bash
# Check cluster network configuration
oc get network.config.openshift.io cluster -o yaml | grep -A 10 "serviceNetwork"

# Expected output for IPv6 or dual-stack:
# serviceNetwork:
# - fd00:10:96::/112  (IPv6)
# - 10.96.0.0/16      (IPv4 - if dual-stack)

# Check pod network
oc get network.config.openshift.io cluster -o yaml | grep -A 10 "clusterNetwork"

# Expected output:
# clusterNetwork:
# - cidr: fd00:10:244::/56  (IPv6)
# - cidr: 10.244.0.0/16     (IPv4 - if dual-stack)

# Verify service IP families
oc get svc -A -o custom-columns=\
NAME:.metadata.name,\
IP-POLICY:.spec.ipFamilyPolicy,\
IPs:.spec.clusterIPs | head -20

# Expected: IP-POLICY shows "PreferDualStack" or "RequireDualStack"
```

---

## Deployment Steps

### Quick Start

For OpenShift clusters with IPv6 support:

```bash
# 1. Verify cluster access
oc whoami
oc get nodes

# 2. Deploy Eclipse Che with custom dashboard
chectl server:deploy \
  --platform openshift \
  --che-operator-image quay.io/eclipse/che-operator:next \
  --installer operator

# 3. Patch CheCluster to use PR-1442 dashboard
oc patch checluster eclipse-che -n eclipse-che --type merge -p '
{
  "spec": {
    "components": {
      "dashboard": {
        "deployment": {
          "containers": [{
            "image": "quay.io/eclipse/che-dashboard:pr-1442",
            "imagePullPolicy": "Always",
            "name": "che-dashboard"
          }]
        }
      }
    }
  }
}'

# 4. Wait for rollout
oc rollout status deployment/che-dashboard -n eclipse-che

# 5. Get Che URL
CHE_URL=$(oc get checluster eclipse-che -n eclipse-che -o jsonpath='{.status.cheURL}')
echo "Eclipse Che URL: $CHE_URL"
```

### Step-by-Step Deployment

#### Step 1: Login to OpenShift

```bash
# If using cluster bot, save kubeconfig to file
cat > ~/ostest-kubeconfig.yaml << 'EOF'
# Paste the kubeconfig content from cluster bot here
# (includes proxy-url for cluster access)
EOF

# Set kubeconfig
export KUBECONFIG=~/ostest-kubeconfig.yaml

# Verify login
oc whoami
oc cluster-info
```

#### Step 2: Deploy Eclipse Che with chectl

```bash
# Deploy Che using operator installer
chectl server:deploy \
  --platform openshift \
  --installer operator \
  --chenamespace eclipse-che

# Monitor deployment progress
chectl server:status
```

#### Step 3: Update Dashboard Image to PR-1442

Create a patch file:

```bash
cat > che-dashboard-patch.yaml <<EOF
spec:
  components:
    dashboard:
      deployment:
        containers:
          - image: 'quay.io/eclipse/che-dashboard:pr-1442'
            imagePullPolicy: Always
            name: che-dashboard
EOF
```

Apply the patch:

```bash
# Patch CheCluster
oc patch checluster eclipse-che -n eclipse-che \
  --type merge --patch-file che-dashboard-patch.yaml

# Wait for new pod to be ready
oc rollout status deployment/che-dashboard -n eclipse-che --timeout=5m
```

#### Step 4: Verify Deployment

```bash
# Check dashboard pod
oc get pods -n eclipse-che -l app=che-dashboard

# Verify dashboard image
oc get deployment che-dashboard -n eclipse-che \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Expected: quay.io/eclipse/che-dashboard:pr-1442

# Get Che URL
oc get checluster eclipse-che -n eclipse-che -o jsonpath='{.status.cheURL}'
```

---

## Configuration

### Custom CheCluster Configuration

For more control, create a custom CheCluster resource:

```yaml
# che-cluster-ipv6.yaml
apiVersion: org.eclipse.che/v2
kind: CheCluster
metadata:
  name: eclipse-che
  namespace: eclipse-che
spec:
  components:
    # Use PR-1442 dashboard image with IPv6 support
    dashboard:
      deployment:
        containers:
          - image: 'quay.io/eclipse/che-dashboard:pr-1442'
            imagePullPolicy: Always
            name: che-dashboard

    # Disable metrics (optional - for resource-constrained environments)
    metrics:
      enable: false

  # Networking configuration
  networking:
    # Domain is automatically configured on OpenShift
    # Override if needed:
    # domain: apps.your-cluster.example.com

    # TLS is automatically configured via OpenShift routes
    # tlsSecretName: che-tls

    # Gateway configuration for OAuth
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

  # DevWorkspace operator configuration
  devEnvironments:
    # Default editor
    defaultEditor: che-incubator/che-code/latest

    # Storage configuration
    storage:
      pvcStrategy: per-workspace
```

Apply the configuration:

```bash
# Delete existing CheCluster (if needed)
oc delete checluster eclipse-che -n eclipse-che

# Create namespace
oc create namespace eclipse-che

# Apply custom configuration
oc apply -f che-cluster-ipv6.yaml

# Wait for deployment
oc wait --for=condition=Available deployment/che-dashboard -n eclipse-che --timeout=10m
```

### Deploy with Custom Configuration Using chectl

```bash
chectl server:deploy \
  --platform openshift \
  --che-operator-cr-yaml=che-cluster-ipv6.yaml \
  --chenamespace eclipse-che
```

---

## Verification

### 1. Check Deployment Status

```bash
# Check all Che pods
oc get pods -n eclipse-che

# Expected pods:
# - che-operator-xxx
# - che-xxx (che server)
# - che-dashboard-xxx
# - che-gateway-xxx

# Check CheCluster status
oc get checluster eclipse-che -n eclipse-che -o yaml | grep -A 10 "status:"
```

### 2. Verify IPv6 Support

```bash
# Check dashboard pod IPs
oc get pods -n eclipse-che -l app=che-dashboard -o wide

# Get detailed IP information
DASHBOARD_POD=$(oc get pods -n eclipse-che -l app=che-dashboard -o jsonpath='{.items[0].metadata.name}')

oc get pod $DASHBOARD_POD -n eclipse-che -o jsonpath='{.status.podIPs[*].ip}' | tr ' ' '\n'

# Expected output (dual-stack):
# 10.244.1.5      (IPv4)
# fd00:10:244::5  (IPv6)
```

### 3. Check Service Configuration

```bash
# Verify services have dual-stack configuration
oc get svc -n eclipse-che -o custom-columns=\
NAME:.metadata.name,\
TYPE:.spec.type,\
IP-POLICY:.spec.ipFamilyPolicy,\
CLUSTER-IPS:.spec.clusterIPs

# Expected output:
# NAME              TYPE        IP-POLICY         CLUSTER-IPS
# che-dashboard     ClusterIP   PreferDualStack   [10.96.x.x, fd00:10:96::x]
# che-host          ClusterIP   PreferDualStack   [10.96.x.x, fd00:10:96::x]
```

### 4. Test Dashboard Access

```bash
# Get Che URL
CHE_URL=$(oc get checluster eclipse-che -n eclipse-che -o jsonpath='{.status.cheURL}')
echo "Che URL: $CHE_URL"

# Test HTTP access
curl -k ${CHE_URL}/dashboard/

# Expected: HTML content or redirect to login
```

### 5. Verify Backend Dual-Stack Binding

```bash
# Check if backend listens on both IPv4 and IPv6
oc exec -n eclipse-che $DASHBOARD_POD -- sh -c "netstat -tlnp 2>/dev/null || ss -tlnp" | grep :8080

# Expected output:
# tcp6       0      0 :::8080                 :::*                    LISTEN
# (This means listening on both IPv4 and IPv6)
```

### 6. Test IPv6 URL Validation

Access the dashboard and test in browser console:

```javascript
// Open: https://<che-url>/dashboard/
// Browser Console (F12):

const regex = /^(http(s)?:\/\/)((\w[\w.-]*)|(\[[0-9a-fA-F:.]+\]))(:\d+)?([-a-zA-Z0-9@:%._+~#=/[\]?&{}, ]*)$/;

console.log('IPv6 loopback:', regex.test('http://[::1]:8080/repo.git'));
// Expected: true ✅

console.log('IPv6 address:', regex.test('http://[2001:db8::1]/path'));
// Expected: true ✅

console.log('IPv4-mapped IPv6:', regex.test('http://[::ffff:192.168.1.1]:8080/repo.git'));
// Expected: true ✅
```

---

## Troubleshooting

### Issue 1: Dashboard Pod Not Starting

**Symptoms:**
```bash
oc get pods -n eclipse-che
# che-dashboard-xxx   0/1     ImagePullBackOff
```

**Solution:**

```bash
# Check pod events
oc describe pod -n eclipse-che -l app=che-dashboard

# Verify image exists
podman pull quay.io/eclipse/che-dashboard:pr-1442

# Check for typos in CheCluster
oc get checluster eclipse-che -n eclipse-che -o yaml | grep -A 5 "dashboard:"

# Force pod recreation
oc delete pod -n eclipse-che -l app=che-dashboard
```

### Issue 2: Cluster Does Not Support IPv6

**Symptoms:**
```bash
oc get network.config.openshift.io cluster -o yaml | grep serviceNetwork
# serviceNetwork:
# - 10.96.0.0/16  (only IPv4)
```

**Solution:**

The cluster is IPv4-only. You can still deploy Che with PR-1442 dashboard:
- ✅ IPv6 URL validation will work
- ✅ Backend will bind to `::` (dual-stack ready)
- ❌ Cannot test actual IPv6 connectivity

For dual-stack IPv6 testing, launch a new cluster with cluster bot:
```
launch 4.20.2 metal,ipv6
```

### Issue 3: Cannot Access Dashboard

**Symptoms:**

Browser cannot load Che URL

**Solution:**

```bash
# Check route
oc get route -n eclipse-che

# Verify route host
oc get route che -n eclipse-che -o jsonpath='{.spec.host}'

# Check if pods are running
oc get pods -n eclipse-che

# Port-forward for direct access
oc port-forward -n eclipse-che svc/che-host 8080:8080
# Then access: http://localhost:8080/dashboard/

# Check dashboard logs
oc logs -n eclipse-che -l app=che-dashboard --tail=50 -f
```

### Issue 4: IPv6 URLs Show "Invalid URL" Error

**Symptoms:**

Dashboard shows validation error for `http://[::1]:8080/repo.git`

**Solution:**

Verify dashboard image:

```bash
# Check current image
oc get deployment che-dashboard -n eclipse-che \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Should be: quay.io/eclipse/che-dashboard:pr-1442

# If wrong, patch:
oc patch checluster eclipse-che -n eclipse-che --type merge -p '
{
  "spec": {
    "components": {
      "dashboard": {
        "deployment": {
          "containers": [{
            "image": "quay.io/eclipse/che-dashboard:pr-1442",
            "imagePullPolicy": "Always",
            "name": "che-dashboard"
          }]
        }
      }
    }
  }
}'

# Wait for rollout
oc rollout status deployment/che-dashboard -n eclipse-che
```

### Issue 5: chectl Deployment Fails

**Symptoms:**
```bash
chectl server:deploy
# Error: Platform openshift is not supported
```

**Solution:**

```bash
# Use correct platform flag
chectl server:deploy --platform openshift

# If cluster health check fails, skip it
chectl server:deploy \
  --platform openshift \
  --skip-kubernetes-health-check \
  --skip-version-check

# Verify cluster connectivity first
oc cluster-info
oc get nodes
```

### Issue 6: Cluster Bot Cluster Expired

**Symptoms:**

Kubeconfig no longer works after 4-6 hours

**Solution:**

Cluster bot clusters are temporary. Launch a new cluster:

```bash
# In Slack, send to cluster bot:
launch 4.20.2 metal,ipv6

# Download new kubeconfig
export KUBECONFIG=/path/to/new-kubeconfig

# Redeploy Che
chectl server:deploy --platform openshift
```

---

## Next Steps

After successful deployment:

1. **Test IPv6 URL Validation** - See [IPv6 Testing Guide](./test-ipv6-validation.md)
2. **Test Data Resolver API** - See [Data Resolver Testing](./testing-data-resolver-api.md)
3. **Create Workspaces** - Test workspace creation with IPv6 Git repositories
4. **Monitor Logs** - Check for any IPv6-related issues

---

## Additional Resources

- [OpenShift CI Cluster Bot](https://docs.ci.openshift.org/docs/how-tos/testing-with-test-platform/#requesting-a-cluster-from-dptp)
- [OpenShift Release Portal](https://amd64.ocp.releases.ci.openshift.org/)
- [Eclipse Che on OpenShift](https://eclipse.dev/che/docs/stable/administration-guide/installing-che-on-openshift-4-using-cli/)
- [chectl Documentation](https://github.com/che-incubator/chectl)
- [Issue #23674](https://github.com/eclipse-che/che/issues/23674)

---

**Document Version:** 2.0
**Last Updated:** 2026-01-26
**Dashboard Image:** `quay.io/eclipse/che-dashboard:pr-1442`
**Target Platform:** OpenShift 4.20.2+ with IPv6 support

<!-- Generated by Claude Sonnet 4.5 -->
