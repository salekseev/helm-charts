---
title: Research Session
query: "Integration testing approaches for Helm charts: kubectl image shell compatibility issues, Terratest evaluation vs bash-based tests, chart-testing tool, and best practices for GitHub Actions CI/CD environments"
date: 11/8/2025
time: 2:01:24 PM
timestamp: 2025-11-08T19:01:24.358Z
exchanges: 1
---

# Research Session

## Initial Query

**Question:** Integration testing approaches for Helm charts: kubectl image shell compatibility issues, Terratest evaluation vs bash-based tests, chart-testing tool, and best practices for GitHub Actions CI/CD environments

**Response:**

# Integration Testing for Helm Charts: Comprehensive Analysis

## Executive Summary

Based on your project context, you're at a critical decision point between fixing bash-based integration tests or adopting Terratest. Given that Task 11 is marked complete with successful integration tests, and you're experiencing kubectl image shell compatibility issues during cleanup, the optimal path is **hybrid approach**: maintain bash-based core tests while selectively adopting chart-testing (ct) for enhanced validation. Full Terratest migration is premature given your working implementation.

## Current State Analysis

### kubectl Image Shell Compatibility Issues

The `registry.k8s.io/kubectl:v1.31.0` image uses a **distroless base** with minimal shell support, causing bash script failures. This is intentional for security but creates operational challenges:

**Root Cause:**
- Distroless images contain only `/bin/sh` (busybox-based) or no shell at all
- Bash-specific constructs (`[[`, `${var^^}`, arrays) fail in POSIX sh
- Your cleanup jobs likely use bashisms incompatible with minimal shells

**Immediate Solutions:**

1. **Switch to shell-compatible kubectl image:**
```yaml
# tests/integration/cleanup-job.yaml
image: bitnami/kubectl:1.31.0  # Full shell support
# OR
image: alpine/k8s:1.31.0       # Alpine-based with bash
```

2. **Convert scripts to POSIX sh compatibility:**
```bash
# Before (bash-specific)
if [[ "${STATUS}" == "Running" ]]; then
    POD_NAME="${POD_NAME^^}"
fi

# After (POSIX sh compatible)
if [ "${STATUS}" = "Running" ]; then
    POD_NAME=$(echo "${POD_NAME}" | tr '[:lower:]' '[:upper:]')
fi
```

3. **Install bash in cleanup job init container:**
```yaml
initContainers:
- name: install-bash
  image: registry.k8s.io/kubectl:v1.31.0
  command: ['/bin/sh', '-c']
  args:
  - |
    # This won't work with distroless, use bitnami instead
    apk add --no-cache bash
```

## Bash-Based Testing: Current Implementation Assessment

### Strengths of Your Current Approach

Your completed Task 11 demonstrates **production-ready bash testing** with:

1. **Full deployment validation:**
```bash
# tests/integration/verify-deployment.sh
#!/bin/bash
set -euo pipefail

# PostgreSQL readiness
kubectl wait --for=condition=ready pod -l app=postgresql -n spicedb-test --timeout=120s

# SpiceDB deployment
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=spicedb -n spicedb-test --timeout=180s

# Migration job completion
kubectl wait --for=condition=complete job/spicedb-migrate -n spicedb-test --timeout=300s

# Health endpoint validation
POD=$(kubectl get pod -l app.kubernetes.io/name=spicedb -n spicedb-test -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n spicedb-test "${POD}" -- wget -q -O- --header="authorization: Bearer ${PRESHARED_KEY}" http://localhost:8443/healthz
```

