# Deploy Eclipse Che with IPv6 Support

This repository contains scripts and documentation for testing [Eclipse Che Dashboard PR-1442](https://github.com/eclipse-che/che-dashboard/pull/1442), which adds IPv6 URL validation support.

## Purpose

This repository was created to test **PR-1442: Add IPv6 support for dashboard and factory URLs**.

The PR adds support for IPv6 URLs in factory flows, allowing users to create workspaces from repositories hosted on IPv6-only servers.

## Is it tested? How?

### Testing Overview

This repository provides automated scripts to deploy and test Eclipse Che with IPv6 URL validation on OpenShift clusters with IPv6 networking.

### Test Environment Setup

**1. Provision OpenShift Cluster with IPv6**

Use the OpenShift CI cluster bot to provision an IPv6-enabled cluster:

```bash
# Recommended: IPv6-only cluster
launch 4.20.2 metal,ipv6

# Alternative: Dual-stack with IPv6 primary
launch 4.20.2 metal,dualstack-primaryv6
```

See [cluster-bot-commands.md](./cluster-bot-commands.md) for detailed cluster options.

**2. Deploy Eclipse Che with PR-1442 Dashboard**

Run the automated deployment script:

```bash
# Clone this repository
git clone https://github.com/olexii4/deploy-che-ipv6-chectl.git
cd deploy-che-ipv6-chectl

# Run deployment script
./scripts/deploy-che-ipv6-chectl.sh
```

The script will:
- ✅ Verify IPv6 cluster networking
- ✅ Install chectl if needed
- ✅ Deploy Eclipse Che operator
- ✅ Configure dashboard with PR-1442 image (`quay.io/eclipse/che-dashboard:pr-1442`)
- ✅ Verify deployment and display Che URL

See [deploy-che-ipv6-chectl.md](./deploy-che-ipv6-chectl.md) for detailed deployment documentation.

**3. Run IPv6 Validation Tests**

Execute the automated test suite:

```bash
./scripts/test-ipv6-validation.sh
```

The test script validates:
- ✅ IPv6 URL parsing in factory flows
- ✅ Workspace creation from IPv6 Git repositories
- ✅ Support for various IPv6 URL formats
- ✅ Dashboard handling of IPv6 addresses

See [test-ipv6-validation.md](./test-ipv6-validation.md) for detailed testing documentation.

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

### Expected Results

- ✅ Dashboard correctly parses IPv6 URLs with square brackets
- ✅ Factory flow creates workspace from IPv6 repository URLs
- ✅ Git clone works over IPv6 network
- ✅ Workspace starts successfully with IPv6-hosted devfiles
- ✅ No URL validation errors for RFC-compliant IPv6 URLs

## Repository Contents

### Scripts

- **[scripts/deploy-che-ipv6-chectl.sh](./scripts/deploy-che-ipv6-chectl.sh)** - Automated deployment script
- **[scripts/test-ipv6-validation.sh](./scripts/test-ipv6-validation.sh)** - Automated IPv6 validation test suite

### Documentation

- **[deploy-che-ipv6-chectl.md](./deploy-che-ipv6-chectl.md)** - Comprehensive deployment guide
- **[test-ipv6-validation.md](./test-ipv6-validation.md)** - Testing guide and test scenarios
- **[cluster-bot-commands.md](./cluster-bot-commands.md)** - OpenShift cluster bot commands reference

## Quick Start

### Prerequisites

1. **OpenShift Cluster with IPv6**
   ```bash
   launch 4.20.2 metal,ipv6
   ```

2. **Required Tools**
   - `oc` CLI (OpenShift CLI)
   - `chectl` (Eclipse Che CLI)
   - `kubectl` (Kubernetes CLI)

### Deploy and Test

```bash
# Clone repository
git clone https://github.com/olexii4/deploy-che-ipv6-chectl.git
cd deploy-che-ipv6-chectl

# Deploy Eclipse Che with PR-1442 dashboard
./scripts/deploy-che-ipv6-chectl.sh

# Run IPv6 validation tests
./scripts/test-ipv6-validation.sh
```

## Usage Examples

### Basic Deployment

```bash
./scripts/deploy-che-ipv6-chectl.sh
```

### Custom Configuration

```bash
# Custom namespace
./scripts/deploy-che-ipv6-chectl.sh --namespace my-che

# Custom dashboard image (for testing different PR builds)
./scripts/deploy-che-ipv6-chectl.sh --dashboard-image quay.io/eclipse/che-dashboard:pr-1442-v2

# Skip IPv6 verification
./scripts/deploy-che-ipv6-chectl.sh --skip-ipv6-check
```

### Manual Testing

After deployment, you can manually test IPv6 URLs:

1. Access the Che dashboard
2. Navigate to factory URL:
   ```
   https://<che-host>/#http://[fd00::1]:8080/your-repo.git
   ```
3. Verify workspace creation succeeds

## Features Tested

### IPv6 URL Parsing (PR-1442)

- ✅ Square bracket notation for IPv6 addresses
- ✅ Port specification in IPv6 URLs
- ✅ Path components after IPv6 address
- ✅ Query parameters with IPv6 URLs
- ✅ HTTP and HTTPS schemes

### Factory Flow Integration

- ✅ Factory URL generation with IPv6
- ✅ Devfile loading from IPv6 URLs
- ✅ Git clone over IPv6
- ✅ Workspace provisioning with IPv6 resources

### Dashboard Validation

- ✅ URL input field accepts IPv6 addresses
- ✅ No validation errors for RFC-compliant IPv6 URLs
- ✅ Proper error messages for invalid IPv6 formats
- ✅ Factory flow works end-to-end with IPv6

## Cluster Configurations

### Recommended: IPv6-Only

```bash
launch 4.20.2 metal,ipv6
```

Pure IPv6 environment for thorough IPv6-only testing.

### Alternative: Dual-Stack

```bash
# IPv6 primary, IPv4 secondary
launch 4.20.2 metal,dualstack-primaryv6

# IPv4 primary, IPv6 secondary (less thorough for IPv6 testing)
launch 4.20.2 metal,dualstack
```

## Troubleshooting

### Common Issues

**Cluster not IPv6-enabled**
```bash
# Verify cluster networking
oc get network.config.openshift.io cluster -o yaml
```

**chectl not found**
```bash
# Install chectl
curl -sL https://che-incubator.github.io/chectl/install.sh | bash
```

**Dashboard image pull errors**
```bash
# Check pod status
oc get pods -n eclipse-che
oc describe pod <dashboard-pod> -n eclipse-che
```

See full documentation for detailed troubleshooting steps.

## Related Links

- **[Eclipse Che Dashboard PR-1442](https://github.com/eclipse-che/che-dashboard/pull/1442)** - The pull request being tested
- [Eclipse Che Documentation](https://eclipse.dev/che/docs/)
- [OpenShift CI Cluster Bot](https://docs.ci.openshift.org/docs/how-tos/cluster-claim/)

## License

EPL-2.0

## Contributing

This repository is specifically for testing PR-1442 IPv6 support. For issues or contributions to Eclipse Che itself, please visit the [Eclipse Che GitHub repository](https://github.com/eclipse-che/che).
