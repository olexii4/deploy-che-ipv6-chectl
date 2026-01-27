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
See [mirror-images-to-registry.md](./mirror-images-to-registry.md) for detailed mirroring documentation.

**3. Run IPv6 Validation Tests**

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

### Documentation

- **[deploy-che-ipv6-chectl.md](./scripts/deploy-che-ipv6-chectl.md)** - Comprehensive deployment guide
- **[test-ipv6-validation.md](./scripts/test-ipv6-validation.md)** - Testing guide and test scenarios

## Recent script fixes (2026-01)

- **Proxy support (cluster-bot kubeconfig)**:
  - `deploy-che-ipv6-chectl.sh` exports `HTTP_PROXY/HTTPS_PROXY` from kubeconfig `proxy-url` before running `chectl`.
  - `mirror-images-to-registry.sh` exports `HTTP_PROXY/HTTPS_PROXY` from kubeconfig `proxy-url` before running `skopeo` (since `skopeo` does not read kubeconfig `proxy-url`).
- **Mirroring is safer**:
  - The mirroring script no longer applies `ImageContentSourcePolicy` if image mirroring fails.
- **Mirroring is more reliable and can be faster**:
  - `mirror-images-to-registry.sh` supports `--prefetch-only` + `--cache-dir` to predownload the fixed image list into local OCI archives.
  - When a cached OCI archive exists, mirroring will push from cache instead of pulling from the source registry again.
  - Each `skopeo copy` operation is protected by a timeout (`SKOPEO_TIMEOUT_SECONDS`, default 900s) to avoid hangs.
- **Fixed bad image reference**:
  - Removed the non-existent `quay.io/eclipse/che--traefik:v2.11.12` entry from the mirror list (it caused guaranteed failures).

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