2. **Upgrade and persistence testing:**
```bash
# tests/integration/verify-persistence.sh
#!/bin/bash
set -euo pipefail

NAMESPACE="spicedb-test"
PRESHARED_KEY=$(kubectl get secret -n ${NAMESPACE} spicedb -o jsonpath='{.data.preshared-key}' | base64 -d)

# Write test schema
kubectl exec -n ${NAMESPACE} deployment/spicedb -- \
  spicedb schema write --endpoint=localhost:50051 \
  --token="${PRESHARED_KEY}" \
  --schema-definition-file=/test-schema.zed

# Perform upgrade
helm upgrade spicedb ./charts/spicedb \
  --namespace ${NAMESPACE} \
  --reuse-values \
  --set image.tag=v1.35.0

# Verify data persisted
kubectl exec -n ${NAMESPACE} deployment/spicedb -- \
  spicedb schema read --endpoint=localhost:50051 \
  --token="${PRESHARED_KEY}" | grep "definition user"
```

### Weaknesses and Pain Points

1. **Error handling complexity:**
```bash
# Brittle failure modes
kubectl wait --for=condition=ready pod -l app=spicedb --timeout=60s || {
    echo "Pod failed to become ready"
    kubectl describe pod -l app=spicedb
    kubectl logs -l app=spicedb --tail=50
    exit 1
}
```

2. **No structured test reporting:**
- CI/CD sees only exit codes (0 or 1)
- No TAP/JUnit output for GitHub Actions test reporting
- Difficult to track which specific assertion failed

3. **State management burden:**
- Manual Kind cluster lifecycle
- Manual namespace creation/cleanup
- Test isolation challenges

## Chart Testing (ct) Tool: Recommended Enhancement

The **Helm chart-testing** tool is purpose-built for Helm CI/CD and integrates seamlessly with GitHub Actions.

### Installation and Setup

```yaml
# .github/workflows/integration-test.yaml
name: Integration Tests

on:
  pull_request:
    paths:
    - 'charts/spicedb/**'
  push:
    branches: [main, master]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0  # Required for ct to detect changes

    - name: Set up Helm
      uses: azure/setup-helm@v4
      with:
        version: v3.14.0

    - name: Set up chart-testing
      uses: helm/chart-testing-action@v2.6.1

    - name: Create Kind cluster
      uses: helm/kind-action@v1.9.0
      with:
        node_image: kindest/node:v1.31.0

    - name: Install PostgreSQL
      run: |
        helm repo add bitnami https://charts.bitnami.com/bitnami
        helm install postgresql bitnami/postgresql \
          --set auth.password=spicedb \
          --set primary.persistence.size=1Gi \
          --wait --timeout 3m

    - name: Run chart-testing (install)
      run: |
        ct install \
          --charts charts/spicedb \
          --helm-extra-set-args "--set=datastore.engine=postgres --set=datastore.uri=postgresql://postgres:spicedb@postgresql:5432/spicedb"

    - name: Run chart-testing (upgrade)
      run: |
        ct install --upgrade \
          --charts charts/spicedb
```

### ct Configuration File

```yaml
# ct.yaml (repository root)
chart-dirs:
  - charts
chart-repos:
  - bitnami=https://charts.bitnami.com/bitnami
helm-extra-args: --timeout 10m
validate-maintainers: false
check-version-increment: true
debug: true

# Additional test values
additional-test-values:
  - tests/values/production-postgres.yaml
  - tests/values/production-cockroachdb.yaml
  - tests/values/ha-configuration.yaml
```

### Enhanced Test Values Files

```yaml
# tests/values/production-postgres.yaml
datastore:
  engine: postgres
  uri: "postgresql://spicedb:spicedb@postgresql:5432/spicedb?sslmode=require"

replicaCount: 3

resources:
  requests:
    memory: 256Mi
    cpu: 250m
  limits:
    memory: 512Mi
    cpu: 500m

podDisruptionBudget:
  enabled: true

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
```

### Key ct Advantages

1. **Automatic change detection:** Tests only modified charts
2. **Version increment validation:** Ensures Chart.yaml version bumps
3. **Upgrade testing:** Automatically tests upgrade path from previous version
4. **Multiple values testing:** Validates different configurations in single run
5. **Native GitHub Actions integration:** Detailed test reporting

## Terratest Evaluation: When to Adopt

### Terratest Overview

Terratest is a Go library for infrastructure testing, excellent for complex scenarios requiring programmatic control.

