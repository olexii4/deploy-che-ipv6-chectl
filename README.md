# Deploy Eclipse Che with IPv6 Support

This repository contains scripts for deploying Eclipse Che on IPv6-only OpenShift clusters and testing IPv6 URL validation.

> **Note:** cluster-bot kubeconfigs include `proxy-url` for cluster access. These scripts automatically use that proxy when needed.

## Quick Start

### 1. Provision OpenShift Cluster with IPv6

Use the OpenShift CI cluster bot to provision an IPv6-enabled cluster:

```bash
launch 4.20.2 metal,ipv6
```

Save the kubeconfig provided by cluster bot:

```bash
# Save kubeconfig to file
cat > ~/ostest-kubeconfig.yaml << 'EOF'
# Paste the kubeconfig content from cluster bot here
EOF
```

### 2. Predownload Container Images

**Predownload OLM bundle images to speed up deployment:**

```bash
# Clone this repository
git clone https://github.com/olexii4/deploy-che-ipv6-chectl.git
cd deploy-che-ipv6-chectl

# Pull bundle images (requires podman)
podman pull quay.io/devfile/devworkspace-operator-bundle:next
podman pull quay.io/eclipse/eclipse-che-openshift-opm-bundles:next
```

This step is optional but recommended to avoid timeouts during deployment.

### 3. Deploy Eclipse Che

**Deploy using manual operator installation (bypasses OLM catalog networking issues):**

```bash
# Deploy Eclipse Che
./scripts/deploy-che-manual-from-bundles.sh \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --dashboard-image pr-1442 \
  --namespace eclipse-che
```

**What the script does:**
- Extracts manifests directly from OLM bundle images (bypasses catalog networking)
- Deploys DevWorkspace Operator
- Deploys Che Operator
- Creates CheCluster custom resource with custom dashboard image
- Waits for all components to be ready

**Options:**
```
--kubeconfig <path>              Path to kubeconfig file (required)
--namespace <name>               Namespace for Eclipse Che (default: eclipse-che)
--dashboard-image <image>        Dashboard image (shortcuts: pr-XXXX, next, latest)
--che-server-image <image>       Che server container image
--skip-devworkspace              Skip DevWorkspace Operator installation
--devworkspace-bundle <image>    DevWorkspace bundle image
--che-bundle <image>             Che bundle image
```

### 4. Access Eclipse Che Dashboard

On cluster-bot metal clusters, the Che route is not directly accessible. The cluster-bot provides a proxy in the kubeconfig that must be used.

**Extract proxy from kubeconfig:**

```bash
# Get proxy URL from kubeconfig (example output: http://145.40.68.183:8213)
grep proxy-url ~/ostest-kubeconfig.yaml
```

**Method 1: Launch Chrome with HTTP proxy (Recommended)**

```bash
# Extract proxy IP and port from kubeconfig
PROXY_URL=$(grep proxy-url ~/ostest-kubeconfig.yaml | awk '{print $2}')
PROXY_HOST=$(echo $PROXY_URL | sed 's|http://||' | cut -d: -f1)
PROXY_PORT=$(echo $PROXY_URL | sed 's|http://||' | cut -d: -f2)

# macOS
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --proxy-server="http://${PROXY_HOST}:${PROXY_PORT}"

# Linux
google-chrome \
  --proxy-server="http://${PROXY_HOST}:${PROXY_PORT}"
```

Then get Che URL and open in the proxied Chrome:
```bash
export KUBECONFIG=~/ostest-kubeconfig.yaml
CHE_URL=$(kubectl get checluster eclipse-che -n eclipse-che -o jsonpath='{.status.cheURL}')
echo "Open in Chrome: ${CHE_URL}/dashboard/"
```

**Method 2: Use Chrome proxy extension**

1. Install "Proxy Switcher and Manager" extension in Chrome
2. Configure HTTP proxy using the IP and port from kubeconfig's `proxy-url`
   - Example: `145.40.68.183:8213`
3. Enable the proxy
4. Navigate to the Che URL

### 5. Run IPv6 Validation Tests

Execute the automated test suite:

