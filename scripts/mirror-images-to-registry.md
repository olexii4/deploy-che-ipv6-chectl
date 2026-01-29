<!--
Copyright (c) 2026 Red Hat, Inc.
This program and the accompanying materials are made
available under the terms of the Eclipse Public License 2.0
which is available at https://www.eclipse.org/legal/epl-2.0/


SPDX-License-Identifier: EPL-2.0

Contributors:
  Red Hat, Inc. - initial API and implementation
-->

## Mirror images to the cluster registry (IPv6-only OpenShift)

On **IPv6-only OpenShift clusters**, pulling images directly from public registries (for example `quay.io`) may fail.  
The script `scripts/mirror-images-to-registry.sh` mirrors the required images into the cluster’s registry and applies OpenShift mirror policies so nodes pull from the local registry.

### What the script does

- **Mirrors the required images** (Che, DevWorkspace, gateway sidecars, registries) into the detected cluster registry.
- Applies:
  - `ImageTagMirrorSet` and `ImageDigestMirrorSet` (preferred on modern OpenShift)
  - `ImageContentSourcePolicy` (compatibility)
- Supports **single-arch optimization** (mirrors only `linux/amd64` when the cluster is single-arch).
- Uses kubeconfig `proxy-url` (if present) for `skopeo` pushes (since `skopeo` does not read kubeconfig proxies automatically).

### Standard mirroring (cluster access required)

```bash
./scripts/mirror-images-to-registry.sh \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --mode full
```

- **`--mode minimal`**: mirrors only the core Che-related images (faster).
- **`--mode full`**: includes DevWorkspace + UDI (recommended for workspace tests).

Optional performance/visibility flags:

```bash
./scripts/mirror-images-to-registry.sh \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --mode full \
  --parallel 3 \
  --heartbeat-seconds 60 \
  --skopeo-log-level debug
```

### Predownload images for later (no cluster access required)

If you want to reduce dependency on proxy availability during deployment, you can predownload the script’s **base image list** into a local cache.

```bash
./scripts/mirror-images-to-registry.sh \
  --mode full \
  --prefetch-only \
  --cache-dir ~/.cache/che-ipv6-mirror
```

This creates one OCI archive per image in the cache directory. On the next run with cluster access, the script will reuse cached archives automatically.

### Use cache during mirroring (cluster access required)

```bash
./scripts/mirror-images-to-registry.sh \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --mode full \
  --cache-dir ~/.cache/che-ipv6-mirror
```

### Dynamic image discovery (optional)

Some images (especially OLM/operator-related pulls) may only become visible after the cluster creates pods. You can mirror those images too:

```bash
./scripts/mirror-images-to-registry.sh \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --mode full \
  --mirror-from-namespace openshift-marketplace \
  --mirror-from-namespace openshift-operators \
  --mirror-from-namespace eclipse-che
```

Note: `--mirror-from-namespace` is ignored when `--prefetch-only` is used.

### Reliability controls

- **Timeouts**: each `skopeo copy` is guarded by `SKOPEO_TIMEOUT_SECONDS` (default `900`). If it hangs, it will be killed and retried.

Example:

```bash
SKOPEO_TIMEOUT_SECONDS=600 ./scripts/mirror-images-to-registry.sh --kubeconfig ~/ostest-kubeconfig.yaml --mode full
```

### Disk usage

The cache (especially in `--mode full`) can be **multiple GB** due to large images like UDI.

