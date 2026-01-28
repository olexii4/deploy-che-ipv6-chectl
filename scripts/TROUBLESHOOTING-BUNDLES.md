# Troubleshooting OLM Bundle Images on IPv6-Only Clusters

## Problem: Missing OLM Bundle Images

When deploying Eclipse Che on IPv6-only clusters with no outbound internet connectivity, deployments may fail with errors like:

```
Failed to pull image "quay.io/eclipse/eclipse-che-olm-bundle@sha256:b525...":
  manifest unknown
  network is unreachable
```

## Root Cause

OLM (Operator Lifecycle Manager) operators use **bundle images** that are:
1. Referenced by **SHA256 digest** (not tags) in catalog indices
2. **Discovered dynamically** when OLM installs operators
3. **Cannot be pre-discovered** until OLM reads the catalog

On IPv6-only clusters without internet access:
- Catalog index images can be mirrored
- But bundle digests aren't known until OLM tries to pull them
- Pods fail because they can't reach quay.io

## The Catch-22

```
┌─────────────────────────────────────────────────────────┐
│  • OLM bundles reference specific digests              │
│  • Digests aren't known until OLM reads the catalog    │
│  • Cluster can't pull bundles when OLM requests them   │
│  • Can't pre-mirror what we don't know is needed       │
└─────────────────────────────────────────────────────────┘
```

## Solution: Static Bundle List

The `mirror-images-to-registry.sh` script maintains a **static list of known bundle digests** that must be updated when operator versions change.

### Location

File: `scripts/mirror-images-to-registry.sh`
Lines: ~299-304

```bash
# OLM bundle images (referenced by catalog indices via digest)
# NOTE: These digests may change when operator versions update
"quay.io/devfile/devworkspace-operator-bundle@sha256:a3fb42e76b477cc00f4833be380efde57503802082ce07985e55dd5f96a1d597"
"quay.io/eclipse/eclipse-che-olm-bundle@sha256:b525748e410cf2ddb405209ac5bce7b4ed2e401b7141f6c4edcea0e32e5793a1"
```

## How to Find Missing Bundle Digests

### Method 1: Check Deployment Failures

1. **Try to deploy Eclipse Che**
2. **Check for pull failures**:
   ```bash
   oc get events -n eclipse-che --sort-by='.lastTimestamp' | grep -i bundle
   ```
3. **Look for errors** like:
   ```
   Failed to pull image "quay.io/eclipse/eclipse-che-olm-bundle@sha256:b525..."
   ```
4. **Extract the full digest** from the error message

### Method 2: Inspect Catalog Index

On a machine with internet access:

```bash
# Pull the catalog index
skopeo inspect docker://quay.io/eclipse/eclipse-che-olm-catalog:next

# Look for "RelatedImages" or bundle references
# Bundle images typically have names like:
#   quay.io/eclipse/eclipse-che-olm-bundle@sha256:...
#   quay.io/devfile/devworkspace-operator-bundle@sha256:...
```

### Method 3: Use opm (Operator Package Manager)

If available:

```bash
# Render the catalog to see all bundle references
opm render quay.io/eclipse/eclipse-che-olm-catalog:next | grep -i bundle
```

## Adding Missing Bundles

1. **Identify the missing bundle digest** (see methods above)
2. **Edit** `scripts/mirror-images-to-registry.sh`
3. **Add the bundle** to the static list (around line 302):
   ```bash
   "quay.io/eclipse/NEW-BUNDLE-NAME@sha256:DIGEST-HERE"
   ```
4. **Re-run the mirror script**:
   ```bash
   ./scripts/mirror-images-to-registry.sh --kubeconfig <path>
   ```
5. **Retry deployment**

## Example: Adding Eclipse Che Bundle

```bash
# 1. Found error in events
oc get events -n eclipse-che | grep bundle
# Output: Failed to pull quay.io/eclipse/eclipse-che-olm-bundle@sha256:b525...

# 2. Add to mirror script
vim scripts/mirror-images-to-registry.sh
# Add: "quay.io/eclipse/eclipse-che-olm-bundle@sha256:b525748e410cf2ddb405209ac5bce7b4ed2e401b7141f6c4edcea0e32e5793a1"

# 3. Re-mirror
./scripts/mirror-images-to-registry.sh --kubeconfig ~/cluster.kubeconfig

# 4. Retry deployment
./scripts/deploy-che-ipv6-chectl.sh --kubeconfig ~/cluster.kubeconfig
```

## Why Dynamic Discovery Is Disabled

The script has code for **dynamic bundle discovery** (lines 343-439) but it's disabled (`if false &&`) because:

1. **Platform compatibility**: Requires Linux-specific tools (opm, podman)
2. **Timing**: Bundles aren't in catalog metadata until catalog is unpacked
3. **Reliability**: Static list is more predictable for disconnected environments

## Alternative: Dual-Stack Clusters

For **testing IPv6 functionality** without these issues:

```bash
# Launch cluster WITH outbound connectivity
launch 4.20.2 metal,ipv6

# Cluster will have:
# ✅ IPv6 service network
# ✅ IPv6 pod network
# ✅ Outbound IPv4 connectivity to pull images
# ✅ No mirroring needed
```

This allows testing IPv6 URL validation without disconnected deployment complexity.

## Future Improvements

Potential solutions being considered:

1. **Complete offline mirror**: Extract all bundles from catalogs on internet-connected machine
2. **OLM-less deployment**: Deploy operators directly without OLM (complex)
3. **Bundle auto-discovery**: Improve dynamic discovery to work across platforms
4. **Version pinning**: Track bundle digests per operator version in version control

## Related Issues

- OLM bundles: https://olm.operatorframework.io/docs/concepts/olm-architecture/operator-catalog/creating-an-update-graph/#bundle-image
- IPv6-only clusters: Limited to internal/mirrored registries only
- Image mirroring: https://docs.openshift.com/container-platform/4.20/installing/disconnected_install/index.html
