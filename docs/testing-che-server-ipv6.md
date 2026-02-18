# Testing Eclipse Che Server IPv6 Support

This guide explains how to test Eclipse Che Server IPv6 factory URL parser implementation on an IPv6-only OpenShift cluster.

## Prerequisites

1. **IPv6 OpenShift Cluster**
   - Provision via cluster-bot: `launch 4.20.2 metal,ipv6`
   - Save kubeconfig to `~/ostest-kubeconfig.yaml`

2. **Built Che Server Image**
   - Build from PR: `quay.io/eclipse/che-server:pr-XXX`
   - Or use comment from PR build workflow

3. **Deploy Scripts Repository**
   ```bash
   git clone https://github.com/olexii4/deploy-che-ipv6-chectl.git
   cd deploy-che-ipv6-chectl
   ```

## Step 1: Mirror Images

Mirror all images to the cluster's local registry (IPv6 clusters cannot pull from external registries):

```bash
./scripts/mirror-images-to-registry.sh \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --dashboard-image pr-1442 \
  --mode full \
  --parallel 4
```

**What this does:**
- Mirrors Eclipse Che images to cluster's local registry
- Creates ImageContentSourcePolicy for image redirection
- Waits for cluster nodes to reboot (~10-15 minutes)

## Step 2: Deploy Eclipse Che with Custom Che Server Image

Deploy Che with your PR's che-server image:

```bash
./scripts/deploy-che-from-bundles.sh \
  --kubeconfig ~/ostest-kubeconfig.yaml \
  --dashboard-image pr-1442 \
  --che-server-image quay.io/eclipse/che-server:pr-951 \
  --namespace eclipse-che
```

**Parameters:**
- `--che-server-image`: Your custom che-server image from the PR
- `--dashboard-image`: Dashboard image (use pr-XXXX shortcut)
- `--namespace`: Eclipse Che namespace (default: eclipse-che)

**Output:**
The script will show:
- ✅ Che URL
- ✅ Proxy configuration from kubeconfig
- ✅ Chrome launch commands for your OS
- ✅ Next steps to access the dashboard

## Step 3: Deploy IPv6 Test Infrastructure

Deploy test servers with IPv6 addresses to validate GitHub URL parser:

```bash
./scripts/test-ipv6-validation.sh --kubeconfig ~/ostest-kubeconfig.yaml
```

**What this deploys:**
- Git HTTP server with GitHub API mock on IPv6
- Devfile server on IPv6
- GitHub-compatible repository layout
- GitHub API endpoints (`/api/v3/*`)

**Test repositories created:**
- `/testuser/nodejs-hello-world` (GitHub-style)
- `/testuser/python-hello-world` (GitHub-style)
- `/nodejs-hello-world.git` (direct Git access)
- `/python-hello-world.git` (direct Git access)

## Step 4: Test GitHub URL Parser with IPv6

### Get Test Infrastructure IPs

```bash
export KUBECONFIG=~/ostest-kubeconfig.yaml

# Get git server IPv6 address
GIT_IPV6=$(oc get svc git-server -n che-test -o jsonpath='{.spec.clusterIP}')
echo "Git Server (IPv6): http://[${GIT_IPV6}]:8080"

# Get Che URL
CHE_URL=$(oc get checluster eclipse-che -n eclipse-che -o jsonpath='{.status.cheURL}')
echo "Che URL: ${CHE_URL}"
```

### Launch Chrome with Proxy

```bash
# Close existing Chrome windows
killall "Google Chrome" 2>/dev/null

# macOS
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --proxy-server="$(grep proxy-url $KUBECONFIG | awk '{print $2}')" \
  --user-data-dir="/tmp/chrome-che-proxy-$(date +%s)" \
  --no-first-run \
  "${CHE_URL}/dashboard/api/swagger/static/index.html"

# Linux
google-chrome \
  --proxy-server="$(grep proxy-url $KUBECONFIG | awk '{print $2}')" \
  --user-data-dir="/tmp/chrome-che-proxy-$(date +%s)" \
  --no-first-run \
  "${CHE_URL}/dashboard/api/swagger/static/index.html"
```

### Test via Swagger API

Navigate to: **POST /dashboard/api/data/resolver**

#### Test Case 1: GitHub-style Repository URL (IPv6)

Test that the GitHub URL parser recognizes IPv6 addresses:

```json
{
  "url": "http://[fd00::1]:8080/testuser/nodejs-hello-world"
}
```

**Expected Result:**
- HTTP 200 response
- Devfile content returned
- GitHub URL parser successfully handled IPv6 address

**What this validates:**
- IPv6 bracket notation parsing in GitHub URLs
- Pattern matching for GitHub-style URLs with IPv6
- URL parser recognizes IPv6 server as GitHub-compatible

#### Test Case 2: GitHub API Endpoint (IPv6)

Test that GitHub API calls work over IPv6:

```json
{
  "url": "http://[fd00::1]:8080/api/v3/user"
}
```

**Expected Result:**
- HTTP 200 response
- JSON user data returned

**What this validates:**
- GitHub API client can connect to IPv6 addresses
- GitHub server detection works with IPv6

#### Test Case 3: GitHub Clone URL with Branch (IPv6)

```json
{
  "url": "http://[fd00::1]:8080/testuser/nodejs-hello-world/tree/main"
}
```

**Expected Result:**
- HTTP 200 response
- Devfile content for specific branch

**What this validates:**
- IPv6 URLs with path segments (branches)
- Complex GitHub URL parsing with IPv6

#### Test Case 4: Direct Git Repository (IPv6)

```json
{
  "url": "http://[fd00::1]:8080/nodejs-hello-world.git"
}
```

**Expected Result:**
- HTTP 200 response
- Devfile content returned

