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

**2. Deploy Eclipse Che or CodeReady Workspaces**

Run the automated deployment script:

```bash
# Clone this repository
git clone https://github.com/olexii4/deploy-che-ipv6-chectl.git
cd deploy-che-ipv6-chectl
```

**For Local CRC/OpenShift Local:**

```bash
# Deploy with dashboard PR (using shortcut)
./scripts/deploy-che-ipv6.sh \
  --skip-ipv6-check \
  --skip-mirror \
  --dashboard-image pr-1442

# Deploy with latest dashboard
./scripts/deploy-che-ipv6.sh \
  --skip-ipv6-check \
  --skip-mirror \
  --dashboard-image latest

# Deploy CodeReady Workspaces locally
./scripts/deploy-che-ipv6.sh \
  --crw \
  --skip-ipv6-check \
  --skip-mirror
```

**For Remote IPv6-only Clusters (cluster-bot):**

```bash
# Deploy with manual OLM (recommended for IPv6-only)
./scripts/deploy-che-ipv6.sh \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --dashboard-image pr-1442 \
  --manual-olm

# Deploy with longer timeout
./scripts/deploy-che-ipv6.sh \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --dashboard-image pr-1442 \
  --manual-olm \
  --olm-timeout 900

# Deploy CodeReady Workspaces on IPv6 cluster
./scripts/deploy-che-ipv6.sh \
  --crw \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --manual-olm
```

**Advanced Options:**

```bash
# Prefetch images to local cache before deployment (IPv6-only clusters)
./scripts/deploy-che-ipv6.sh \
  --prefetch-images \
  --manual-olm \
  --kubeconfig ~/ostest-kubeconfig.yaml

# Use custom cache directory for prefetch + mirroring reuse
./scripts/deploy-che-ipv6.sh \
  --manual-olm \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --prefetch-images \
  --cache-dir ~/.cache/che-ipv6-mirror

# Choose mirroring mode for IPv6-only clusters
# - full (default): includes DevWorkspace + UDI for workspace tests
# - minimal: mirrors only core Che images (faster, but workspace creation may not work)
./scripts/deploy-che-ipv6.sh \
  --manual-olm \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --mirror-mode minimal

# Auto-install chectl if missing (only needed for chectl method)
./scripts/deploy-che-ipv6.sh \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --install-chectl
```

**Deployment Methods:**

The script supports two deployment methods:

**Method 1: chectl (default)**
- Uses `chectl server:deploy --installer operator`
- Fast on stable networks
- May timeout on IPv6-only or slow network clusters (120s timeout hardcoded in chectl)
- Best for: Local CRC, dual-stack clusters with internet access

