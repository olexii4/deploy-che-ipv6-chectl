# Diagnosing Eclipse Che Access Issues

This guide explains how to diagnose and resolve access issues when Eclipse Che is deployed but the dashboard is not reachable from your laptop.

## Overview

The `diagnose-che-access.sh` script helps identify why you cannot access Eclipse Che and provides specific solutions based on the failure mode.

**Common Problem**: Eclipse Che deploys successfully on cluster-bot IPv6 clusters, but the dashboard URL is not accessible from your laptop due to network isolation or DNS resolution issues.

## When to Use This Script

Run this script when:

- Eclipse Che deployment completes successfully (`chectl server:deploy` finishes)
- `oc get checluster eclipse-che -n eclipse-che` shows `chePhase: Active`
- But accessing the Che URL in your browser fails with:
  - `ERR_NAME_NOT_RESOLVED` (DNS failure)
  - `ERR_CONNECTION_REFUSED` or `ERR_CONNECTION_TIMED_OUT` (network unreachable)
  - Connection timeout or "No route to host"

## Usage

```bash
# Basic usage (uses default namespace: eclipse-che)
./scripts/diagnose-che-access.sh

# Specify custom Che namespace
./scripts/diagnose-che-access.sh my-che-namespace
```

## What the Script Tests

### Test 1: Cluster-Internal Access

**What it checks**: Can Che be accessed from within the cluster?

```bash
# Runs a curl pod inside the cluster to test Che URL
oc run che-test-access --image=curlimages/curl --rm -i \
  curl -sL -w "%{http_code}" "${CHE_URL}"
```

**Possible outcomes**:
- ✅ **HTTP 200/301/302**: Che is working, problem is external access
- ❌ **Failed/Timeout**: Che deployment or route is broken

**If this test fails**: Check Che pods and route configuration
```bash
oc get pods -n eclipse-che
oc get route che -n eclipse-che
oc logs -n eclipse-che -l app=che
```

### Test 2: DNS Resolution

**What it checks**: Can your laptop resolve the Che route hostname?

```bash
host che-eclipse-che.apps.<cluster>.origin-ci-int-gce.dev.rhcloud.com
```

**Possible outcomes**:
- ✅ **Resolves to IP**: DNS is working
- ❌ **NXDOMAIN/not found**: DNS cannot resolve cluster-bot hostname (expected for cluster-bot)

**Why this fails on cluster-bot**: Cluster-bot API hostnames use internal DNS zones not accessible from public internet.

### Test 3: Network Connectivity

**What it checks**: Can your laptop reach the Che URL over the network?

```bash
curl -sL --max-time 5 "${CHE_URL}"
```

**Possible outcomes**:
- ✅ **Succeeds**: Full access works (rare on cluster-bot)
- ❌ **Timeout/Refused**: Network route is blocked or requires VPN/proxy

**Why this fails**: Cluster-bot clusters often use HostNetwork ingress only reachable from Red Hat internal network.

### Test 4: OAuth Configuration

**What it checks**: OAuth redirect URIs and authentication setup

**Important**: This is why **port-forward doesn't work** for Che access:
- OAuth redirect URIs are configured for the route hostname (e.g., `https://che-eclipse-che.apps.<cluster>.example.com/...`)
- When you access via `http://localhost:8080`, OAuth redirects fail because:
  - Redirect URI mismatch (localhost vs route hostname)
  - HTTPS → HTTP protocol mismatch
  - OAuth state validation fails

## Solutions (Recommended Order)

The script recommends solutions based on test results. Here are the approaches in detail:

---

### Solution 1: SOCKS Proxy via SSH Bastion (Recommended)

**Best for**: Cluster-bot clusters where you have Red Hat VPN or bastion access

**Why it works**:
- Proxies all browser traffic (including DNS) through the bastion
- OAuth redirects work correctly (browser sees the real route URL)
- No configuration changes needed on cluster

**Prerequisites**:
- SSH access to a Red Hat VPN server or bastion host that can reach the cluster network

**Setup**:

```bash
# 1. Create SOCKS proxy tunnel (runs in background)
ssh -D 1080 -N -f your-username@bastion.redhat.com

# Explanation:
#   -D 1080: Create SOCKS proxy on local port 1080
#   -N: Don't execute remote command (just tunnel)
#   -f: Run in background

# 2. Verify SSH tunnel is running
ps aux | grep "ssh -D 1080"
```

