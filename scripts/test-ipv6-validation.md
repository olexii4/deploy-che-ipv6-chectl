<!--
Copyright (c) 2026 Red Hat, Inc.
This program and the accompanying materials are made
available under the terms of the Eclipse Public License 2.0
which is available at https://www.eclipse.org/legal/epl-2.0/

SPDX-License-Identifier: EPL-2.0

Contributors:
  Red Hat, Inc. - initial API and implementation
-->

# IPv6 URL Validation Testing Guide

This guide provides comprehensive testing procedures for IPv6 support in Eclipse Che Dashboard (PR-1442).

**Dashboard Image:** `quay.io/eclipse/che-dashboard:pr-1442`
**Related Issue:** [#23674](https://github.com/eclipse-che/che/issues/23674)

---

## Table of Contents

- [Overview](#overview)
- [Test Environment Setup](#test-environment-setup)
- [Testing Methods](#testing-methods)
- [Test Cases](#test-cases)
- [Automated Testing](#automated-testing)
- [Expected Results](#expected-results)
- [Troubleshooting](#troubleshooting)

---

## Overview

This testing guide covers validation of IPv6 URL support in the following Eclipse Che Dashboard components:

1. **Frontend URL Validation** - Factory location adapter, Git repository URLs
2. **Backend Server Binding** - Dual-stack network support (`::` binding)
3. **Container Registry URLs** - IPv6 address support in registry configuration
4. **Data Resolver API** - Fetching resources from IPv6 URLs

### What Was Changed

| Component | Change | Impact |
|-----------|--------|--------|
| Backend Server | Host binding: `0.0.0.0` → `::` | Dual-stack support |
| URL Validation Regex | Added `\[[0-9a-fA-F:.]+\]` pattern | IPv6 literal addresses |
| Git Client | Updated URL regex | IPv6 Git repository URLs |
| Container Registry | Updated URL pattern | IPv6 registry addresses |

---

## Test Environment Setup

### Prerequisites

- Eclipse Che deployed with PR-1442 dashboard image
- Access to Che dashboard (browser)
- kubectl CLI access to cluster
- curl or similar HTTP client

### Verify Dashboard Image

```bash
# Check dashboard image
kubectl get deployment che-dashboard -n eclipse-che \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Expected: quay.io/eclipse/che-dashboard:pr-1442
```

### Setup Test Services (Optional)

For full testing, deploy test HTTP servers:

```bash
# Deploy test devfile server (in-cluster)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ipv6-test-server
  namespace: eclipse-che
  labels:
    app: ipv6-test
spec:
  containers:
  - name: server
    image: python:3.11-alpine
    command:
      - sh
      - -c
      - |
        mkdir -p /data
        cat > /data/devfile.yaml <<'DEVFILE'
        schemaVersion: 2.2.0
        metadata:
          name: ipv6-test
          displayName: IPv6 Test Workspace
        components:
          - name: tools
            container:
              image: quay.io/devfile/universal-developer-image:ubi8-latest
        DEVFILE
        cd /data && python3 -m http.server 8080 --bind ::
    ports:
    - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: ipv6-test-server
  namespace: eclipse-che
spec:
  selector:
    app: ipv6-test
  ports:
  - port: 80
    targetPort: 8080
  ipFamilyPolicy: PreferDualStack
EOF
```

---

## Testing Methods

### Method 1: Browser Console Testing

Test URL validation directly in the browser console.

**Steps:**

1. Open Eclipse Che Dashboard: `https://<che-url>/dashboard/`
2. Open Browser DevTools (F12)
3. Switch to Console tab
4. Run test commands

**Test Commands:**

```javascript
// URL validation regex from PR-1442
const regex = /^(http(s)?:\/\/)((\w[\w.-]*)|(\[[0-9a-fA-F:.]+\]))(:\d+)?([-a-zA-Z0-9@:%._+~#=/[\]?&{}, ]*)$/;

// Test IPv6 loopback
console.log('IPv6 loopback:', regex.test('http://[::1]:8080/repo.git'));
// Expected: true ✅

// Test IPv6 standard address
console.log('IPv6 address:', regex.test('http://[2001:db8::1]/path'));
// Expected: true ✅

// Test IPv6 with port
console.log('IPv6 with port:', regex.test('https://[fe80::1]:443/resource'));
// Expected: true ✅

// Test IPv4-mapped IPv6
console.log('IPv4-mapped IPv6:', regex.test('http://[::ffff:192.168.1.1]:8080/repo.git'));
// Expected: true ✅

// Test invalid URLs
console.log('Missing brackets:', regex.test('http://::1:8080/repo.git'));
// Expected: false ❌

console.log('Invalid protocol:', regex.test('ftp://[::1]/file'));
// Expected: false ❌
```

### Method 2: Factory Flow Testing

Test IPv6 URLs through the workspace creation flow.

**Steps:**

1. Navigate to: `https://<che-url>/dashboard/#/load-factory`
2. Enter IPv6 Git repository URL in the form
3. Observe validation behavior

**Test URLs:**

```
# Valid IPv6 URLs (should be accepted)
http://[::1]:8080/repo.git
https://[2001:db8::1]/project/repo.git
http://[fe80::1]:8080/repos/my-project.git

# Invalid URLs (should show error)
http://::1:8080/repo.git  (missing brackets)
http://[::1:8080/repo.git  (missing closing bracket)
```

### Method 3: Container Registry Testing

Test IPv6 support in container registry configuration.

**Steps:**

1. Navigate to: `https://<che-url>/dashboard/#/user-preferences`
2. Click **Container Registries** tab
3. Click **Add Registry**
4. Enter IPv6 registry URL

**Test URLs:**

```
# Valid registry URLs
http://[::1]:5000
https://[2001:db8::1]:5000
http://[fd00:10:96::5]:5000

# Invalid URLs
http://::1:5000  (missing brackets)
```

### Method 4: Data Resolver API Testing

Test backend API with IPv6 URLs using Swagger UI or curl.

#### Using Swagger UI

1. Navigate to: `https://<che-url>/dashboard/swagger/`
2. Find: **Data Resolver** → `POST /api/data/resolver`
3. Click **Try it out**
4. Enter request body:

```json
{
  "url": "http://ipv6-test-server.eclipse-che.svc/devfile.yaml"
}
```

5. Click **Execute**
6. Observe response (should fetch devfile content)

#### Using curl (from dashboard pod)

```bash
# Get dashboard pod name
DASHBOARD_POD=$(kubectl get pods -n eclipse-che -l app=che-dashboard -o jsonpath='{.items[0].metadata.name}')

# Test Data Resolver API with IPv6 service
kubectl exec -n eclipse-che $DASHBOARD_POD -- curl -s -X POST \
  "http://localhost:8080/dashboard/api/data/resolver" \
  -H "Content-Type: application/json" \
  -d '{"url": "http://ipv6-test-server.eclipse-che.svc/devfile.yaml"}'

# Expected: YAML content of devfile
```

---

## Test Cases

### Test Suite 1: IPv6 URL Validation (Frontend)

| Test ID | URL | Expected | Validates |
|---------|-----|----------|-----------|
| TC1.1 | `http://[::1]:8080/repo.git` | ✅ Valid | IPv6 loopback with port |
| TC1.2 | `https://[2001:db8::1]/repo.git` | ✅ Valid | IPv6 standard address |
| TC1.3 | `http://[fe80::1]:8080/path` | ✅ Valid | IPv6 link-local |
| TC1.4 | `http://[::ffff:192.168.1.1]:8080/repo.git` | ✅ Valid | IPv4-mapped IPv6 |
| TC1.5 | `https://[2001:db8:85a3::8a2e:370:7334]:443/repo.git` | ✅ Valid | Full IPv6 address |
| TC1.6 | `http://[::1]:8080/repo.git?branch=main` | ✅ Valid | IPv6 with query params |
| TC1.7 | `http://::1:8080/repo.git` | ❌ Invalid | Missing brackets |
| TC1.8 | `http://[::1:8080/repo.git` | ❌ Invalid | Missing closing bracket |
| TC1.9 | `ftp://[::1]/file` | ❌ Invalid | Invalid protocol |
| TC1.10 | `http://[gggg::1]/path` | ❌ Invalid | Invalid hex characters |

### Test Suite 2: Backend Dual-Stack Binding

| Test ID | Description | Command | Expected |
|---------|-------------|---------|----------|
| TC2.1 | Verify :: binding | `netstat -tlnp \| grep :8080` | tcp6 on :::8080 |
| TC2.2 | Check IPv4 access | `curl http://localhost:8080/dashboard/` | 200 OK |
| TC2.3 | Check IPv6 access | `curl http://[::1]:8080/dashboard/` | 200 OK |
| TC2.4 | Pod has IPv6 IP | `kubectl get pod <pod> -o jsonpath='{.status.podIPs[*].ip}'` | IPv6 address present |

### Test Suite 3: Container Registry URLs

| Test ID | URL | Expected | Notes |
|---------|-----|----------|-------|
| TC3.1 | `http://[::1]:5000` | ✅ Valid | Local registry |
| TC3.2 | `https://[2001:db8::1]:5000` | ✅ Valid | Remote registry |
| TC3.3 | `http://[fd00:10:96::5]:5000` | ✅ Valid | Cluster service IP |
| TC3.4 | `http://::1:5000` | ❌ Invalid | Missing brackets |

### Test Suite 4: Data Resolver API

| Test ID | URL | Expected Response | Validates |
|---------|-----|-------------------|-----------|
| TC4.1 | `http://ipv6-test-server.eclipse-che.svc/devfile.yaml` | 200 OK | In-cluster service |
| TC4.2 | `http://[::1]:8090/devfile.yaml` | 500 ECONNREFUSED | URL parsing (expected failure) |
| TC4.3 | `https://example.com/devfile.yaml` | 200 OK | IPv4 still works |
| TC4.4 | Invalid URL | 400 Bad Request | Validation |

---

## Automated Testing

### Run Automated Test Script

Use the provided test script to run all validation tests:

```bash
# Make script executable
chmod +x test-ipv6-validation.sh

# Run tests (with kubeconfig from cluster bot)
./test-ipv6-validation.sh --kubeconfig ~/ostest-kubeconfig.yaml

# Or export KUBECONFIG and run
export KUBECONFIG=~/ostest-kubeconfig.yaml
./test-ipv6-validation.sh

# Cleanup test infrastructure
./test-ipv6-validation.sh --kubeconfig ~/ostest-kubeconfig.yaml --cleanup
```

### Unit Tests

The code includes Jest unit tests for IPv6 validation:

```bash
# Run frontend tests
cd packages/dashboard-frontend
yarn test factory-location-adapter

# Expected output:
# PASS  src/services/factory-location-adapter/__tests__/factoryLocationAdapter.spec.ts
#   ✓ should return true for http IPv6 literal address with port
#   ✓ should return true for https IPv6 literal address
#   ✓ should return true for http IPv4-mapped IPv6 address
```

---

## Expected Results

### ✅ What Should Work

1. **IPv6 URL Validation**
   - Dashboard accepts IPv6 URLs in square brackets
   - Factory flow validates IPv6 Git repository URLs
   - Container registry accepts IPv6 addresses
   - No validation errors for valid IPv6 URLs

2. **Backend Dual-Stack**
   - Dashboard backend listens on both IPv4 and IPv6
   - Accessible via `http://localhost:8080` (IPv4)
   - Accessible via `http://[::1]:8080` (IPv6) if supported
   - Pod has both IPv4 and IPv6 IPs (on dual-stack cluster)

3. **Data Resolver API**
   - Can fetch resources from IPv4 URLs
   - Correctly parses IPv6 URLs (even if connection fails)
   - Returns proper HTTP status codes

### ⚠️ Known Limitations

1. **IPv4-Only Clusters (CRC, Minikube)**
   - URL validation works ✅
   - Cannot actually connect to IPv6 services ❌
   - Backend binds to `::` but only IPv4 is available
   - Expected behavior: ECONNREFUSED when trying to connect to IPv6 addresses

2. **Network Namespace Isolation**
   - `[::1]` on host ≠ `[::1]` in pod
   - Host IPv6 services not accessible from pods
   - Use in-cluster services for testing connectivity

3. **TLS Certificates**
   - Self-signed certs may not include IPv6 SANs
   - May need to use `--insecure` flag for testing

---

## Troubleshooting

### Issue 1: IPv6 URLs Show "Invalid URL" Error

**Cause:** Dashboard image is not PR-1442

**Solution:**

```bash
# Verify dashboard image
kubectl get deployment che-dashboard -n eclipse-che \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Update if needed
kubectl set image deployment/che-dashboard -n eclipse-che \
  che-dashboard=quay.io/eclipse/che-dashboard:pr-1442
```

### Issue 2: Cannot Connect to IPv6 URLs

**Cause:** Cluster is IPv4-only (expected on CRC, Minikube)

**Explanation:**

This is EXPECTED behavior! The PR-1442 changes enable:
- ✅ IPv6 URL validation (frontend)
- ✅ IPv6 URL parsing (backend)
- ✅ Dual-stack server binding (backend)

But actual IPv6 connectivity requires:
- Dual-stack Kubernetes cluster
- IPv6-enabled network infrastructure

**Verification:**

```bash
# This proves URL parsing works:
kubectl exec -n eclipse-che $DASHBOARD_POD -- curl -X POST \
  http://localhost:8080/dashboard/api/data/resolver \
  -H "Content-Type: application/json" \
  -d '{"url": "http://[::1]:8090/file.yaml"}'

# Expected response:
# {"statusCode":500,"code":"ECONNREFUSED","message":"connect ECONNREFUSED ::1:8090"}
# ✅ This proves IPv6 URL was parsed correctly!
```

### Issue 3: Backend Not Listening on IPv6

**Symptoms:**

```bash
netstat -tlnp | grep :8080
# Shows only: tcp  0.0.0.0:8080
```

**Cause:** Old dashboard image without PR-1442 changes

**Solution:**

Restart pods with correct image:

```bash
kubectl delete pod -n eclipse-che -l app=che-dashboard
# Pods will be recreated with correct image
```

### Issue 4: Browser Console Tests Fail

**Cause:** Cached old JavaScript code

**Solution:**

- Hard refresh: Ctrl+Shift+R (or Cmd+Shift+R on Mac)
- Clear browser cache
- Try incognito/private browsing mode

---

## Test Results Documentation

### Recording Test Results

Document your test results:

```markdown
## Test Execution: YYYY-MM-DD

**Environment:**
- Cluster Type: Kind/GKE/EKS/CRC
- Kubernetes Version: v1.29.0
- Dashboard Image: quay.io/eclipse/che-dashboard:pr-1442
- IPv6 Support: Dual-stack / IPv4-only

**Test Suite 1: IPv6 URL Validation**
- TC1.1: ✅ PASS
- TC1.2: ✅ PASS
- TC1.3: ✅ PASS
...

**Test Suite 2: Backend Dual-Stack**
- TC2.1: ✅ PASS - Backend binds to ::
- TC2.2: ✅ PASS - IPv4 access works
- TC2.3: ⚠️ SKIP - IPv6 not available (IPv4-only cluster)
...

**Summary:**
- Total Tests: 20
- Passed: 17
- Failed: 0
- Skipped: 3 (IPv6 connectivity on IPv4-only cluster)

**Notes:**
- All URL validation tests passed
- Backend correctly binds to :: (dual-stack ready)
- IPv6 connectivity skipped due to IPv4-only cluster
```

---

## Additional Resources

- [Deployment Guide](./deploy-che-ipv6-chectl.md) - How to deploy Che with IPv6
- [Issue #23674](https://github.com/eclipse-che/che/issues/23674) - Original issue
- [RFC 3986 - IPv6 Literal Addresses](https://datatracker.ietf.org/doc/html/rfc3986#section-3.2.2)

---

**Document Version:** 1.0
**Last Updated:** 2026-01-26
**Dashboard Image:** `quay.io/eclipse/che-dashboard:pr-1442`

<!-- Generated by Claude Sonnet 4.5 -->