**Ideal Use Cases for SpiceDB Chart:**

1. **Complex multi-chart dependencies:**
```go
// tests/terratest/spicedb_full_stack_test.go
func TestSpiceDBWithExternalDatastore(t *testing.T) {
    t.Parallel()
    
    // Install PostgreSQL
    postgresOptions := &helm.Options{
        KubectlOptions: k8s.NewKubectlOptions("", "", "spicedb-test"),
        SetValues: map[string]string{
            "auth.password": "testpass",
        },
    }
    helm.Install(t, postgresOptions, "bitnami/postgresql", "postgresql")
    defer helm.Delete(t, postgresOptions, "postgresql", true)
    
    // Wait for PostgreSQL
    k8s.WaitUntilPodAvailable(t, postgresOptions.KubectlOptions, "postgresql-0", 30, 5*time.Second)
    
    // Install SpiceDB
    spicedbOptions := &helm.Options{
        KubectlOptions: postgresOptions.KubectlOptions,
        SetValues: map[string]string{
            "datastore.engine": "postgres",
            "datastore.uri": "postgresql://postgres:testpass@postgresql:5432/spicedb",
        },
    }
    helm.Install(t, spicedbOptions, "../../charts/spicedb", "spicedb")
    defer helm.Delete(t, spicedbOptions, "spicedb", true)
    
    // Validation
    k8s.WaitUntilDeploymentAvailable(t, spicedbOptions.KubectlOptions, "spicedb", 30, 5*time.Second)
    
    // Functional testing
    pod := k8s.ListPods(t, spicedbOptions.KubectlOptions, metav1.ListOptions{
        LabelSelector: "app.kubernetes.io/name=spicedb",
    })[0]
    
    output := k8s.RunKubectlAndGetOutput(t, spicedbOptions.KubectlOptions,
        "exec", pod.Name, "--",
        "wget", "-qO-", "http://localhost:8443/healthz")
    
    require.Contains(t, output, "ok")
}
```

2. **Advanced validation requiring Go logic:**
```go
func TestMigrationJobCorrectness(t *testing.T) {
    helmChartPath := "../../charts/spicedb"
    
    options := &helm.Options{
        SetValues: map[string]string{
            "migrations.enabled": "true",
        },
    }
    
    output := helm.RenderTemplate(t, options, helmChartPath, "migration-job", []string{"templates/hooks/migration-job.yaml"})
    
    var job batchv1.Job
    helm.UnmarshalK8SYaml(t, output, &job)
    
    // Complex assertions
    require.Equal(t, "pre-install,pre-upgrade", job.Annotations["helm.sh/hook"])
    require.Equal(t, "0", job.Annotations["helm.sh/hook-weight"])
    require.Equal(t, int32(3), *job.Spec.BackoffLimit)
    require.Equal(t, int64(600), *job.Spec.ActiveDeadlineSeconds)
    
    // Verify environment variables match deployment
    deploymentOutput := helm.RenderTemplate(t, options, helmChartPath, "deployment", []string{"templates/deployment.yaml"})
    var deployment appsv1.Deployment
    helm.UnmarshalK8SYaml(t, deploymentOutput, &deployment)
    
    migrationEnv := job.Spec.Template.Spec.Containers[0].Env
    deploymentEnv := deployment.Spec.Template.Spec.Containers[0].Env
    
    require.Subset(t, deploymentEnv, migrationEnv, "Migration job should inherit datastore env vars")
}
```

### Terratest Drawbacks for Your Project

1. **Learning curve:** Requires Go proficiency
2. **Maintenance overhead:** More code than bash/ct
3. **Slower execution:** Go compilation + test execution
4. **Overkill for current needs:** Your bash tests already validate required scenarios

### Decision Matrix: When to Use Each Tool

