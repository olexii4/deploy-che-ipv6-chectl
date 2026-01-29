# chectl Timeout and Image Options for IPv6 Deployments

## Overview

The deploy-che-ipv6.sh script now includes enhanced chectl timeout values and custom image/CR options to better handle IPv6-only cluster deployments with slow network connections.

## Timeout Values

### Default chectl Timeouts (from chectl source)

```
--k8spodwaittimeout          120000ms (120 seconds)
--k8spodreadytimeout         120000ms (120 seconds)
--k8spoderrorrechecktimeout  60000ms  (60 seconds)
--k8spoddownloadimagetimeout 1200000ms (1200 seconds / 20 minutes)
```

### Increased Timeouts for IPv6 (2x defaults)

The script automatically applies these increased timeout values when using chectl:

```bash
CHECTL_K8S_POD_WAIT_TIMEOUT=240000          # 240s (2x default)
CHECTL_K8S_POD_READY_TIMEOUT=240000         # 240s (2x default)
CHECTL_K8S_POD_ERROR_RECHECK_TIMEOUT=120000 # 120s (2x default)
CHECTL_K8S_POD_DOWNLOAD_IMAGE_TIMEOUT=2400000 # 2400s/40min (2x default)
```

These increased timeouts help with:
- Slow image pulls on IPv6-only connections
- Delayed pod startup due to network latency
- OLM catalog and operator installation delays

## New Command-Line Options

### 1. Custom Che Server Image

```bash
./deploy-che-ipv6.sh --che-server-image quay.io/eclipse/che-server:next
```

**Default Values:**
- Upstream Che: `quay.io/eclipse/che-server:next`
- CodeReady Workspaces: `registry.redhat.io/codeready-workspaces/server-rhel8:latest`

**Use Case:** Override the Che server container image (different from the dashboard image).

### 2. Custom CheCluster CR YAML

```bash
./deploy-che-ipv6.sh --che-operator-cr-yaml /path/to/custom-checluster.yaml
```

**Use Case:** Provide a complete CheCluster custom resource definition. This allows you to:
- Pre-define all container images (for mirroring discovery)
- Set custom resource limits and requests
- Configure networking, storage, and security settings
- Define plugin and devfile registry URLs

**Example CR:** See `examples/custom-checluster-cr.yaml`

### 3. CheCluster CR Patch YAML

```bash
./deploy-che-ipv6.sh --che-operator-cr-patch-yaml /path/to/patch.yaml
```

**Use Case:** Override specific fields in the default CheCluster CR without providing a full definition.

**Example Patch:**
```yaml
spec:
  components:
    cheServer:
      deployment:
        containers:
          - name: che
            resources:
              limits:
                memory: 2Gi
              requests:
                memory: 1Gi
    dashboard:
      deployment:
        containers:
          - name: dashboard
            resources:
              limits:
                memory: 512Mi
```

## Complete Example Usage

### Basic Deployment with Increased Timeouts

```bash
./deploy-che-ipv6.sh \
  --kubeconfig cluster.kubeconfig \
  --dashboard-image pr-1442
```

Timeouts are automatically increased (no additional flags needed).

### Advanced Deployment with Custom Images

```bash
./deploy-che-ipv6.sh \
  --kubeconfig cluster.kubeconfig \
  --dashboard-image quay.io/eclipse/che-dashboard:pr-1442 \
  --che-server-image quay.io/eclipse/che-server:next \
  --che-operator-image quay.io/eclipse/che-operator:next \
  --che-operator-cr-patch-yaml /tmp/che-resources.yaml
```

### Pre-Discovery of All Images for Mirroring

To discover all images that will be needed for deployment:

1. Create a custom CheCluster CR with all images explicitly defined
2. Use the CR to extract image list before deployment
3. Mirror all images to internal registry
4. Deploy with the custom CR

**Example workflow:**

```bash
# Step 1: Create custom CR with explicit images
cat > /tmp/custom-che-cr.yaml <<EOF
apiVersion: org.eclipse.che/v2
kind: CheCluster
metadata:
  name: eclipse-che
  namespace: eclipse-che
spec:
  components:
    cheServer:
      deployment:
        containers:
          - image: quay.io/eclipse/che-server:next
    dashboard:
      deployment:
        containers:
          - image: quay.io/eclipse/che-dashboard:pr-1442
    pluginRegistry:
      deployment:
        containers:
          - image: quay.io/eclipse/che-plugin-registry:next
    devfileRegistry:
      deployment:
        containers:
          - image: quay.io/eclipse/che-devfile-registry:next
    devWorkspace:
      deployment:
        containers:
          - image: quay.io/devfile/devworkspace-controller:next
          - image: quay.io/devfile/project-clone:next
EOF

# Step 2: Extract images from CR (manual or scripted)
grep -oE 'image: [^ ]+' /tmp/custom-che-cr.yaml | awk '{print $2}'

# Step 3: Mirror images
./mirror-images-to-registry.sh --kubeconfig cluster.kubeconfig --mode full

# Step 4: Deploy with custom CR
./deploy-che-ipv6.sh \
  --kubeconfig cluster.kubeconfig \
  --che-operator-cr-yaml /tmp/custom-che-cr.yaml
```

## Timeout Behavior with Retry Logic

The script's retry logic works in conjunction with the timeout values:

1. **Attempt 1-2:** Killed at 110 seconds (before chectl's internal 120s timeout)
2. **Attempt 3:** Full timeout allowed (uses the increased timeout values)

This ensures:
- Quick retries for transient issues
- Proper error messages on final attempt
- No premature failures due to slow IPv6 connections

## How Timeouts Help with Image Mirroring

The increased timeouts are critical for IPv6-only deployments because:

1. **Image Download Timeout (40 minutes):** Allows time for large images (UDI, registry images) to be pulled through the internal registry mirror
2. **Pod Ready Timeout (4 minutes):** Gives catalog pods time to start and serve gRPC connections
3. **Pod Wait Timeout (4 minutes):** Allows scheduler to find available nodes and assign pods
4. **Error Recheck Timeout (2 minutes):** Prevents false positives from temporary network issues

## Troubleshooting

### If deployment still times out with increased timeouts:

1. **Check catalog pod logs:**
   ```bash
   oc logs -n openshift-marketplace <catalog-pod-name>
   ```

2. **Verify image mirroring completed:**
   ```bash
   oc get imagecontentsourcepolicy
   oc get imagetagmirrorset
   ```

3. **Check operator installation:**
   ```bash
   oc get subscription -n openshift-operators
   oc get installplan -n openshift-operators
   oc get csv -n openshift-operators
   ```

4. **Use manual OLM mode for more control:**
   ```bash
   ./deploy-che-ipv6.sh --manual-olm --olm-timeout 1200
   ```

## Reference

- chectl source code: `/Users/oleksiiorel/workspace/che-incubator/chectl`
- Timeout definitions: `src/flags.ts`
- Server deploy command: `src/commands/server/deploy.ts`
- CheCluster CR handling: `src/tasks/che-cluster-tasks.ts`
