# deploy-local.sh - Local/Test Cluster Deployment

Deploy Eclipse Che or CodeReady Workspaces on local and test OpenShift clusters.

## Supported Clusters

- **OpenShift Local (CRC)** - IPv4 only, ARM64-compatible
- **SNO (Single Node OpenShift)** - IPv4 or IPv6
- **Cluster-bot clusters** - IPv6-enabled test clusters
- **Any OpenShift 4.x cluster**

## Prerequisites

- `oc` CLI installed and logged into cluster
- `chectl` installed (for operator installation)
- OpenShift cluster running

## Usage

```bash
./deploy-local.sh [options]
```

## Options

| Option | Description |
|--------|-------------|
| `--crw` | Deploy CodeReady Workspaces instead of Eclipse Che |
| `--dashboard-image <image>` | Dashboard image (supports shortcuts: pr-XXXX, next, latest) |
| `--namespace <namespace>` | Namespace (default: eclipse-che or openshift-workspaces for CRW) |
| `--skip-devworkspace` | Skip DevWorkspace operator installation (if already cluster-wide) |
| `--arm64-gateway` | Use ARM64-compatible gateway images (for CRC on Apple Silicon) |
| `--cleanup` | Delete existing deployment before installing |
| `--help` | Show help message |

## Dashboard Image Shortcuts

| Shortcut | Expands To (Eclipse Che) | Expands To (CRW) |
|----------|-------------------------|------------------|
| `pr-1442` | `quay.io/eclipse/che-dashboard:pr-1442` | ⚠️ Warning shown |
| `next` | `quay.io/eclipse/che-dashboard:next` | `registry.redhat.io/.../crw-2-rhel8-dashboard:next` |
| `latest` | `quay.io/eclipse/che-dashboard:latest` | `registry.redhat.io/.../crw-2-rhel8-dashboard:latest` |
| Full path | Used as-is | Used as-is |

## Examples

### Deploy Eclipse Che with PR-1442 Dashboard

```bash
# On CRC (ARM64 Mac)
./deploy-local.sh \
  --dashboard-image pr-1442 \
  --arm64-gateway

# On x86_64 cluster
./deploy-local.sh \
  --dashboard-image pr-1442
```

### Deploy CodeReady Workspaces

```bash
# Deploy CRW with latest dashboard
./deploy-local.sh \
  --crw \
  --dashboard-image latest

# Clean deploy of CRW
./deploy-local.sh \
  --crw \
  --cleanup \
  --dashboard-image next
```

### Deploy on Cluster-bot IPv6 Cluster

```bash
# Login to cluster first
export KUBECONFIG=~/cluster-bot.kubeconfig
oc whoami

# Deploy Eclipse Che
./deploy-local.sh \
  --dashboard-image pr-1442

# Deploy CRW
./deploy-local.sh \
  --crw \
  --dashboard-image latest
```

### Skip DevWorkspace Operator

If DevWorkspace operator is already installed cluster-wide:

```bash
./deploy-local.sh \
  --dashboard-image pr-1442 \
  --skip-devworkspace
```

## How It Works

1. **Prerequisites Check** - Verifies `oc` and `chectl` are available
2. **Cluster Detection** - Detects CRC, cluster-bot, or other OpenShift clusters
3. **IPv6 Detection** - Checks if cluster has IPv6 networking
4. **Cleanup** (optional) - Removes existing deployment
5. **Operator Installation** - Installs Eclipse Che or CRW operator via chectl
6. **CheCluster Creation** - Creates CheCluster CR with specified configuration
7. **Wait for Ready** - Waits for all deployments to be ready
8. **Status Display** - Shows deployment status and access URLs

## ARM64 Gateway Images

On ARM64 systems (CRC on Apple Silicon), use `--arm64-gateway` to ensure gateway pods can run:

```bash
./deploy-local.sh \
  --dashboard-image pr-1442 \
  --arm64-gateway
```

This uses:
- `registry.redhat.io/openshift4/ose-oauth-proxy:v4.14` (ARM64-compatible)
- `registry.redhat.io/openshift4/ose-kube-rbac-proxy:v4.14` (ARM64-compatible)

## CRC vs IPv6 Cluster

### OpenShift Local (CRC)
- **Networking:** IPv4 only
- **Use Case:** Local development, dashboard testing
- **IPv6 Testing:** ❌ Not supported
- **Command:** `./deploy-local.sh --dashboard-image pr-1442 --arm64-gateway`

### Cluster-bot IPv6 Cluster
- **Networking:** IPv6 (fd02::/112 services, fd01::/48 pods)
- **Use Case:** IPv6 validation testing
- **IPv6 Testing:** ✅ Fully supported
- **Command:** `./deploy-local.sh --dashboard-image pr-1442`

## Product Differences

### Eclipse Che (Default)
```bash
./deploy-local.sh --dashboard-image pr-1442
```
- **Namespace:** `eclipse-che`
- **Images:** `quay.io/eclipse/*`
- **Operator:** `eclipse-che`
- **Use Case:** Testing upstream features, PR validation

### CodeReady Workspaces (--crw)
```bash
./deploy-local.sh --crw --dashboard-image latest
```
- **Namespace:** `openshift-workspaces`
- **Images:** `registry.redhat.io/codeready-workspaces/*`
- **Operator:** `codeready-workspaces`
- **Use Case:** Production deployments, Red Hat support

## Troubleshooting

### Operator Installation Fails

If operator installation fails, check:

```bash
# Check operator pod
oc get pods -n eclipse-che -l app.kubernetes.io/component=che-operator

# Check operator logs
oc logs -f -n eclipse-che -l app.kubernetes.io/component=che-operator
```

### Gateway Pod CrashLoopBackOff

On ARM64 systems, make sure to use `--arm64-gateway`:

```bash
./deploy-local.sh --dashboard-image pr-1442 --arm64-gateway
```

### DevWorkspace Operator Already Installed

If DevWorkspace operator is already installed cluster-wide, use `--skip-devworkspace`:

```bash
./deploy-local.sh --dashboard-image pr-1442 --skip-devworkspace
```

## Comparison with deploy-che-ipv6.sh

| Feature | deploy-local.sh | deploy-che-ipv6.sh |
|---------|----------------|-------------------|
| **Target** | Local/test clusters | IPv6-only clusters |
| **Image Mirroring** | ❌ Not needed | ✅ Required |
| **chectl Support** | ✅ Yes | Optional (--manual-olm) |
| **IPv6 Clusters** | ✅ Supported | ✅ Primary target |
| **CRC Support** | ✅ Yes (ARM64) | ⚠️ Limited |
| **Prefetch** | ❌ No | ✅ Yes |
| **Best For** | Quick testing | IPv6 validation |

## See Also

- [deploy-che-ipv6.md](./deploy-che-ipv6.md) - Full IPv6 cluster deployment
- [test-ipv6-validation.md](./test-ipv6-validation.md) - IPv6 testing
- [mirror-images-to-registry.md](./mirror-images-to-registry.md) - Image mirroring