| Scenario | Tool | Rationale |
|----------|------|-----------|
| Basic install/upgrade validation | ct | Native Helm integration, automatic version checking |
| Multi-configuration testing | ct | Additional values files feature |
| Migration job verification | helm-unittest | Template-level validation sufficient |
| End-to-end functional testing | Bash | Current implementation works well |
| Complex state validation | Terratest | Only if bash becomes unmaintainable |
| Cross-chart dependency testing | Terratest | Programmatic control beneficial |
| Performance/load testing | Bash + K6/Vegeta | Specialized tools better suited |

## Recommended Hybrid Approach

### Phase 1: Fix Current Bash Tests (Immediate)

```bash
# tests/integration/cleanup-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: test-cleanup
spec:
  template:
    spec:
      containers:
      - name: kubectl
        image: bitnami/kubectl:1.31.0  # Change this
        command: ['/bin/bash']  # Now works
        args:
        - -c
        - |
          set -euo pipefail
          kubectl delete namespace spicedb-test --ignore-not-found=true
          kubectl wait --for=delete namespace/spicedb-test --timeout=120s
      restartPolicy: OnFailure
```

### Phase 2: Add ct for Enhanced Validation

```yaml
# .github/workflows/ci.yaml (add to existing)
  integration-test:
    needs: [lint, unittest]
    runs-on: ubuntu-latest
    strategy:
      matrix:
        kubernetes-version:
          - v1.28.0
          - v1.29.0
          - v1.30.0
          - v1.31.0
        test-values:
          - production-postgres
          - production-cockroachdb
          - ha-configuration
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: helm/chart-testing-action@v2.6.1

      - uses: helm/kind-action@v1.9.0
        with:
          node_image: kindest/node:${{ matrix.kubernetes-version }}

      - name: Install dependencies
        run: |
          helm repo add bitnami https://charts.bitnami.com/bitnami
          
          # Install PostgreSQL for postgres tests
          if [[ "${{ matrix.test-values }}" == *"postgres"* ]]; then
            helm install postgresql bitnami/postgresql \
              --set auth.password=spicedb \
              --wait --timeout 3m
          fi
          
          # Install CockroachDB for cockroachdb tests
          if [[ "${{ matrix.test-values }}" == *"cockroachdb"* ]]; then
            helm install cockroachdb bitnami/cockroachdb \
              --wait --timeout 5m
          fi

      - name: Run ct install
        run: |
          ct install \
            --charts charts/spicedb \
            --helm-extra-set-args "-f tests/values/${{ matrix.test-values }}.yaml"

      - name: Run custom bash tests
        run: |
          ./tests/integration/verify-deployment.sh
          ./tests/integration/verify-persistence.sh
```

### Phase 3: Maintain Bash for Functional Validation

```bash
# tests/integration/Makefile
.PHONY: test-integration
test-integration: setup-kind install-deps deploy-spicedb verify-deployment verify-migrations verify-persistence cleanup

setup-kind:
	@command -v kind >/dev/null 2>&1 || { echo "Installing kind..."; go install sigs.k8s.io/kind@latest; }
	@kind get clusters | grep -q spicedb-test || kind create cluster --name spicedb-test --config kind-config.yaml

install-deps:
	helm repo add bitnami https://charts.bitnami.com/bitnami --force-update
	helm upgrade --install postgresql bitnami/postgresql \
		--namespace spicedb-test --create-namespace \
		--set auth.password=spicedb \
		--wait --timeout 3m

deploy-spicedb:
	helm upgrade --install spicedb ../../charts/spicedb \
		--namespace spicedb-test \
		--set datastore.engine=postgres \
		--set datastore.uri="postgresql://postgres:spicedb@postgresql:5432/spicedb" \
		--wait --timeout 5m

verify-deployment:
	./verify-deployment.sh

verify-migrations:
	./verify-migrations.sh

verify-persistence:
	./verify-persistence.sh

cleanup:
	kind delete cluster --name spicedb-test
```

## GitHub Actions Best Practices

### Structured Test Reporting

```yaml
# .github/workflows/ci.yaml
- name: Run integration tests
  run: make test-integration
  
- name: Upload test results
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: integration-test-logs
    path: |
      tests/integration/logs/
      tests/integration/results.xml

- name: Publish test results
  uses: EnricoMi/publish-unit-test-result-action@v2
  if: always()
  with:
    files: tests/integration/results.xml
```