```bash
./scripts/test-ipv6-validation.sh --kubeconfig ~/ostest-kubeconfig.yaml
```

The test script validates:
- ✅ IPv6 URL parsing in factory flows
- ✅ Workspace creation from IPv6 Git repositories
- ✅ Support for various IPv6 URL formats
- ✅ Dashboard handling of IPv6 addresses

## Test Scenarios

### Supported IPv6 URL Formats

```
http://[::1]:8080/repo.git
http://[fd00::1]:8080/repo.git
http://[2001:db8::1]:8080/repo.git
https://[fd00::1]:8080/repo.git
http://[fd00::1]/path/to/repo.git
https://[2001:db8::1]:443/repo.git
```

### Factory URL Testing

```bash
# Test factory URL with IPv6 repository
https://che-host/#http://[fd00::1]:8080/repo.git

# Test with devfile
https://che-host/#http://[fd00::1]:8080/repo.git?df=devfile.yaml
```

### Test with Real Repository

```bash
./scripts/test-ipv6-validation.sh \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --repo-url git@github.com:che-samples/web-nodejs-sample.git \
  --devfile-url https://registry.devfile.io/devfiles/nodejs-angular/2.2.1
```

## Deployment Method

### Manual Operator Installation

The deployment script extracts operator manifests directly from OLM bundle images and applies them manually. This approach:

- ✅ **Bypasses OLM catalog networking issues** common in IPv6-only clusters
- ✅ **Works on clusters with broken IPv6 ClusterIP connectivity**
- ✅ **Uses official OLM bundle images** (same as OLM would use)
- ✅ **Provides direct control** over operator versions
- ✅ **Compatible with image mirroring** for disconnected environments

**How it works:**

```
1. Pull DevWorkspace Operator bundle image using podman
2. Extract manifests from bundle (/manifests directory)
3. Apply CRDs, RBAC, and Deployment directly
4. Pull Che Operator bundle image
5. Extract and apply Che Operator manifests
6. Create CheCluster CR with custom configuration
7. Wait for all components to be ready
```

**Bundle images used:**
- DevWorkspace: `quay.io/devfile/devworkspace-operator-bundle:next`
- Eclipse Che: `quay.io/eclipse/eclipse-che-openshift-opm-bundles:next`

## Repository Contents

### Scripts

- **[scripts/deploy-che-manual-from-bundles.sh](./scripts/deploy-che-manual-from-bundles.sh)** - Manual operator deployment from OLM bundles
- **[scripts/test-ipv6-validation.sh](./scripts/test-ipv6-validation.sh)** - Automated IPv6 validation test suite
- **[scripts/diagnose-che-access.sh](./scripts/diagnose-che-access.sh)** - Diagnose Che dashboard access issues

### Documentation

- **[scripts/diagnose-che-access.md](./scripts/diagnose-che-access.md)** - Troubleshooting guide for IPv6 networking issues

## Troubleshooting

### Issue: Cannot access Che dashboard

**Solution:** Use SOCKS proxy as described in step 3 above.

Port-forward access does not work for Che login due to OAuth redirect URI mismatch.

### Issue: Deployment fails with "cannot connect to catalog"

**Solution:** Use the manual deployment script `deploy-che-manual-from-bundles.sh` which bypasses OLM catalog networking.

For detailed troubleshooting, see [scripts/diagnose-che-access.md](./scripts/diagnose-che-access.md)

## Expected Results

- ✅ Dashboard correctly parses IPv6 URLs with square brackets
- ✅ Factory flow creates workspace from IPv6 repository URLs
- ✅ Git clone works over IPv6 network
- ✅ Workspace starts successfully with IPv6-hosted devfiles
- ✅ No URL validation errors for RFC-compliant IPv6 URLs

## Manual Testing

After deployment, you can manually test IPv6 URLs:

1. Access the Che dashboard using SOCKS proxy
2. Navigate to factory URL:
   ```
   https://<che-host>/#http://[fd00::1]:8080/your-repo.git
   ```
3. Verify workspace creation succeeds

## License

EPL-2.0
