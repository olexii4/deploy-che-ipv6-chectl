# Create Che HTTP Proxy Pod

This script creates an HTTP proxy pod inside the OpenShift cluster that provides access to Eclipse Che when direct access from your laptop is not possible.

## Overview

The `create-che-proxy.sh` script deploys an nginx-based proxy pod within the cluster that:
- Has internal cluster access to Che services
- Can be accessed via `oc port-forward` from your laptop
- Preserves OAuth redirect URIs for proper authentication

## When to Use This Script

Use this script when:

- Direct access to the Che route is blocked (network/firewall restrictions)
- VPN credentials don't work or are not available
- You cannot use SOCKS proxy via SSH bastion
- You need OAuth authentication to work (unlike direct pod port-forward)

**Important**: This is an alternative workaround. The recommended approach is still SOCKS proxy (see [diagnose-che-access.md](./diagnose-che-access.md)).

## How It Works

The script creates:
1. **ConfigMap**: nginx configuration that proxies requests to internal Che service
2. **Pod**: nginx container running the proxy with the configuration

The nginx proxy:
- Listens on port 8080
- Forwards requests to `che-host.eclipse-che.svc.cluster.local:8080`
- Preserves the `Host` header with the route hostname for OAuth redirects
- Supports WebSocket connections for IDE features

## Prerequisites

- oc CLI configured and connected to OpenShift cluster
- Eclipse Che deployed in a namespace (default: `eclipse-che`)
- Sufficient permissions to create pods and configmaps

## Usage

```bash
# Basic usage (uses default namespace: eclipse-che)
./scripts/create-che-proxy.sh

# Specify custom Che namespace
./scripts/create-che-proxy.sh my-che-namespace
```

## Access Che via Proxy

After running the script:

```bash
# 1. Start port-forward (keep this running)
oc port-forward -n eclipse-che pod/che-proxy 8080:8080

# 2. Open browser and access Che at:
http://localhost:8080/dashboard/
```

## What Gets Created

### ConfigMap: che-proxy-config

Contains nginx configuration:

```nginx
events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;

        location / {
            # Proxy to Che service (internal cluster access)
            proxy_pass https://che-host.eclipse-che.svc.cluster.local:8080;
            proxy_ssl_verify off;

            # Preserve original host for OAuth redirects
            proxy_set_header Host <che-route-hostname>;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Forwarded-Host <che-route-hostname>;

            # WebSocket support
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
```

### Pod: che-proxy

Runs nginx:alpine image with the proxy configuration mounted.

## Cleanup

To remove the proxy pod and configuration:

```bash
# Remove proxy resources
oc delete pod/che-proxy configmap/che-proxy-config -n eclipse-che

# Or if using custom namespace
oc delete pod/che-proxy configmap/che-proxy-config -n <namespace>
```

## Troubleshooting

### Issue: Port-forward connection refused

**Cause**: Proxy pod is not ready yet

**Solution**:
```bash
# Check pod status
oc get pod che-proxy -n eclipse-che

# Wait for pod to be Ready
oc wait --for=condition=Ready pod/che-proxy -n eclipse-che --timeout=60s

# Then retry port-forward
oc port-forward -n eclipse-che pod/che-proxy 8080:8080
```

---

### Issue: 502 Bad Gateway when accessing localhost:8080

**Cause**: Che service is not accessible from the proxy pod

**Solution**:
```bash
# Verify Che service exists
oc get svc che-host -n eclipse-che

# Check Che pods are running
oc get pods -n eclipse-che -l app=che

# Test from proxy pod
oc exec -n eclipse-che che-proxy -- curl -k https://che-host:8080/healthz
```

---

### Issue: OAuth redirect fails with "redirect_uri mismatch"

**Cause**: OAuth is configured for the route hostname but accessed via localhost