### Convert Bash Tests to TAP/JUnit Output

```bash
# tests/integration/verify-deployment.sh
#!/bin/bash
set -euo pipefail

# TAP output for GitHub Actions parsing
TAP_OUTPUT="${TAP_OUTPUT:-results.tap}"
exec > >(tee "${TAP_OUTPUT}")

echo "TAP version 13"
echo "1..5"

test_num=1

# Test 1: PostgreSQL ready
if kubectl wait --for=condition=ready pod -l app=postgresql -n spicedb-test --timeout=120s >/dev/null 2>&1; then
    echo "ok ${test_num} - PostgreSQL pod ready"
else
    echo "not ok ${test_num} - PostgreSQL pod ready"
    kubectl describe pod -l app=postgresql -n spicedb-test
fi
((test_num++))

# Test 2: SpiceDB deployment ready
if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=spicedb -n spicedb-test --timeout=180s >/dev/null 2>&1; then
    echo "ok ${test_num} - SpiceDB deployment ready"
else
    echo "not ok ${test_num} - SpiceDB deployment ready"
    kubectl describe deployment -l app.kubernetes.io/name=spicedb -n spicedb-test
fi
((test_num++))

# ... more tests
```

### Parallel Test Execution

```yaml
jobs:
  integration-matrix:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        scenario:
          - name: postgres-basic
            datastore: postgres
            values: production-postgres.yaml
          - name: postgres-ha
            datastore: postgres
            values: ha-configuration.yaml
          - name: cockroachdb-basic
            datastore: cockroachdb
            values: production-cockroachdb.yaml
          - name: memory-mode
            datastore: memory
            values: memory-mode.yaml
    steps:
      - name: Run ${{ matrix.scenario.name }} test
        run: |
          make test-integration \
            DATASTORE=${{ matrix.scenario.datastore }} \
            VALUES_FILE=tests/values/${{ matrix.scenario.values }}
```

## Advanced Integration Testing Patterns

### 1. Migration Safety Testing

```bash
# tests/integration/verify-migration-safety.sh
#!/bin/bash
set -euo pipefail

NAMESPACE="spicedb-test"

# Install v1.34.0
helm install spicedb ./charts/spicedb \
  --namespace ${NAMESPACE} \
  --set image.tag=v1.34.0 \
  --wait

# Load test data
kubectl exec -n ${NAMESPACE} deployment/spicedb -- \
  spicedb schema write --schema-definition-file=/test-schema.zed

# Record migration job count before upgrade
BEFORE_COUNT=$(kubectl get jobs -n ${NAMESPACE} -l app.kubernetes.io/component=migration --no-headers | wc -l)

# Upgrade to v1.35.0
helm upgrade spicedb ./charts/spicedb \
  --namespace ${NAMESPACE} \
  --set image.tag=v1.35.0 \
  --wait

# Verify new migration job ran
AFTER_COUNT=$(kubectl get jobs -n ${NAMESPACE} -l app.kubernetes.io/component=migration --no-headers | wc -l)
if [ ${AFTER_COUNT} -le ${BEFORE_COUNT} ]; then
    echo "FAIL: Migration job did not run during upgrade"
    exit 1
fi

# Verify data still accessible
kubectl exec -n ${NAMESPACE} deployment/spicedb -- \
  spicedb schema read | grep "definition user"
```

### 2. TLS Certificate Validation

