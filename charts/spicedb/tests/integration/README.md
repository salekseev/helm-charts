# SpiceDB Helm Chart - Integration Tests

Comprehensive end-to-end integration tests for the SpiceDB Helm chart. These tests deploy SpiceDB to a Kind Kubernetes cluster with PostgreSQL, validate migrations during helm upgrades, verify data persistence, and test cleanup hooks.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Test Coverage](#test-coverage)
- [Architecture](#architecture)
- [Local Testing](#local-testing)
- [CI/CD Integration](#cicd-integration)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)

## Prerequisites

Before running the integration tests, ensure you have the following tools installed:

### Required Tools

| Tool | Minimum Version | Installation |
|------|----------------|--------------|
| **Kind** | v0.20.0+ | `brew install kind` (macOS) or [kind.sigs.k8s.io](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) |
| **kubectl** | v1.28.0+ | `brew install kubectl` (macOS) or [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| **Helm** | v3.12.0+ | `brew install helm` (macOS) or [helm.sh/docs/intro/install](https://helm.sh/docs/intro/install/) |
| **Docker** | v20.10+ | [docker.com/get-started](https://www.docker.com/get-started) |

### Optional Tools

- **act**: For local GitHub Actions testing - `brew install act`
- **zed CLI**: For manual SpiceDB testing - Available from [authzed/zed releases](https://github.com/authzed/zed/releases)

### System Requirements

- **CPU**: 4+ cores recommended
- **Memory**: 8GB+ RAM
- **Disk**: 10GB free space
- **OS**: Linux, macOS, or Windows (WSL2)

## Quick Start

Run the full integration test suite:

```bash
# From chart directory
cd charts/spicedb
make test-integration

# Or from repository root
make spicedb-test-integration
```

Or run tests individually:

```bash
# From chart directory
cd charts/spicedb

# Migration and upgrade tests
./tests/integration/migration-test.sh

# Self-healing features E2E tests
./tests/integration/self-healing-test.sh

# Run specific self-healing test
TEST_FILTER=liveness ./tests/integration/self-healing-test.sh
```

Expected output:

```
[====] SpiceDB Integration Test Suite [====]
[INFO] Cluster: spicedb-test
[INFO] Namespace: spicedb-test
[INFO] Release: spicedb

[====] Setting up Kind cluster [====]
[INFO] Creating Kind cluster: spicedb-test
...
[INFO] ✓ Kind cluster ready

[====] Deploying PostgreSQL [====]
[INFO] ✓ PostgreSQL is ready and accepting connections

[====] Installing SpiceDB chart [====]
[INFO] ✓ SpiceDB chart installed successfully

[====] Loading test schema and data [====]
[INFO] ✓ Test data loaded successfully

[====] Performing Helm upgrade [====]
[INFO] ✓ Helm upgrade completed successfully

[====] Verifying data persistence [====]
[INFO] ✓ Data persistence verified

[====] Verifying migration job cleanup [====]
[INFO] ✓ Migration job cleanup verified

[====] Testing idempotent upgrades [====]
[INFO] ✓ Idempotent upgrade successful

[====] Test Summary [====]
[INFO] ✓ All tests passed successfully!
```

## Test Coverage

The integration test suite validates:

### 1. Infrastructure Setup

- ✅ Kind cluster creation and configuration
- ✅ PostgreSQL StatefulSet deployment (official postgres:16 image)
- ✅ PersistentVolumeClaim provisioning and binding
- ✅ Service connectivity and DNS resolution

### 2. Chart Installation

- ✅ Helm chart installation with PostgreSQL datastore
- ✅ Migration job execution (pre-install hook)
- ✅ SpiceDB pod deployment and readiness
- ✅ Schema and relationship data loading

### 3. Upgrade Testing

- ✅ Helm upgrade with modified values (version bump, replica changes)
- ✅ Pre-upgrade migration hook execution
- ✅ Rolling update of SpiceDB pods
- ✅ Data persistence across upgrades

### 4. Data Persistence

- ✅ Schema persistence (definition preservation)
- ✅ Relationship persistence (permission data retention)
- ✅ Permission checks before and after upgrade
- ✅ Data integrity verification

### 5. Migration Job Cleanup

- ✅ Hook-delete-policy annotation validation
- ✅ Old migration job removal
- ✅ No orphaned pods or jobs
- ✅ Proper cleanup timing (before-hook-creation)

### 6. Idempotency

- ✅ Multiple upgrades with same values
- ✅ Migration job re-execution
- ✅ No data corruption or drift
- ✅ Consistent schema state

### 7. Self-Healing Features (E2E)

- ✅ Liveness probe automatic pod restart on failure
- ✅ Readiness probe endpoint removal for unready pods
- ✅ Startup probe protection during slow initialization
- ✅ Resource limits enforcement and OOM handling
- ✅ Graceful shutdown on SIGTERM signal
- ✅ Pod anti-affinity distribution across nodes
- ✅ Topology spread constraints across zones
- ✅ PodDisruptionBudget enforcement during disruptions

## Architecture

### Test Components

```
tests/integration/
├── postgres-deployment.yaml    # PostgreSQL StatefulSet, Service, Secret, PVC
├── test-schema.zed            # Sample SpiceDB schema (user, document)
├── verify-persistence.sh      # Data persistence verification script
├── verify-cleanup.sh          # Migration job cleanup validation script
├── migration-test.sh          # Main orchestration script (upgrades & data)
├── self-healing-test.sh       # Self-healing features E2E test suite
├── kind-cluster-config.yaml   # Multi-node Kind cluster configuration
└── README.md                  # This file
```

### Test Flow Diagram

```
┌─────────────────────┐
│  Setup Kind Cluster │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│  Deploy PostgreSQL  │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│ Install SpiceDB     │
│ Chart (v1.35.3)     │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│ Load Test Schema    │
│ & Relationships     │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│ Verify Initial      │
│ Permission Checks   │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│ Capture Pre-upgrade │
│ Migration Job State │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│ Helm Upgrade        │
│ (v1.36.0, 2 pods)   │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│ Verify Data         │
│ Persistence         │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│ Verify Migration    │
│ Job Cleanup         │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│ Test Idempotent     │
│ Upgrade (same vals) │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│ Final Verification  │
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│ Cleanup Kind        │
│ Cluster             │
└─────────────────────┘
```

## Local Testing

### Running Specific Test Phases

The test suite supports individual phase execution for debugging:

```bash
# From chart directory (cd charts/spicedb)

# Run only unit tests (fast)
make test-unit

# Run only integration tests
make test-integration

# Run all tests
make test-all

# Run with custom cluster name
KIND_CLUSTER_NAME=my-test make test-integration

# Skip cleanup (for debugging)
SKIP_CLEANUP=true ./tests/integration/migration-test.sh
```

### Manual Testing Steps

For manual testing or debugging:

```bash
# 1. Create Kind cluster
kind create cluster --name spicedb-test

# 2. Deploy PostgreSQL
kubectl apply -f tests/integration/postgres-deployment.yaml
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgres -n spicedb-test --timeout=5m

# 3. Install SpiceDB chart
helm install spicedb . \
  --namespace spicedb-test \
  --set config.datastoreEngine=postgres \
  --set config.datastore.hostname=postgres.spicedb-test.svc.cluster.local \
  --set config.datastore.password=testpassword123 \
  --set config.presharedKey="insecure-default-key-change-in-production"

# 4. Verify installation
kubectl get pods -n spicedb-test
kubectl get jobs -n spicedb-test

# 5. Load test data
cd tests/integration
./verify-persistence.sh initial

# 6. Perform upgrade
cd ../..
helm upgrade spicedb . \
  --namespace spicedb-test \
  --set image.tag=v1.36.0 \
  --set replicaCount=2

# 7. Verify persistence
cd tests/integration
./verify-persistence.sh verify

# 8. Verify cleanup
./verify-cleanup.sh verify

# 9. Cleanup
kind delete cluster --name spicedb-test
```

### Testing with `act` (GitHub Actions Locally)

Run CI pipeline locally:

```bash
# Install act
brew install act

# Run integration tests locally (will be skipped due to conditional)
act -j integration-test

# Run unit tests with act
act -j unittest
```

**Note**: Integration tests are automatically skipped when using `act` due to resource constraints. Use `make test-integration` for local integration testing instead.

## Self-Healing Test Suite

The `self-healing-test.sh` script provides comprehensive E2E testing for Kubernetes self-healing capabilities.

### Running Self-Healing Tests

```bash
# Run all self-healing tests
./tests/integration/self-healing-test.sh

# Run with debug output (keep cluster on failure)
SKIP_CLEANUP=true ./tests/integration/self-healing-test.sh

# Run specific test only
TEST_FILTER=liveness ./tests/integration/self-healing-test.sh
TEST_FILTER=readiness ./tests/integration/self-healing-test.sh
TEST_FILTER=startup ./tests/integration/self-healing-test.sh
TEST_FILTER=oom ./tests/integration/self-healing-test.sh
TEST_FILTER=shutdown ./tests/integration/self-healing-test.sh
TEST_FILTER=affinity ./tests/integration/self-healing-test.sh
TEST_FILTER=topology ./tests/integration/self-healing-test.sh
TEST_FILTER=pdb ./tests/integration/self-healing-test.sh
```

### Self-Healing Test Details

#### Test 1: Liveness Probe Restart

- **Purpose**: Verify unhealthy pods are automatically restarted
- **Method**: Kills SpiceDB process (PID 1) inside container
- **Success**: Pod restart count increments and pod returns to Ready state
- **Timeout**: 90 seconds for restart detection

#### Test 2: Readiness Probe Endpoint Removal

- **Purpose**: Verify unready pods are removed from Service endpoints
- **Method**: Simulates readiness failure by blocking health check
- **Success**: Pod IP removed from Service endpoints, moved to notReadyAddresses
- **Timeout**: 60 seconds for endpoint removal

#### Test 3: Startup Probe Slow Initialization

- **Purpose**: Verify startup probe prevents premature liveness probe kills
- **Method**: Creates pod with 20s startup delay
- **Success**: Pod not restarted during startup window (no restarts before 25s)
- **Timeout**: 60 seconds total test time

#### Test 4: Resource Limits and OOM

- **Purpose**: Verify memory limits are enforced and OOMKilled pods restart
- **Method**: Creates pod with 128Mi limit, attempts to allocate 200Mi
- **Success**: Container OOMKilled event detected, pod restarts automatically
- **Timeout**: 60 seconds for OOM detection

#### Test 5: Graceful Shutdown

- **Purpose**: Verify SIGTERM triggers graceful shutdown within grace period
- **Method**: Deletes pod, monitors shutdown time
- **Success**: Pod terminates within configured terminationGracePeriodSeconds
- **Grace Period**: 30 seconds (configurable in chart)

#### Test 6: Anti-Affinity Distribution

- **Purpose**: Verify pods spread across multiple nodes
- **Method**: Checks pod-to-node mapping for 3 replicas
- **Success**: Pods distributed across 2+ nodes (preferredDuringScheduling)
- **Note**: Non-blocking if cluster has insufficient nodes

#### Test 7: Topology Spread Constraints

- **Purpose**: Verify pods spread across topology zones
- **Method**: Labels nodes with zone labels, checks pod distribution
- **Success**: Pods distributed across 2+ zones
- **Note**: Non-blocking in test clusters without zone diversity

#### Test 8: PodDisruptionBudget Enforcement

- **Purpose**: Verify PDB prevents excessive pod eviction
- **Method**: Attempts node drain, monitors PDB status
- **Success**: PDB maintains desiredHealthy pods during disruption
- **Timeout**: 30 seconds for drain attempt

### Expected Output

```
[====] SpiceDB Self-Healing Features E2E Test Suite [====]
[INFO] Cluster: spicedb-selfhealing-test
[INFO] Namespace: spicedb-test
[INFO] Release: spicedb

[====] Test 1: Liveness Probe Automatic Restart [====]
[INFO] Killing SpiceDB process inside pod...
[INFO] Pod restarted! New restart count: 1
[PASS] Liveness probe successfully restarted unhealthy pod

[====] Test 2: Readiness Probe Endpoint Removal [====]
[INFO] Pod successfully removed from service endpoints
[PASS] Pod moved to notReadyAddresses as expected

[====] Test 3: Startup Probe Slow Initialization Protection [====]
[PASS] Startup probe successfully protected slow initialization

[====] Test 4: Resource Limits and OOM Prevention [====]
[PASS] Resource limits enforced - pod OOMKilled and restarted

[====] Test 5: Graceful Shutdown on SIGTERM [====]
[PASS] Graceful shutdown completed within grace period

[====] Test 6: Pod Anti-Affinity Distribution [====]
[PASS] Anti-affinity working - pods distributed across 3 nodes

[====] Test 7: Topology Spread Constraints [====]
[PASS] Topology spread working - pods distributed across 3 zones

[====] Test 8: PodDisruptionBudget Enforcement [====]
[PASS] PodDisruptionBudget successfully prevented excessive disruption

[====] Test Summary [====]
[INFO] Tests run: 8
[INFO] Tests passed: 8
[INFO] Tests failed: 0
[PASS] All self-healing tests passed successfully!
```

### Troubleshooting Self-Healing Tests

#### Liveness Test Failures

- **Issue**: Pod not restarting after process kill
- **Check**: `kubectl describe pod` for liveness probe configuration
- **Verify**: Probe settings match chart values (periodSeconds, failureThreshold)

#### Readiness Test Failures

- **Issue**: Pod not removed from endpoints
- **Check**: `kubectl get endpoints` to see current state
- **Verify**: Readiness probe configured correctly in deployment

#### Startup Test Failures

- **Issue**: Pod restarted during initialization
- **Check**: Startup probe failureThreshold * periodSeconds > initialization time
- **Adjust**: Increase `probes.startup.failureThreshold` in values

#### OOM Test Timeouts

- **Issue**: No OOM detected in test window
- **Note**: This may be expected if stress test doesn't trigger OOM
- **Verify**: Resource limits are configured in deployment spec

#### PDB Test Skipped

- **Issue**: Tests skip PDB validation
- **Check**: Ensure PDB is enabled (`podDisruptionBudget.enabled=true`)
- **Verify**: `kubectl get pdb` shows PodDisruptionBudget exists

## CI/CD Integration

### GitHub Actions Workflow

The integration tests run automatically in GitHub Actions on every push and pull request.

**Workflow configuration**: `.github/workflows/ci.yaml`

**Matrix strategy**: Tests run against Kubernetes versions:

- v1.28.0
- v1.29.0
- v1.30.0

**Triggers**:

- Push to `main` or `master` branches
- Pull requests targeting `main` or `master`

**Artifacts**: Logs are uploaded as artifacts on failure (retention: 7 days)

### Viewing Test Results

1. Navigate to repository **Actions** tab
2. Select workflow run
3. Check **Integration Tests** job
4. Expand test output or download logs artifact

### Skipping Integration Tests

Add `[skip ci]` or `[ci skip]` to commit message:

```bash
git commit -m "docs: update README [skip ci]"
```

## Troubleshooting

### Common Issues and Solutions

#### 1. Port Conflicts

**Symptom**: `Error: port 50051 already in use`

**Solution**:

```bash
# Find process using port
lsof -ti:50051 | xargs kill -9

# Or use different port mapping in Kind config
# Edit migration-test.sh and change extraPortMappings
```

#### 2. Resource Limits

**Symptom**: Pods stuck in `Pending` state, events show insufficient CPU/memory

**Solution**:

```bash
# Increase Docker Desktop resources:
# - Docker Desktop → Preferences → Resources
# - Set CPUs: 4+, Memory: 8GB+

# Or reduce chart resource requests:
helm install spicedb charts/spicedb \
  --set resources.requests.cpu=100m \
  --set resources.requests.memory=256Mi
```

#### 3. Image Pull Failures

**Symptom**: `ImagePullBackOff` or `ErrImagePull`

**Solution**:

```bash
# Pre-load images into Kind cluster
docker pull postgres:16
docker pull authzed/spicedb:v1.35.3
docker pull authzed/zed:latest

kind load docker-image postgres:16 --name spicedb-test
kind load docker-image authzed/spicedb:v1.35.3 --name spicedb-test
kind load docker-image authzed/zed:latest --name spicedb-test
```

#### 4. Migration Job Timeout

**Symptom**: `error: timed out waiting for the condition on jobs/spicedb-migration`

**Solution**:

```bash
# Check migration job logs
kubectl logs -n spicedb-test -l app.kubernetes.io/component=migration

# Common causes:
# - Database connection issues (check PostgreSQL readiness)
# - Slow database initialization (increase timeout in migration-test.sh)
# - Resource constraints (increase job resource limits)
```

#### 5. Permission Check Failures

**Symptom**: `verify-persistence.sh` reports permission check failures

**Solution**:

```bash
# Verify SpiceDB is healthy
kubectl get pods -n spicedb-test
kubectl logs -n spicedb-test -l app.kubernetes.io/name=spicedb

# Check schema was loaded correctly
kubectl run -n spicedb-test zed-debug --rm -i --restart=Never \
  --image=authzed/zed:latest -- \
  zed schema read --endpoint spicedb-spicedb:50051 --insecure \
  --token insecure-default-key-change-in-production
```

#### 6. Cleanup Verification Failures

**Symptom**: `verify-cleanup.sh` reports multiple migration jobs remaining

**Solution**:

```bash
# This may be normal behavior during cleanup grace period
# Wait 30-60 seconds and re-check
sleep 60
./verify-cleanup.sh verify

# If jobs persist, check hook annotations
kubectl get jobs -n spicedb-test -o yaml | grep -A2 "helm.sh/hook"

# Manually delete stuck jobs
kubectl delete jobs -n spicedb-test -l app.kubernetes.io/component=migration
```

#### 7. Kind Cluster Creation Failures

**Symptom**: `ERROR: failed to create cluster`

**Solution**:

```bash
# Cleanup stale clusters
kind delete cluster --name spicedb-test

# Check Docker is running
docker ps

# Ensure sufficient disk space
df -h

# Try with verbose logging
kind create cluster --name spicedb-test -v 5
```

#### 8. Test Hangs Indefinitely

**Symptom**: Tests appear stuck without progress

**Solution**:

```bash
# Set shorter timeout
timeout 600 ./migration-test.sh

# Check for pending pods
kubectl get pods --all-namespaces | grep Pending

# Review events for errors
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Force cleanup and retry
kind delete cluster --name spicedb-test
```

## Advanced Usage

### Custom Test Scenarios

Modify `test-schema.zed` to test custom permission models:

```zed
definition organization {}

definition project {
    relation org: organization
    relation admin: user
    relation member: user

    permission manage = admin
    permission view = member + admin
}
```

### Performance Testing

Add performance metrics collection:

```bash
# Time each test phase
export TIME_FORMAT="[%Es elapsed]"
time ./migration-test.sh
```

### Multi-Cluster Testing

Test across different Kubernetes versions:

```bash
for version in v1.28.0 v1.29.0 v1.30.0; do
  export KIND_CLUSTER_NAME="spicedb-test-${version}"
  kind create cluster --name "$KIND_CLUSTER_NAME" \
    --image "kindest/node:${version}"
  ./migration-test.sh
  kind delete cluster --name "$KIND_CLUSTER_NAME"
done
```

### Debugging Failed Tests

Enable verbose logging:

```bash
# Enable bash tracing
bash -x ./migration-test.sh

# Keep cluster on failure
SKIP_CLEANUP=true ./migration-test.sh

# Access cluster after test failure
export KUBECONFIG=$(kind get kubeconfig --name=spicedb-test)
kubectl get all -n spicedb-test
```

## Contributing

When adding new integration tests:

1. Update `migration-test.sh` with new test phases
2. Add corresponding verification scripts
3. Update this README with new test coverage
4. Ensure tests pass locally before submitting PR
5. Add test output examples to troubleshooting section

## License

This integration test suite is part of the SpiceDB Helm chart and follows the same Apache 2.0 license.

## Support

- **Issues**: [GitHub Issues](https://github.com/salekseev/helm-charts/issues)
- **Discussions**: [GitHub Discussions](https://github.com/salekseev/helm-charts/discussions)
- **SpiceDB Docs**: [authzed.com/docs](https://authzed.com/docs)
