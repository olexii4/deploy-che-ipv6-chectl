# OpenShift CI Cluster Bot Commands for Eclipse Che IPv6 Testing

This document provides the best cluster bot commands for testing Eclipse Che with IPv6 support.

**Related Documentation:**
- [Deploy Eclipse Che with IPv6](./deploy-che-ipv6-chectl.md)
- [IPv6 Testing Guide](./test-ipv6-validation.md)

---

## Table of Contents

- [Recommended Commands](#recommended-commands)
- [Command Syntax](#command-syntax)
- [Available Parameters](#available-parameters)
- [Command Breakdown](#command-breakdown)
- [Alternative Configurations](#alternative-configurations)

---

## Recommended Commands

### Best Command for Eclipse Che IPv6 Testing

**Recommended (IPv6-Only):**
```bash
launch 4.20.2 metal,ipv6
```

**Why This Configuration:**
- ✅ **IPv6-only networking** - Pure IPv6 environment for thorough IPv6 URL validation testing
- ✅ **Standard cluster** - Adequate resources for Eclipse Che and workspaces
- ✅ **Metal platform** - Stable baremetal environment, good for comprehensive testing
- ✅ **OpenShift 4.20.2** - Latest stable release with IPv6 improvements
- ✅ **Faster provisioning** - Standard size deploys faster than large

### Alternative Commands

**1. Large Cluster (More Resources):**
```bash
launch 4.20.2 metal,ipv6,large
```
- More resources for multiple concurrent workspaces
- 8 vCPU, 32GB RAM per node (vs 4 vCPU, 16GB in standard)
- Better for stress testing

**2. Dual-Stack with IPv6 Primary:**
```bash
launch 4.20.2 metal,dualstack-primaryv6
```
- IPv6 primary, IPv4 secondary
- IPv6 testing with IPv4 fallback
- May require image mirroring for some services

**3. Dual-Stack with IPv4 Primary:**
```bash
launch 4.20.2 metal,dualstack
```
- IPv4 primary, IPv6 secondary
- Better compatibility with external services
- Good for dual-stack testing
- Faster provisioning
- May have different networking characteristics

**5. Compact Cluster (Resource-Limited Testing):**
```bash
launch 4.20.2 metal,dualstack,compact
```
- Smaller footprint
- Single node cluster
- Faster deployment
- Limited for testing multiple concurrent workspaces

---

## Command Syntax

### Basic Format
```
launch <version> <platform>,<param1>,<param2>,...
```

### Components

**1. Version** - OpenShift release version
- Format: `4.20.2` (major.minor.patch)
- Available versions: Check [OpenShift Releases](https://amd64.ocp.releases.ci.openshift.org/)
- Recommended: `4.20.2` or later for best IPv6 support

**2. Platform** - Deployment platform
- `metal` - Baremetal (recommended for IPv6 testing)
- `aws` - Amazon Web Services
- `gcp` - Google Cloud Platform
- `azure` - Microsoft Azure
- `vsphere` - VMware vSphere
- `ovirt` - oVirt/RHV
- `openstack` - OpenStack

**3. Parameters** - Comma-separated configuration options
- `ipv6` - IPv6-only cluster
- `dualstack` - Dual-stack (IPv4 primary, IPv6 secondary)
- `dualstack-primaryv6` - Dual-stack (IPv6 primary, IPv4 secondary)
- `large` - Larger node sizes (recommended for Che)
- `xlarge` - Extra-large nodes
- `compact` - Compact 3-node cluster

---

## Available Parameters

### Network Configuration

| Parameter | Description | IPv6 Support | Recommended for Che |
|-----------|-------------|--------------|---------------------|
| `ipv4` | IPv4-only cluster | ❌ No | ❌ No |
| `ipv6` | IPv6-only cluster | ✅ Full | ⚠️ Limited (external services) |
| `dualstack` | IPv4 primary, IPv6 secondary | ✅ Dual | ✅ Yes |
| `dualstack-primaryv6` | IPv6 primary, IPv4 secondary | ✅ Dual (preferred) | ✅✅ **Best** |

### Cluster Size

| Parameter | Nodes | vCPUs/Node | Memory/Node | Use Case |
|-----------|-------|------------|-------------|----------|
| (default) | 3 workers | 4 | 16 GB | Light testing |
| `large` | 3 workers | 8 | 32 GB | **Che + workspaces** |
| `xlarge` | 3 workers | 16 | 64 GB | Heavy workloads |
| `compact` | 3 masters | 8 | 24 GB | Resource-limited |

### Network Plugins

| Parameter | Description | IPv6 Support |
|-----------|-------------|--------------|
| (default) | OVN-Kubernetes | ✅ Full |
| `ovn` | Explicitly use OVN | ✅ Full |
| `ovn-hybrid` | OVN hybrid mode | ✅ Partial |
| `sdn` | OpenShift SDN (deprecated) | ❌ Limited |

### Additional Parameters

| Parameter | Description | Recommended |
|-----------|-------------|-------------|
| `preserve-bootstrap` | Keep bootstrap node | Optional |
| `fips` | FIPS mode | No |
| `proxy` | HTTP proxy | No |
| `mirror` | Disconnected mirror | No |
| `techpreview` | Tech preview features | Optional |
| `multi-zone` | Multi-AZ deployment | Optional |

---

## Command Breakdown

### Recommended Command Analysis

```bash
launch 4.20.2 metal,dualstack
```

**Component Breakdown:**

1. **`launch`** - Cluster bot command
   - Simplified syntax (equivalent to `workflow-launch`)
   - Creates temporary test cluster (4-6 hour lifetime)

2. **`4.20.2`** - OpenShift version
   - Latest stable release with IPv6 improvements
   - Full dual-stack support
   - Updated OVN-Kubernetes with IPv6 fixes

3. **`metal`** - Baremetal platform
   - **Pros:**
     - Predictable networking behavior
     - Full control over network stack
     - No cloud provider limitations
     - Best for IPv6 testing
   - **Cons:**
     - Slower provisioning (~30-45 min)
     - Limited to available baremetal capacity

4. **`dualstack`** - Dual-stack networking (IPv4 primary)
   - **Configuration:**
     - Services get IPv4 ClusterIP first, IPv6 second
     - Pods prefer IPv4 for egress, IPv6 available
     - Routes support both IPv4 and IPv6
   - **Pros:**
     - Better compatibility with external services
     - Tests IPv6 functionality without breaking IPv4
     - No image mirroring needed (can pull from quay.io via IPv4)
     - Most realistic current deployment scenario
   - **Cons:**
     - Less aggressive IPv6 testing than dualstack-primaryv6

**Default Cluster Size (Standard):**
   - **Specifications:**
     - 3 worker nodes
     - 4 vCPUs per node
     - 16 GB memory per node
   - **Sufficient for:**
     - Eclipse Che server
     - Che Dashboard
     - DevWorkspace Operator
     - 2-3 concurrent user workspaces
     - Standard testing workflows
   - **Note:** For more workspaces, use `large` parameter (8 vCPU, 32GB per node)

---

## Alternative Configurations

### For Different Testing Scenarios

#### 1. Maximum IPv6 Testing
```bash
launch 4.20.2 metal,ipv6,large
```
**Use when:**
- Testing pure IPv6 functionality
- Validating IPv6-only environments
- Finding IPv4 dependencies

**Limitations:**
- External registries may need IPv4
- Some container images may fail to pull
- Limited external connectivity

#### 2. Production-Like Environment
```bash
launch 4.20.2 metal,dualstack,large,multi-zone
```
**Use when:**
- Testing production deployment scenarios
- Validating HA configurations
- Testing zone failures

**Benefits:**
- Multi-zone deployment
- Better fault tolerance
- More realistic production testing

#### 3. Fast Iteration Testing
```bash
launch 4.20.2 aws,dualstack
```
**Use when:**
- Quick feedback needed
- Testing on cloud infrastructure
- Iterating on fixes

**Benefits:**
- Faster provisioning (~15-20 min)
- Good IPv6 support on AWS
- Better compatibility with external services
- Cost-effective for short tests

#### 4. Minimal Resource Testing
```bash
launch 4.20.2 metal,dualstack,compact
```
**Use when:**
- Limited cluster capacity
- Basic functionality testing
- Single workspace testing

**Limitations:**
- Only 3 control plane nodes (no separate workers)
- Limited concurrent workspaces
- May struggle with heavy workloads

#### 5. Latest Features Testing
```bash
launch 4.20.2 metal,dualstack-primaryv6,large,techpreview
```
**Use when:**
- Testing upcoming features
- Validating tech preview APIs
- Early adoption testing

**Risks:**
- Tech preview features may be unstable
- Not for production validation
- May have breaking changes

---

## Using the Cluster Bot

### Step 1: Access Cluster Bot

In Red Hat Internal Slack workspace:
```
@cluster-bot help
```

### Step 2: Launch Cluster

Send message to cluster bot:
```
launch 4.20.2 metal,dualstack-primaryv6,large
```

### Step 3: Wait for Response

The bot will respond with:
- Cluster creation confirmation
- Estimated time (30-45 min for metal)
- Cluster ID

### Step 4: Receive Credentials

After cluster is ready (~30-45 min), bot sends:
- Kubeconfig file (download link)
- Console URL
- API URL
- Credentials (kubeadmin password)

**Example response:**
```
Your cluster is ready!

Console: https://console-openshift-console.apps.ci-ln-12345.origin-ci.int.example.com
API: https://api.ci-ln-12345.origin-ci.int.example.com:6443
kubeadmin password: XXXXX-XXXXX-XXXXX-XXXXX

Download kubeconfig: [link]

Cluster will be deleted in 6 hours.
```

### Step 5: Configure Access

```bash
# Download kubeconfig
export KUBECONFIG=/path/to/downloaded-kubeconfig

# Verify access
oc whoami
oc get nodes

# Check IPv6 configuration
oc get network.config.openshift.io cluster -o yaml | grep -A 10 serviceNetwork
```

### Step 6: Deploy Eclipse Che

```bash
# Deploy using script
./deploy-che-ipv6-chectl.sh

# Or deploy manually
chectl server:deploy --platform openshift

# Patch dashboard image
oc patch checluster eclipse-che -n eclipse-che --type merge -p '
{
  "spec": {
    "components": {
      "dashboard": {
        "deployment": {
          "containers": [{
            "image": "quay.io/eclipse/che-dashboard:pr-1442",
            "imagePullPolicy": "Always",
            "name": "che-dashboard"
          }]
        }
      }
    }
  }
}'
```

---

## Cluster Lifetime and Management

### Cluster Duration

**Default Lifetime:** 4-6 hours
- Cluster is automatically deleted after expiration
- No way to extend lifetime
- Save all test results before expiration

### Best Practices

1. **Document cluster ID** - Keep track of cluster for reference
2. **Download logs early** - Export important logs before deletion
3. **Plan testing** - Complete testing within 4-6 hour window
4. **Multiple launches** - Launch new cluster if more time needed

### Cleanup

Clusters are automatically deleted. To manually delete:
```
@cluster-bot done <cluster-id>
```

---

## Troubleshooting

### Issue: Cluster Launch Fails

**Symptoms:**
```
Error: Failed to provision cluster
```

**Solutions:**
- Check platform capacity (metal may be full)
- Try alternative platform: `aws` instead of `metal`
- Simplify parameters: remove `large`, use defaults
- Check OpenShift version availability

### Issue: Kubeconfig Not Received

**Symptoms:**

No kubeconfig after 30+ minutes

**Solutions:**
```
@cluster-bot auth <cluster-id>
```

Re-sends authentication credentials

### Issue: IPv6 Not Working

**Symptoms:**

Cluster has no IPv6 addresses

**Verification:**
```bash
# Check network configuration
oc get network.config.openshift.io cluster -o yaml

# Should show IPv6 CIDRs:
# serviceNetwork:
# - fd00:10:96::/112
# clusterNetwork:
# - cidr: fd00:10:244::/56
```

**Solutions:**
- Verify correct parameters: `dualstack-primaryv6` or `ipv6`
- Check platform supports IPv6 (metal, aws, gcp)
- Launch new cluster if configuration is wrong

---

## Summary

**Best Command for Eclipse Che IPv6 Testing:**
```bash
launch 4.20.2 metal,dualstack
```

**Why:**
- ✅ Latest OpenShift with IPv6 improvements
- ✅ Dual-stack for compatibility and testing (IPv4 primary)
- ✅ Better compatibility with external services
- ✅ No image mirroring required
- ✅ Baremetal for predictable networking
- ✅ Faster provisioning (standard vs large)

**Alternatives:**
- **More resources:** `launch 4.20.2 metal,dualstack,large`
- **Advanced IPv6:** `launch 4.20.2 metal,dualstack-primaryv6`
- **Pure IPv6:** `launch 4.20.2 metal,ipv6` (requires image mirroring)
- **Quick testing:** `launch 4.20.2 aws,dualstack`

---

## Additional Resources

- [OpenShift CI Cluster Bot FAQ](https://github.com/openshift/ci-chat-bot/blob/main/docs/FAQ.md)
- [OpenShift Releases](https://amd64.ocp.releases.ci.openshift.org/)
- [Deploy Eclipse Che with IPv6](./deploy-che-ipv6-chectl.md)
- [IPv6 Testing Guide](./test-ipv6-validation.md)
- [Data Resolver Testing](./testing-data-resolver-api.md)

---

**Document Version:** 2.0
**Last Updated:** 2026-01-26
**Recommended Command:** `launch 4.20.2 metal,dualstack`

<!-- Generated by Claude Sonnet 4.5 -->

## Sources

- [OpenShift CI Cluster Bot FAQ](https://github.com/openshift/ci-chat-bot/blob/main/docs/FAQ.md)
- [Deploying OpenShift with IPv6 Static Addressing](https://blog.distributed-ci.io/ocp-ipv6-options.html)
- [Converting to IPv4/IPv6 dual stack networking](https://docs.openshift.com/container-platform/4.10/networking/ovn_kubernetes_network_provider/converting-to-dual-stack.html)
- [What is the state of dual-stack IPv4/IPv6 support in OpenShift Container Platform 4](https://access.redhat.com/solutions/5982721)