**Why this might still fail**: While this proxy preserves the `Host` header to help with OAuth, some OAuth flows check the browser's URL which will be `http://localhost:8080`. This can still cause redirect mismatches.

**Solution**:
1. Use SOCKS proxy instead (recommended) - see [diagnose-che-access.md](./diagnose-che-access.md)
2. Or modify /etc/hosts to map route hostname to 127.0.0.1:
   ```bash
   # Get route hostname
   ROUTE_HOST=$(oc get route che -n eclipse-che -o jsonpath='{.spec.host}')

   # Add to /etc/hosts
   echo "127.0.0.1 ${ROUTE_HOST}" | sudo tee -a /etc/hosts

   # Access at:
   https://${ROUTE_HOST}:8080/dashboard/
   ```

---

### Issue: Connection timeout or slow performance

**Cause**: Port-forward adds network overhead

**Optimization**: This is expected with port-forward. For better performance:
- Use SOCKS proxy instead (Solution 1 in diagnose-che-access.md)
- Or request a cluster with public access

---

## Limitations

This approach has several limitations:

1. **OAuth issues**: Browser sees `localhost:8080` but OAuth expects route hostname
2. **Performance**: Port-forward adds latency and overhead
3. **Single connection**: Only one port-forward session at a time
4. **HTTPS**: Accessing via HTTP (not HTTPS) which some features may require

For production or long-term use, prefer:
- SOCKS proxy via SSH bastion (recommended)
- VPN access to cluster network
- Cluster with public routes

## Comparison with Direct Port-Forward

| Approach | OAuth Support | Performance | Setup Complexity |
|----------|---------------|-------------|------------------|
| Direct port-forward to che pod | ❌ Breaks | Fast | Simple |
| Proxy pod + port-forward | ⚠️ Partial | Medium | Medium |
| SOCKS proxy via SSH | ✅ Full | Good | Medium |
| VPN access | ✅ Full | Best | Varies |

## Related Documentation

- [diagnose-che-access.md](./diagnose-che-access.md) - Comprehensive access troubleshooting
- [deploy-che-ipv6-chectl.md](./deploy-che-ipv6-chectl.md) - Deployment guide
- [test-ipv6-validation.md](./test-ipv6-validation.md) - Testing guide

## Example Workflow

Complete workflow using this script:

```bash
# 1. Deploy Eclipse Che
./scripts/deploy-che-ipv6-chectl.sh --kubeconfig ~/cluster.kubeconfig

# 2. If direct access fails, create proxy
./scripts/create-che-proxy.sh

# 3. Start port-forward in one terminal
oc port-forward -n eclipse-che pod/che-proxy 8080:8080

# 4. Access in browser
open http://localhost:8080/dashboard/

# 5. When done, cleanup
oc delete pod/che-proxy configmap/che-proxy-config -n eclipse-che
```

## Advanced: Custom nginx Configuration

If you need custom nginx settings, edit the ConfigMap before creating the pod:

```bash
# Create configmap with custom settings
cat <<EOF | oc apply -n eclipse-che -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: che-proxy-config
data:
  nginx.conf: |
    events {
        worker_connections 2048;
    }
    http {
        # Add custom settings here
        client_max_body_size 100M;

        server {
            listen 8080;
            location / {
                proxy_pass https://che-host.eclipse-che.svc.cluster.local:8080;
                proxy_ssl_verify off;

                # Your custom headers here
            }
        }
    }
EOF

# Then create the pod (script will use existing configmap)
./scripts/create-che-proxy.sh
```

## Support

If the proxy approach doesn't work:

1. Check proxy pod logs:
   ```bash
   oc logs -n eclipse-che che-proxy
   ```

2. Verify Che is accessible from within cluster:
   ```bash
   oc run test-curl --image=curlimages/curl --rm -i -n eclipse-che -- \
     curl -k https://che-host:8080/healthz
   ```

3. Use alternative access methods from [diagnose-che-access.md](./diagnose-che-access.md)
