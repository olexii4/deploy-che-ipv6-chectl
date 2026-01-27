# Deploy Eclipse Che with IPv6 Support

This repository contains scripts and documentation for testing [Eclipse Che Dashboard PR-1442](https://github.com/eclipse-che/che-dashboard/pull/1442), which adds IPv6 URL validation support.

> **Note about cluster-bot kubeconfigs:** cluster-bot kubeconfigs typically include `proxy-url`.  
> These scripts automatically use that proxy when needed (so you don’t hit DNS errors like `ENOTFOUND api.<cluster>`).

### Test Environment Setup

**1. Provision OpenShift Cluster with IPv6**

Use the OpenShift CI cluster bot to provision an IPv6-enabled cluster:

```bash
launch 4.20.2 metal,ipv6
```

Save the kubeconfig provided by cluster bot:

```bash
# Save kubeconfig to file
cat > ~/ostest-kubeconfig.yaml << 'EOF'
# Paste the kubeconfig content from cluster bot here
# (includes proxy-url for cluster access)
EOF
```

**2. Deploy Eclipse Che with PR-1442 Dashboard**

Run the automated deployment script:

```bash
# Clone this repository
git clone https://github.com/olexii4/deploy-che-ipv6-chectl.git
cd deploy-che-ipv6-chectl

# Run deployment script with kubeconfig
./scripts/deploy-che-ipv6-chectl.sh --kubeconfig ~/ostest-kubeconfig.yaml
```

Useful options:

```bash
# Auto-install chectl if missing
./scripts/deploy-che-ipv6-chectl.sh --kubeconfig ~/ostest-kubeconfig.yaml --install-chectl

# Predownload base images to local cache before touching the cluster (optional)
# This helps when proxy connectivity is flaky during the deploy window.
./scripts/deploy-che-ipv6-chectl.sh --prefetch-images

# IPv6-only clusters: choose mirroring mode
# - full (default): includes DevWorkspace + UDI for workspace tests
# - minimal: mirrors only core Che images (faster, but workspace creation may not work)
./scripts/deploy-che-ipv6-chectl.sh --kubeconfig ~/ostest-kubeconfig.yaml --mirror-mode minimal

# Use a local cache directory for prefetch + mirroring reuse (optional)
./scripts/deploy-che-ipv6-chectl.sh \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --prefetch-images \
  --cache-dir ~/.cache/che-ipv6-mirror
```

The script will:
- ✅ Verify IPv6 cluster networking
- ✅ Use kubeconfig `proxy-url` automatically (if present)
- ✅ Check `chectl` is installed (or install with `--install-chectl`)
- ✅ Deploy Eclipse Che **via the operator** (using `chectl server:deploy --installer operator`)
- ✅ Configure dashboard with PR-1442 image (`quay.io/eclipse/che-dashboard:pr-1442`)
- ✅ Verify deployment and display Che URL

See [deploy-che-ipv6-chectl.md](./scripts/deploy-che-ipv6-chectl.md) for detailed deployment documentation.
See [mirror-images-to-registry.md](./scripts/mirror-images-to-registry.md) for detailed mirroring documentation.

**3. Access Eclipse Che Dashboard**

On cluster-bot clusters, the Che route may not be directly accessible from your laptop. Use one of these approaches:

```bash
# Option 1: SOCKS Proxy (Recommended)
# Requires SSH access to a Red Hat bastion/VPN server
ssh -D 1080 -N -f user@bastion.redhat.com

# Configure Firefox:
# Settings → Network → Manual proxy → SOCKS Host: 127.0.0.1, Port: 1080, SOCKS v5
# ✓ Enable "Proxy DNS when using SOCKS v5"

# Get Che URL and open in Firefox
CHE_URL=$(oc get checluster eclipse-che -n eclipse-che -o jsonpath='{.status.cheURL}')
echo "Open in Firefox: ${CHE_URL}/dashboard/"

# Option 2: Diagnose access issues
./scripts/diagnose-che-access.sh
```

See [diagnose-che-access.md](./scripts/diagnose-che-access.md) for detailed troubleshooting.

**4. Run IPv6 Validation Tests**

Execute the automated test suite:

```bash
./scripts/test-ipv6-validation.sh --kubeconfig ~/ostest-kubeconfig.yaml
```

The test script validates:
- ✅ IPv6 URL parsing in factory flows
- ✅ Workspace creation from IPv6 Git repositories
- ✅ Support for various IPv6 URL formats
- ✅ Dashboard handling of IPv6 addresses

See [test-ipv6-validation.md](./scripts/test-ipv6-validation.md) for detailed testing documentation.

### Test Scenarios

The PR-1442 implementation is tested against the following IPv6 URL formats:

#### ✅ Supported IPv6 URL Formats

```
http://[::1]:8080/repo.git
http://[fd00::1]:8080/repo.git
http://[2001:db8::1]:8080/repo.git
https://[fd00::1]:8080/repo.git
http://[fd00::1]/path/to/repo.git
https://[2001:db8::1]:443/repo.git
```

#### Factory URL Testing

```bash
# Test factory URL with IPv6 repository
https://che-host/#http://[fd00::1]:8080/repo.git

# Test with devfile
https://che-host/#http://[fd00::1]:8080/repo.git?df=devfile.yaml
```

#### Test infrastructure with a real repo + a real devfile (mirrored into cluster)

The test script can *optionally* mirror an external Git repository and an external devfile URL into the cluster and then serve them via IPv6-only service IPs.

Example repo + devfile:

- Git repo: `git@github.com:che-samples/web-nodejs-sample.git` (the script will rewrite this to HTTPS for cloning)
- Devfile: `https://registry.devfile.io/devfiles/nodejs-angular/2.2.1` (see content at [`registry.devfile.io`](https://registry.devfile.io/devfiles/nodejs-angular/2.2.1))

Run:

```bash
./scripts/test-ipv6-validation.sh \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --repo-url git@github.com:che-samples/web-nodejs-sample.git \
  --devfile-url https://registry.devfile.io/devfiles/nodejs-angular/2.2.1
```

Notes:
- On **IPv6-only clusters**, the cluster may not have outbound access to GitHub / `registry.devfile.io`. If mirroring fails, the script will still deploy the built-in sample repos/devfiles and print those IPv6 factory URLs.

### Expected Results

- ✅ Dashboard correctly parses IPv6 URLs with square brackets
- ✅ Factory flow creates workspace from IPv6 repository URLs
- ✅ Git clone works over IPv6 network
- ✅ Workspace starts successfully with IPv6-hosted devfiles
- ✅ No URL validation errors for RFC-compliant IPv6 URLs

## Repository Contents

### Scripts

- **[scripts/deploy-che-ipv6-chectl.sh](./scripts/deploy-che-ipv6-chectl.sh)** - Automated deployment script
- **[scripts/mirror-images-to-registry.sh](./scripts/mirror-images-to-registry.sh)** - Mirrors required images to the cluster registry (used automatically on IPv6-only clusters)
- **[scripts/test-ipv6-validation.sh](./scripts/test-ipv6-validation.sh)** - Automated IPv6 validation test suite
- **[scripts/diagnose-che-access.sh](./scripts/diagnose-che-access.sh)** - Diagnose and resolve Che dashboard access issues
- **[scripts/create-che-proxy.sh](./scripts/create-che-proxy.sh)** - Create HTTP proxy pod for Che access via port-forward

### Documentation

- **[deploy-che-ipv6-chectl.md](./scripts/deploy-che-ipv6-chectl.md)** - Comprehensive deployment guide
- **[test-ipv6-validation.md](./scripts/test-ipv6-validation.md)** - Testing guide and test scenarios
- **[diagnose-che-access.md](./scripts/diagnose-che-access.md)** - Troubleshooting dashboard access issues
- **[create-che-proxy.md](./scripts/create-che-proxy.md)** - HTTP proxy pod setup guide
- **[mirror-images-to-registry.md](./scripts/mirror-images-to-registry.md)** - Image mirroring documentation

## Recent Changes (2026-01)

### Deployment & Networking
- **Enhanced proxy support (cluster-bot kubeconfig)**:
  - `deploy-che-ipv6-chectl.sh` exports `HTTP_PROXY/HTTPS_PROXY` from kubeconfig `proxy-url` before running `chectl`
  - Script uses local `oc proxy` when API hostname is not resolvable (avoids ENOTFOUND errors)
  - Automatic retry logic when cluster-bot proxy becomes temporarily unavailable
- **Improved deployment resilience**:
  - Automatic discovery and mirroring of missing OLM bundle images when deployment fails
  - Better handling of catalog source and operator bundle images
  - Disabled dynamic bundle discovery on macOS to avoid compatibility issues

### Image Mirroring
- **Safer and more reliable mirroring**:
  - No longer applies `ImageContentSourcePolicy` if image mirroring fails
  - Each `skopeo copy` operation protected by timeout (`SKOPEO_TIMEOUT_SECONDS`, default 900s) to avoid hangs
  - Support for `--parallel` copying with configurable concurrency
  - Heartbeat messages during long operations (configurable with `--heartbeat-seconds`)
- **Cache and prefetch support**:
  - `--prefetch-only` + `--cache-dir` to predownload images into local OCI archives before cluster deployment
  - When cached OCI archives exist, mirroring pushes from cache instead of re-pulling from source
  - Cache directory defaults to `~/.cache/che-ipv6-mirror/`
- **OLM bundle image support**:
  - Added OLM bundle images to mirror list for complete operator deployment
  - Automatic discovery of images from `openshift-marketplace` and `openshift-operators` namespaces
- **Fixed image references**:
  - Removed non-existent `quay.io/eclipse/che--traefik:v2.11.12` from mirror list
  - Trimmed base image set to essential images only

### Access & Diagnostics
- **New proxy pod approach**:
  - Added `create-che-proxy.sh` to create nginx proxy pod for Che access via port-forward
  - Alternative to SOCKS proxy when VPN/bastion access is not available
- **Enhanced diagnostics**:
  - `diagnose-che-access.sh` tests cluster-internal access, DNS resolution, and network connectivity
  - Provides specific solutions based on failure mode (SOCKS proxy, /etc/hosts, OpenShift Console)

### Documentation
- All scripts now have corresponding `.md` documentation files in `scripts/` directory
- Expanded troubleshooting guides with cluster-bot specific patterns
- Added mirroring verbosity and performance tuning documentation

### Manual Testing

After deployment, you can manually test IPv6 URLs:

1. Access the Che dashboard
2. Navigate to factory URL:
   ```
   https://<che-host>/#http://[fd00::1]:8080/your-repo.git
   ```
3. Verify workspace creation succeeds


## License

EPL-2.0

