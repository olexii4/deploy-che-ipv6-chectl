# Deploy Eclipse Che with IPv6 Support

This repository contains scripts and documentation for testing [Eclipse Che Dashboard PR-1442](https://github.com/eclipse-che/che-dashboard/pull/1442), which adds IPv6 URL validation support.

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

The script will:
- ✅ Verify IPv6 cluster networking
- ✅ Install chectl if needed
- ✅ Deploy Eclipse Che operator
- ✅ Configure dashboard with PR-1442 image (`quay.io/eclipse/che-dashboard:pr-1442`)
- ✅ Verify deployment and display Che URL

See [deploy-che-ipv6-chectl.md](./scripts/deploy-che-ipv6-chectl.md) for detailed deployment documentation.

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

- **[deploy-che-ipv6-chectl.md](./scripts/deploy-che-ipv6-chectl.md)** - Comprehensive deployment guide
- **[test-ipv6-validation.md](./scripts/test-ipv6-validation.md)** - Testing guide and test scenarios

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