```bash
# tests/integration/verify-tls.sh
#!/bin/bash
set -euo pipefail

NAMESPACE="spicedb-test"

# Generate test certificates
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=spicedb.local"

# Create TLS secret
kubectl create secret tls spicedb-tls \
  --namespace ${NAMESPACE} \
  --cert=tls.crt --key=tls.key

# Install with TLS enabled
helm install spicedb ./charts/spicedb \
  --namespace ${NAMESPACE} \
  --set tls.grpc.enabled=true \
  --set tls.grpc.secretName=spicedb-tls \
  --wait

# Verify TLS configuration
POD=$(kubectl get pod -n ${NAMESPACE} -l app.kubernetes.io/name=spicedb -o jsonpath='{.items[0].metadata.name}')

# Check TLS environment variables
kubectl exec -n ${NAMESPACE} ${POD} -- env | grep SPICEDB_GRPC_TLS_CERT_PATH

# Verify certificate mounted
kubectl exec -n ${NAMESPACE} ${POD} -- ls -la /etc/spicedb/tls/
```

### 3. High Availability Validation

```bash
# tests/integration/verify-ha.sh
#!/bin/bash
set -euo pipefail

NAMESPACE="spicedb-test"

# Install with HA configuration
helm install spicedb ./charts/spicedb \
  --namespace ${NAMESPACE} \
  --values tests/values/ha-configuration.yaml \
  --wait

# Verify 3 replicas running
READY_REPLICAS=$(kubectl get deployment -n ${NAMESPACE} spicedb -o jsonpath='{.status.readyReplicas}')
if [ "${READY_REPLICAS}" != "3" ]; then
    echo "FAIL: Expected 3 ready replicas, got ${READY_REPLICAS}"
    exit 1
fi

# Verify PodDisruptionBudget exists
kubectl get pdb -n ${NAMESPACE} spicedb

# Verify anti-affinity scheduling
kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=spicedb -o wide | \
  awk 'NR>1 {print $7}' | sort | uniq -c | \
  awk '{if($1>1) {print "WARN: Multiple pods on same node: "$2; warned=1}} END{if(warned) exit 1}'

# Test rolling update
kubectl rollout restart deployment/spicedb -n ${NAMESPACE}
kubectl rollout status deployment/spicedb -n ${NAMESPACE} --timeout=5m

# Verify no downtime (requires background process checking health)
```

## Tooling Comparison Summary

| Feature | Bash | ct | Terratest | helm-unittest |
|---------|------|-----|-----------|---------------|
| **Setup complexity** | Low | Low | Medium | Low |
| **Learning curve** | Low | Low | High | Low |
| **Template validation** | Manual | Yes | Yes | Yes |
| **Install testing** | Yes | Yes | Yes | No |
| **Upgrade testing** | Manual | Yes | Yes | No |
| **Functional testing** | Yes | Limited | Yes | No |
| **CI/CD integration** | Manual | Excellent | Good | Excellent |
| **Test reporting** | Manual | TAP/JUnit | Go test | TAP |
| **Parallel execution** | Manual | Limited | Yes | N/A |
| **Maintenance burden** | Low | Very Low | Medium | Very Low |
| **Best for** | Functional tests | Install/upgrade validation | Complex scenarios | Template unit tests |

## Final Recommendation

**Recommended Stack for SpiceDB Chart:**

1. **helm-unittest** (already in use): Template-level unit tests
2. **chart-testing (ct)**: Install/upgrade validation across multiple configurations
3. **Bash scripts**: Functional end-to-end tests (current implementation)
4. **Skip Terratest**: Unnecessary complexity for current requirements

**Implementation Priority:**

1. **Immediate (This Week):**
   - Fix kubectl image to `bitnami/kubectl:1.31.0`
   - Add ct configuration file
   - Update GitHub Actions to use ct for install tests

2. **Short-term (Next Sprint):**
   - Convert bash test output to TAP format
   - Add test result publishing to GitHub Actions
   - Create test value files for all production scenarios

3. **Long-term (Future Consideration):**
   - Evaluate Terratest only if you add complex multi-chart orchestration
   - Consider Terratest if you need programmatic chaos testing
   - Revisit if bash tests exceed 500 lines or become unmaintainable

This hybrid approach leverages each tool's strengths while avoiding unnecessary complexity, maintaining your already successful testing implementation from Task 11.


---

*Generated by Task Master Research Command*  
*Timestamp: 2025-11-08T19:01:24.358Z*
