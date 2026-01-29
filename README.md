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

**After deployment completes, the script will show:**
- ✅ Che URL (e.g., `https://eclipse-che-eclipse-che.apps.ostest...`)
- ✅ Proxy information extracted from kubeconfig
- ✅ Chrome launch commands for macOS and Linux
- ✅ Step-by-step instructions to access the dashboard

### 4. Access Eclipse Che Dashboard

**The deployment script automatically shows you what to do next!**

When deployment completes successfully, you'll see output like this:

```
=== Eclipse Che Deployed Successfully ===
Che URL: https://eclipse-che-eclipse-che.apps.ostest.test.metalkube.org

=== Next Steps: Access the Dashboard ===

The cluster is only accessible via proxy from the kubeconfig:
  Proxy: http://145.40.68.183:8213

Step 1: Launch Google Chrome with proxy

  macOS:
    /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
      --proxy-server="http://145.40.68.183:8213"

  Linux:
    google-chrome \
      --proxy-server="http://145.40.68.183:8213"

Step 2: Open Che Dashboard in the proxied Chrome:
  https://eclipse-che-eclipse-che.apps.ostest.test.metalkube.org/dashboard/

Step 3: Login with OpenShift credentials
  (Use the kubeadmin credentials from cluster-bot)
```

**Simply copy and paste the commands shown in the output!**

The script automatically:
- ✅ Extracts the proxy from your kubeconfig
- ✅ Shows the correct Chrome launch command for your OS
- ✅ Provides the exact Che URL to open
- ✅ Gives you step-by-step instructions

**Alternative: Manual proxy configuration**

If you prefer to use a browser extension instead:

1. Install "Proxy Switcher and Manager" extension in Chrome
2. Configure HTTP proxy using the IP and port shown in the deployment output
   - Example: `145.40.68.183:8213`
3. Enable the proxy
4. Navigate to the Che URL shown in the output

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