**Firefox Configuration (Recommended)**:

Firefox has the best SOCKS proxy support with DNS proxying:

```
1. Open Firefox
2. Settings → Network Settings → Settings (button)
3. Select: ● Manual proxy configuration
4. SOCKS Host: 127.0.0.1
   Port: 1080
5. Select: ● SOCKS v5
6. ✓ Check: "Proxy DNS when using SOCKS v5"
7. Click OK

# Get Che URL
CHE_URL=$(oc get checluster eclipse-che -n eclipse-che -o jsonpath='{.status.cheURL}')

# Open in Firefox
echo "Access at: ${CHE_URL}/dashboard/"
```

**Chrome Configuration (macOS)**:

Chrome uses system proxy settings:

```
1. System Settings → Network
2. Select your active network interface (Wi-Fi/Ethernet)
3. Click "Details..."
4. Select "Proxies" tab
5. Check: ✓ SOCKS Proxy
   SOCKS proxy server: 127.0.0.1:1080
6. Click OK

# Then access Che URL in Chrome
```

**Cleanup**:

```bash
# Stop SOCKS proxy
pkill -f "ssh -D 1080"

# Remove proxy from browser (uncheck proxy settings)
```

---

### Solution 2: /etc/hosts + SSH Tunnel

**Best for**: When you have SSH access to cluster nodes

**How it works**: Map route hostname to cluster IP in /etc/hosts, tunnel HTTPS traffic via SSH

**Steps**:

```bash
# 1. Get route hostname
ROUTE_HOST=$(oc get route che -n eclipse-che -o jsonpath='{.spec.host}')

# 2. Get ingress router pod IP (or node IP)
ROUTER_IP=$(oc get pod -n openshift-ingress \
  -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default \
  -o jsonpath='{.items[0].status.hostIP}')

# 3. Add to /etc/hosts (requires sudo)
echo "${ROUTER_IP} ${ROUTE_HOST}" | sudo tee -a /etc/hosts

# 4. Verify DNS resolution now works
host ${ROUTE_HOST}
# Should show: ${ROUTE_HOST} has address ${ROUTER_IP}

# 5. If router IP is not directly reachable, create SSH tunnel
# (Assuming you have SSH access to a cluster node at ${ROUTER_IP})
ssh -L 443:${ROUTER_IP}:443 -N -f core@${ROUTER_IP}

# 6. Access Che
echo "Open in browser: https://${ROUTE_HOST}/dashboard/"
```

**Cleanup**:

```bash
# Remove /etc/hosts entry
sudo sed -i '' "/${ROUTE_HOST}/d" /etc/hosts  # macOS
sudo sed -i "/${ROUTE_HOST}/d" /etc/hosts     # Linux

# Stop SSH tunnel
pkill -f "ssh -L 443"
```

---

### Solution 3: OpenShift Console Access

**Best for**: When you can access OpenShift web console but not Che routes

**How it works**: If console is accessible, routes in same cluster should be accessible

**Steps**:

```bash
# 1. Get console URL
oc whoami --show-console

# Example: https://console-openshift-console.apps.<cluster>.example.com

# 2. Open console in browser and log in

# 3. Navigate to route:
#    Networking → Routes
#    Project: eclipse-che
#    Click "Location" link for 'che' route

# 4. This will open Che dashboard
```

**If console is accessible but Che route is not**:
- Check if route exists: `oc get route che -n eclipse-che`
- Check route TLS config: `oc get route che -n eclipse-che -o yaml`
- Verify Che pods are running: `oc get pods -n eclipse-che`

---

### Solution 4: Request Different Cluster Type

**Best for**: When testing requires real external access (e.g., sharing with team)

**How it works**: AWS clusters typically have public routes vs. bare-metal clusters with HostNetwork ingress

```bash
# Request AWS cluster instead of bare-metal
launch 4.20.2 aws,ipv6

# AWS clusters usually provide:
# - Publicly resolvable DNS
# - Public load balancers for routes
# - External access without VPN

# Note: Verify AWS supports IPv6 for your test requirements
```

---

## Troubleshooting