**What this validates:**
- Direct .git URLs work with IPv6
- Fallback URL patterns handle IPv6

## GitHub API Mock Endpoints

The test infrastructure provides GitHub-compatible API endpoints:

### GET /api/v3/user
Returns authenticated user information:
```json
{
  "id": 1,
  "login": "testuser",
  "name": "Test User",
  "email": "test@example.com"
}
```

### GET /api/v3/repos/{user}/{repo}
Returns repository information:
```json
{
  "id": 1,
  "name": "nodejs-hello-world",
  "full_name": "testuser/nodejs-hello-world",
  "private": false,
  "owner": {
    "login": "testuser",
    "id": 1
  },
  "html_url": "http://[IPv6]:8080/testuser/nodejs-hello-world",
  "description": "Test repository",
  "default_branch": "master"
}
```

### Access Pattern
All API endpoints are accessible via IPv6:
```
http://[fd00::cafe::1]:8080/api/v3/user
http://[fd00::cafe::1]:8080/api/v3/repos/testuser/nodejs-hello-world
```

## Verification Checklist

After deployment and testing, verify:

- ✅ Che server pod is running with custom image
  ```bash
  oc get pods -n eclipse-che -l app.kubernetes.io/component=che
  oc describe pod -n eclipse-che -l app.kubernetes.io/component=che | grep Image:
  ```

- ✅ GitHub URL parser accepts IPv6 URLs
  - Test via Swagger API returns HTTP 200
  - No "invalid URL" errors in che-server logs

- ✅ Git server is accessible via IPv6
  ```bash
  oc run test-curl --image=curlimages/curl:latest --rm -i --restart=Never -n che-test -- \
    curl -s "http://[${GIT_IPV6}]:8080/testuser/nodejs-hello-world/info/refs?service=git-upload-pack"
  ```

- ✅ GitHub API endpoints respond correctly
  ```bash
  oc run test-curl --image=curlimages/curl:latest --rm -i --restart=Never -n che-test -- \
    curl -s "http://[${GIT_IPV6}]:8080/api/v3/user"
  ```

- ✅ Che server logs show no IPv6-related errors
  ```bash
  oc logs -n eclipse-che deployment/che-server | grep -i "ipv6\|bracket\|invalid.*url"
  ```

## Test Scenarios Coverage

### GitHub URL Parser Scenarios

| Scenario | Test URL Example | Expected Result |
|----------|-----------------|-----------------|
| Basic GitHub URL | `http://[IPv6]:8080/user/repo` | ✅ Parsed correctly |
| With branch | `http://[IPv6]:8080/user/repo/tree/branch` | ✅ Branch extracted |
| With PR | `http://[IPv6]:8080/user/repo/pull/123` | ✅ PR ID extracted |
| Direct .git | `http://[IPv6]:8080/repo.git` | ✅ Parsed correctly |
| GitHub API | `http://[IPv6]:8080/api/v3/user` | ✅ API responds |

### Edge Cases

| Edge Case | Test | Expected |
|-----------|------|----------|
| IPv6 loopback | `http://[::1]:8080/user/repo` | ✅ Works |
| IPv6 with port | `http://[fd00::1]:8443/user/repo` | ✅ Works |
| Full IPv6 address | `http://[2001:db8::1]:8080/user/repo` | ✅ Works |

## Troubleshooting

### Issue: Cannot access Git server

**Symptom:** curl returns "connection refused" or timeout

**Debug:**
```bash
# Check if service has IPv6 IP
oc get svc git-server -n che-test -o yaml | grep clusterIP

# Check if pod is running
oc get pods -n che-test -l app=git-server

# Check pod logs
oc logs -n che-test deployment/git-server
```

### Issue: Swagger API returns 400 "Invalid URL"

**Symptom:** API rejects IPv6 URLs with brackets

**Debug:**
```bash
# Check che-server logs for URL validation errors
oc logs -n eclipse-che deployment/che-server | tail -100

# Verify che-server image is the PR image
oc get deployment che-server -n eclipse-che -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Issue: GitHub API mock not responding

**Symptom:** `/api/v3/user` returns 404

**Debug:**
```bash
# Test from within cluster
oc run test-curl --image=curlimages/curl:latest --rm -i --restart=Never -n che-test -- \
  curl -v "http://[${GIT_IPV6}]:8080/api/v3/user"

# Check lighttpd configuration
oc exec -n che-test deployment/git-server -- cat /tmp/lighttpd.conf
```

## Expected Results

After successful testing:

- ✅ **238 unit tests passing** in che-server codebase
- ✅ **39 IPv6-specific tests** covering all parsers
- ✅ **GitHub URL parser** recognizes IPv6 GitHub-like servers
- ✅ **Factory URLs work** with IPv6 repository addresses
- ✅ **Workspace creation succeeds** from IPv6-hosted repositories
- ✅ **No CodeQL security warnings** (regex injection fixed)

## Cleanup

Remove test infrastructure:

```bash
./scripts/test-ipv6-validation.sh --kubeconfig ~/ostest-kubeconfig.yaml --cleanup
```

Remove Eclipse Che:

```bash
oc delete checluster eclipse-che -n eclipse-che
oc delete namespace eclipse-che
```

## Additional Resources

- **GitHub URL Parser Implementation:** `wsmaster/che-core-api-factory-github-common/src/main/java/org/eclipse/che/api/factory/server/github/AbstractGithubURLParser.java`
- **Test Coverage:** `wsmaster/che-core-api-factory-github/src/test/java/org/eclipse/che/api/factory/server/github/GithubURLParserTest.java`
- **Deploy Scripts:** https://github.com/olexii4/deploy-che-ipv6-chectl

## License

EPL-2.0