**Method 2: Manual OLM (--manual-olm flag)**
- Deploys via OLM directly without chectl
- Configurable timeout (default: 600s vs chectl's 120s)
- More reliable on slow networks, IPv6-only clusters, and cluster-bot deployments
- Better progress logging
- Best for: IPv6-only clusters, cluster-bot, slow networks

**Dashboard Image Shortcuts:**

The script supports convenient shortcuts for dashboard images, similar to the local CRC deployment pattern:

| Shortcut | Expands To (Upstream) | Expands To (with --crw) |
|----------|----------------------|-------------------------|
| `pr-1442` | `quay.io/eclipse/che-dashboard:pr-1442` | ⚠️ Uses quay.io (warning shown) |
| `next` | `quay.io/eclipse/che-dashboard:next` | `registry.redhat.io/codeready-workspaces/crw-2-rhel8-dashboard:next` |
| `latest` | `quay.io/eclipse/che-dashboard:latest` | `registry.redhat.io/codeready-workspaces/crw-2-rhel8-dashboard:latest` |
| Full path | Used as-is | Used as-is |

**Examples:**

```bash
# Use shortcut (pr-XXXX)
./scripts/deploy-che-ipv6.sh --dashboard-image pr-1442

# Use next (upstream)
./scripts/deploy-che-ipv6.sh --dashboard-image next

# Use latest with CRW (uses Red Hat registry)
./scripts/deploy-che-ipv6.sh --crw --dashboard-image latest

# Use full image path
./scripts/deploy-che-ipv6.sh --dashboard-image quay.io/myorg/che-dashboard:custom
```

**CodeReady Workspaces (--crw flag):**
- Deploys Red Hat's downstream CodeReady Workspaces instead of upstream Eclipse Che
- Uses `redhat-operators` catalog (pre-installed on OpenShift)
- Default namespace: `openshift-workspaces`
- Images from `registry.redhat.io` (requires Red Hat subscription)
- Production-supported version for enterprise environments

**Common Flags Reference:**

| Flag | Use When | Example |
|------|----------|---------|
| `--skip-ipv6-check` | Local CRC, dual-stack clusters | ✅ Local development |
| `--skip-mirror` | Cluster has internet access | ✅ CRC, dual-stack |
| `--manual-olm` | IPv6-only, slow networks, cluster-bot | ✅ Cluster-bot deployments |
| `--dashboard-image` | Testing specific PR or version | `pr-1442`, `next`, `latest` |
| `--crw` | Deploy Red Hat CRW instead of upstream | ✅ Enterprise/production |
| `--olm-timeout` | Need longer wait time | `900` (15 minutes) |
| `--kubeconfig` | Remote cluster access | `~/ostest-kubeconfig.yaml` |

**What the Script Does:**
- ✅ Verify IPv6 cluster networking (unless `--skip-ipv6-check`)
- ✅ Use kubeconfig `proxy-url` automatically (if present)
- ✅ Check `chectl` is installed (or skip with `--manual-olm`)
- ✅ Deploy Eclipse Che/CRW **via the operator** (chectl or manual OLM)
- ✅ Configure dashboard with specified image (default: `pr-1442`)
- ✅ Mirror images on IPv6-only clusters (unless `--skip-mirror`)
- ✅ Verify deployment and display Che URL

See [deploy-che-ipv6.md](./scripts/deploy-che-ipv6.md) for detailed deployment documentation.
See [mirror-images-to-registry.md](./scripts/mirror-images-to-registry.md) for detailed mirroring documentation.

> **⚠️ Troubleshooting Deployment Timeout**
> If deployment fails with:
> ```
> Error: Timeout reached while waiting for "eclipse-che" subscription is ready.
> ```
>
> This is a known chectl limitation (hardcoded 120s timeout in `src/api/kube-client.ts:1395`).
> **Solution:** Use `--manual-olm` flag to bypass chectl and deploy via OLM directly:
> ```bash
> ./scripts/deploy-che-ipv6.sh --manual-olm --kubeconfig ~/ostest-kubeconfig.yaml
> ```
>
> The manual OLM method provides:
> - ✅ 600-second timeout (vs chectl's 120s)
> - ✅ Configurable with `--olm-timeout <seconds>`
> - ✅ Better progress visibility
> - ✅ More reliable on slow networks

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

- **[scripts/deploy-che-ipv6.sh](./scripts/deploy-che-ipv6.sh)** - Automated deployment script
- **[scripts/mirror-images-to-registry.sh](./scripts/mirror-images-to-registry.sh)** - Mirrors required images to the cluster registry (used automatically on IPv6-only clusters)
- **[scripts/test-ipv6-validation.sh](./scripts/test-ipv6-validation.sh)** - Automated IPv6 validation test suite
- **[scripts/diagnose-che-access.sh](./scripts/diagnose-che-access.sh)** - Diagnose and resolve Che dashboard access issues

### Documentation

- **[deploy-che-ipv6.md](./scripts/deploy-che-ipv6.md)** - Comprehensive deployment guide
- **[test-ipv6-validation.md](./scripts/test-ipv6-validation.md)** - Testing guide and test scenarios
- **[diagnose-che-access.md](./scripts/diagnose-che-access.md)** - Troubleshooting dashboard access issues
- **[mirror-images-to-registry.md](./scripts/mirror-images-to-registry.md)** - Image mirroring documentation

## Recent Changes (2026-01)

### Deployment & Networking
- **Manual OLM deployment option (NEW)**:
  - `--manual-olm` flag deploys Eclipse Che directly via OLM without chectl
  - Bypasses chectl's hardcoded 120-second subscription timeout
  - Configurable timeout with `--olm-timeout` (default: 600s vs chectl's 120s)
  - Recommended for IPv6-only clusters, slow networks, and cluster-bot deployments
  - Provides detailed progress logging every 10 seconds
  - No chectl installation required when using `--manual-olm`
- **Enhanced proxy support (cluster-bot kubeconfig)**:
  - `deploy-che-ipv6.sh` exports `HTTP_PROXY/HTTPS_PROXY` from kubeconfig `proxy-url` before running `chectl`
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
- **Enhanced diagnostics**:
  - `diagnose-che-access.sh` tests cluster-internal access, DNS resolution, and network connectivity
  - Provides specific solutions based on failure mode (SOCKS proxy, /etc/hosts, OpenShift Console)
  - **Note**: Port-forward access does not work for Che login due to OAuth redirect URI mismatch

### Documentation
- All scripts now have corresponding `.md` documentation files in `scripts/` directory
- Expanded troubleshooting guides with cluster-bot specific patterns
- Added mirroring verbosity and performance tuning documentation

## Deployment Methods Comparison

| Feature | chectl (default) | Manual OLM (--manual-olm) |
|---------|------------------|---------------------------|
| **Installation** | Requires chectl installed | No chectl required |
| **Subscription timeout** | 120s (hardcoded) | 600s (configurable) |
| **IPv6-only clusters** | ⚠️ May timeout | ✅ Reliable |
| **Slow networks** | ⚠️ May timeout | ✅ Handles delays |
| **Progress logging** | Minimal | Detailed (every 10s) |
| **Cluster-bot deployments** | ⚠️ Often fails | ✅ Recommended |
| **Speed on fast networks** | ✅ Fast | ✅ Comparable |
| **CheCluster creation** | Automatic + patch | Direct configuration |
| **Use case** | Development, fast networks | Production, IPv6, cluster-bot |

**When to use `--manual-olm`:**
- ✅ IPv6-only clusters (cluster-bot `launch 4.20.2 metal,ipv6`)
- ✅ Slow network connections or high-latency clusters
- ✅ chectl fails with "Timeout reached while waiting for 'eclipse-che' subscription is ready"
- ✅ You don't want to install chectl
- ✅ You need longer timeout for OLM subscription resolution

**When to use chectl (default):**
- ✅ Fast, stable network connections
- ✅ IPv4 or dual-stack clusters with good connectivity
- ✅ You already have chectl installed and configured
- ✅ Development environments with direct registry access

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