### Issue: "curl: (6) Could not resolve host"

**Cause**: DNS cannot resolve the route hostname

**Solution**: Use SOCKS proxy (Solution 1) which proxies DNS queries

---

### Issue: "Connection timeout" even with /etc/hosts

**Cause**: The route IP is not directly reachable from your network

**Solution**:
1. Use SOCKS proxy if you have bastion access
2. Or use SSH tunnel (Solution 2 step 5)

---

### Issue: OAuth redirect fails with "redirect_uri mismatch"

**Cause**: Accessing Che via port-forward or non-standard URL

**Why port-forward doesn't work**:
```
Configured OAuth redirect: https://che-<cluster>.example.com/oauth/callback
Your access URL:            http://localhost:8080/oauth/callback
Result:                     ❌ Mismatch → OAuth fails
```

**Solution**: Must access via the real route URL using SOCKS proxy or /etc/hosts

---

### Issue: SOCKS proxy works but very slow

**Cause**: All traffic (including images, fonts) goes through SSH tunnel

**Optimization**:
```bash
# Use compression in SSH tunnel
ssh -D 1080 -N -C -f user@bastion

# -C enables compression
```

---

### Issue: "ssh: connect to host bastion.redhat.com port 22: Connection refused"

**Cause**: No bastion/VPN access or SSH is blocked

**Solution**:
- Request VPN access from Red Hat IT
- Or use Solution 4 (request AWS cluster with public access)

---

## Quick Reference

| Problem | Best Solution |
|---------|---------------|
| DNS doesn't resolve route hostname | SOCKS Proxy (Solution 1) |
| Can ping route IP but not resolve hostname | /etc/hosts (Solution 2) |
| Have OpenShift console access | Console route link (Solution 3) |
| Need public/team access | AWS cluster (Solution 4) |
| Port-forward OAuth fails | Never use port-forward; use SOCKS proxy |

## Related Documentation

- [deploy-che-ipv6-chectl.md](./deploy-che-ipv6-chectl.md) - Deployment guide
- [test-ipv6-validation.md](./test-ipv6-validation.md) - Testing guide
- [Eclipse Che Networking Docs](https://eclipse.dev/che/docs/stable/administration-guide/configuring-che/)

## Common Cluster-Bot Patterns

### Pattern 1: Cluster-bot with proxy-url

```yaml
# Kubeconfig includes proxy-url for API access
clusters:
- cluster:
    proxy-url: http://....redhat.com:8888
    server: https://api.<cluster>.origin-ci-int-gce.dev.rhcloud.com:6443
```

**Implication**: API is accessible via proxy, but Che routes may not be

**Solution**: SOCKS proxy (not just HTTP_PROXY)

### Pattern 2: IPv6-only cluster

```bash
# Service networks show only IPv6
oc get network.config.openshift.io cluster -o jsonpath='{.status.serviceNetwork[*]}'
# Output: fd00:10:128::/112 (IPv6 only)
```

**Implication**: Your laptop needs IPv6 connectivity or must proxy through IPv6-capable bastion

**Solution**: SOCKS proxy via IPv6-enabled bastion

### Pattern 3: HostNetwork ingress

```bash
# Router pods use hostNetwork
oc get pod -n openshift-ingress -o yaml | grep hostNetwork
# Output: hostNetwork: true
```

**Implication**: Routes are only accessible from cluster network, not public internet

**Solution**: SOCKS proxy or VPN access

## Support

If none of these solutions work:

1. **Check Che deployment logs**:
   ```bash
   oc logs -n eclipse-che -l app=che-operator --tail=100
   oc logs -n eclipse-che -l app=che --tail=100
   ```

2. **Verify route is exposed**:
   ```bash
   oc get route che -n eclipse-che -o yaml
   ```

3. **Test from within cluster** (should always work):
   ```bash
   oc run test-curl --image=curlimages/curl --rm -i -n eclipse-che -- \
     curl -sL $(oc get checluster eclipse-che -n eclipse-che -o jsonpath='{.status.cheURL}')
   ```

4. **File issue** with diagnostic output:
   ```bash
   ./scripts/diagnose-che-access.sh > che-access-debug.txt 2>&1
   # Attach che-access-debug.txt to GitHub issue
   ```
