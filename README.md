# Deploy Eclipse Che with IPv6 Support

Scripts and documentation for deploying Eclipse Che on OpenShift with IPv6 networking support.

## Overview

This repository contains deployment scripts and testing tools for Eclipse Che with IPv6 URL validation support (PR-1442). The scripts automate the deployment of Eclipse Che on OpenShift clusters with IPv6 networking.

## Contents

- **deploy-che-ipv6-chectl.sh** - Main deployment script using chectl
- **deploy-che-ipv6-chectl.md** - Comprehensive deployment guide
- **test-ipv6-validation.sh** - IPv6 URL validation test script
- **test-ipv6-validation.md** - Testing guide and documentation
- **cluster-bot-commands.md** - OpenShift CI cluster bot commands reference

## Quick Start

### Prerequisites

1. **OpenShift Cluster with IPv6 Support**
   ```bash
   # Launch via OpenShift CI cluster bot
   launch 4.20.2 metal,ipv6
   ```

2. **Required Tools**
   - `oc` CLI (OpenShift CLI)
   - `chectl` (Eclipse Che CLI)
   - `kubectl` (Kubernetes CLI)

### Deploy Eclipse Che

```bash
# Clone this repository
git clone https://github.com/olexii4/deploy-che-ipv6-chectl.git
cd deploy-che-ipv6-chectl

# Run deployment script
./deploy-che-ipv6-chectl.sh
```

### Test IPv6 URL Validation

```bash
# Run IPv6 validation tests
./test-ipv6-validation.sh
```

## Documentation

### Deployment Guide

See [deploy-che-ipv6-chectl.md](./deploy-che-ipv6-chectl.md) for detailed deployment instructions including:
- Cluster requirements
- Step-by-step deployment process
- Configuration options
- Troubleshooting guide

### Testing Guide

See [test-ipv6-validation.md](./test-ipv6-validation.md) for comprehensive testing documentation:
- IPv6 URL validation tests
- Factory URL testing
- Workspace creation with IPv6 repositories
- Test scenarios and expected results

### Cluster Bot Commands

See [cluster-bot-commands.md](./cluster-bot-commands.md) for OpenShift CI cluster provisioning:
- Recommended cluster configurations
- Alternative cluster options
- Command parameters reference

## Features

### IPv6 URL Support

The PR-1442 dashboard image includes support for IPv6 URLs in factory flows:

```
✅ http://[::1]:8080/repo.git
✅ http://[fd00::1]:8080/repo.git
✅ http://[2001:db8::1]:8080/repo.git
✅ https://[fd00::1]:8080/repo.git
```

### Automated Deployment

The deployment script provides:
- IPv6 cluster validation
- Automatic chectl installation
- Dashboard image configuration (PR-1442)
- Post-deployment verification
- Comprehensive error handling

### Comprehensive Testing

The test script validates:
- IPv6 URL parsing
- Factory URL creation
- Workspace provisioning
- Git repository access over IPv6
- Dashboard IPv6 URL handling

## Cluster Configurations

### Recommended: IPv6-Only

```bash
launch 4.20.2 metal,ipv6
```

Pure IPv6 environment for thorough testing.

### Alternative: Dual-Stack

```bash
# IPv6 primary, IPv4 secondary
launch 4.20.2 metal,dualstack-primaryv6

# IPv4 primary, IPv6 secondary
launch 4.20.2 metal,dualstack
```

## Usage Examples

### Basic Deployment

```bash
./deploy-che-ipv6-chectl.sh
```

### Custom Namespace

```bash
./deploy-che-ipv6-chectl.sh --namespace my-che
```

### Custom Dashboard Image

```bash
./deploy-che-ipv6-chectl.sh --dashboard-image quay.io/myorg/che-dashboard:my-tag
```

### Skip IPv6 Check

```bash
./deploy-che-ipv6-chectl.sh --skip-ipv6-check
```

## Troubleshooting

### Common Issues

**Issue: Cluster not IPv6 enabled**
```bash
# Verify cluster networking
oc get network.config.openshift.io cluster -o yaml
```

**Issue: chectl not found**
```bash
# Install chectl
curl -sL https://che-incubator.github.io/chectl/install.sh | bash
```

**Issue: Dashboard image pull errors**
```bash
# Check image availability
oc get pods -n eclipse-che
oc describe pod <dashboard-pod> -n eclipse-che
```

See the full documentation for detailed troubleshooting steps.

## Related Links

- [Eclipse Che Dashboard PR-1442](https://github.com/eclipse-che/che-dashboard/pull/1442)
- [Eclipse Che Documentation](https://eclipse.dev/che/docs/)
- [OpenShift CI Cluster Bot](https://docs.ci.openshift.org/docs/how-tos/cluster-claim/)

## License

EPL-2.0

## Contributing

This repository is for testing Eclipse Che IPv6 support. For issues or contributions to Eclipse Che itself, please visit the [Eclipse Che GitHub repository](https://github.com/eclipse-che/che).
