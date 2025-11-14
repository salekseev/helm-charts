# SpiceDB Operator-to-Helm Migration Tests

Comprehensive integration test suite for validating SpiceDB operator-to-helm migration scenarios. These tests verify configuration conversion, data persistence, secret migration, and rollback procedures.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Test Coverage](#test-coverage)
- [Test Suite Components](#test-suite-components)
- [Running Tests](#running-tests)
- [Test Scenarios](#test-scenarios)
- [Helper Scripts](#helper-scripts)
- [Troubleshooting](#troubleshooting)
- [CI/CD Integration](#cicd-integration)

## Overview

This test suite validates the complete operator-to-helm migration workflow:

1. **Configuration Conversion**: Verify SpiceDBCluster CR → Helm values.yaml conversion
2. **Basic Migration**: Deploy via operator, migrate to Helm, verify functionality
3. **Secret Migration**: Extract and reuse operator secrets in Helm deployment
4. **Rollback**: Simulate failures and verify rollback to operator works

**Estimated Test Duration**: 15-20 minutes for full suite

## Prerequisites

### Required Tools

| Tool | Minimum Version | Installation |
|------|----------------|--------------|
| **kind** | v0.20.0+ | `brew install kind` or [kind.sigs.k8s.io](https://kind.sigs.k8s.io/) |
| **kubectl** | v1.28.0+ | `brew install kubectl` |
| **Helm** | v3.12.0+ | `brew install helm` |
| **Docker** | v20.10+ | [docker.com/get-started](https://www.docker.com/get-started) |
| **jq** | v1.6+ | `brew install jq` |

### Optional Tools

| Tool | Purpose | Installation |
|------|---------|--------------|
| **zed CLI** | Data integrity testing | [authzed/zed releases](https://github.com/authzed/zed/releases) |
| **grpcurl** | gRPC endpoint testing | `brew install grpcurl` |
| **yq** | YAML processing | `brew install yq` |

### System Requirements

- **CPU**: 4+ cores recommended
- **Memory**: 8GB+ RAM
- **Disk**: 10GB free space
- **OS**: Linux, macOS, or Windows (WSL2)

## Quick Start

Run the complete test suite:

```bash
# 1. Set up test infrastructure
./setup-cluster.sh

# 2. Run all migration tests
./run-all-tests.sh

# 3. Clean up when done
./cleanup-cluster.sh
```

Or run individual tests:

```bash
# Set up infrastructure once
./setup-cluster.sh

# Run individual tests
./test-config-conversion.sh      # Configuration conversion only
./test-basic-migration.sh        # Full migration workflow
./test-secret-migration.sh       # Secret handling
./test-rollback.sh               # Rollback procedure

# Clean up
./cleanup-cluster.sh
```

## Test Coverage

### 1. Configuration Conversion Tests

**File**: `test-config-conversion.sh`

- SpiceDBCluster CR → Helm values.yaml conversion
- Complex configuration mapping (TLS, dispatch, resources)
- Helm template rendering validation
- Values schema validation

**Tested Conversions**:

- ✅ Replica count
- ✅ SpiceDB version
- ✅ Datastore engine (postgres, memory, cockroachdb)
- ✅ Secret references
- ✅ TLS configuration
- ✅ Dispatch cluster settings
- ✅ Resource requests/limits
- ✅ Extra arguments

### 2. Basic Migration Tests

**File**: `test-basic-migration.sh`

- Deploy SpiceDB via operator
- Export operator configuration
- Convert CR to Helm values
- Scale operator to 0 replicas
- Install via Helm chart
- Verify service continuity
- Delete SpiceDBCluster CR
- Verify migration complete

**Validated**:

- ✅ Operator deployment succeeds
- ✅ Configuration export works
- ✅ Conversion produces valid Helm values
- ✅ Downtime window is minimal (< 60s)
- ✅ Helm deployment uses same secrets
- ✅ Service endpoints match
- ✅ No data loss occurs
- ✅ Operator CR can be safely deleted

### 3. Secret Migration Tests

**File**: `test-secret-migration.sh`

- Extract operator secrets (preshared-key, datastore-uri)
- Verify secret format compatibility
- Install Helm with `existingSecret` reference
- Validate authentication works post-migration

**Secret Formats Tested**:

- ✅ Operator `preshared-key` format
- ✅ Operator `datastore-uri` format
- ✅ Helm `existingSecret` reference
- ✅ PostgreSQL connection strings
- ✅ Memory datastore configuration

### 4. Rollback Tests

**File**: `test-rollback.sh`

- Perform complete migration to Helm
- Simulate migration failure scenario
- Scale Helm deployment to 0
- Restore operator control
- Verify data persistence
- Validate service restoration

**Rollback Scenarios**:

- ✅ Helm installation failures
- ✅ Configuration errors discovered post-migration
- ✅ Resource scaling issues
- ✅ Restore operator without data loss

## Test Suite Components

### Directory Structure

```text
tests/integration/migration/operator-to-helm/
├── common/
│   ├── validation-checks.sh          # Reusable validation functions
│   └── convert-cr-to-values.sh       # CR → Helm values conversion script
├── fixtures/
│   ├── minimal-cluster.yaml          # Minimal SpiceDBCluster CR
│   ├── complex-cluster.yaml          # Complex CR (TLS, dispatch, HA)
│   └── test-secrets.yaml             # Test secrets for migration
├── kind-config.yaml                  # Kind cluster configuration
├── setup-cluster.sh                  # Infrastructure setup script
├── cleanup-cluster.sh                # Cleanup script
├── test-basic-migration.sh           # Basic migration test
├── test-config-conversion.sh         # Configuration conversion test
├── test-secret-migration.sh          # Secret migration test
├── test-rollback.sh                  # Rollback procedure test
├── run-all-tests.sh                  # Test orchestration script
└── README.md                         # This file
```

### Test Fixtures

#### minimal-cluster.yaml

Simple SpiceDBCluster for basic migration testing:

- 1 replica
- Memory datastore
- Minimal resources

#### complex-cluster.yaml

Complex SpiceDBCluster for comprehensive testing:

- 3 replicas (HA setup)
- PostgreSQL datastore
- TLS enabled (gRPC, HTTP)
- Dispatch cluster enabled
- Production resource limits

#### test-secrets.yaml

Pre-configured secrets for testing:

- `spicedb-operator-config` - Operator configuration secret
- `postgres-uri` - PostgreSQL connection secret
- `spicedb-grpc-tls` - TLS certificates (self-signed for testing)
- `spicedb-dispatch-tls` - Dispatch TLS certificates

## Running Tests

### Full Test Suite

```bash
# Complete workflow
./setup-cluster.sh        # ~5 minutes
./run-all-tests.sh        # ~15 minutes
./cleanup-cluster.sh      # ~1 minute
```

**Expected Output**:

```text
[====] Operator-to-Helm Migration Test Suite [====]

[RUNNER] Running all migration tests...

[====] Running Test: Configuration Conversion [====]
[TEST] All configuration conversion tests passed!
[RUNNER] Test PASSED: Configuration Conversion

[====] Running Test: Basic Migration [====]
[TEST] All tests passed!
[RUNNER] Test PASSED: Basic Migration

[====] Running Test: Secret Migration [====]
[TEST] All secret migration tests passed!
[RUNNER] Test PASSED: Secret Migration

[====] Running Test: Rollback Procedure [====]
[TEST] All rollback tests passed!
[RUNNER] Test PASSED: Rollback Procedure

[====] Test Suite Summary [====]

[RUNNER] Total tests:  4
[RUNNER] Passed:       4
[RUNNER] Failed:       0

[====] All Tests Passed! [====]
```

### Individual Tests

#### Configuration Conversion Test

```bash
./test-config-conversion.sh
```

Tests CR → Helm values conversion without requiring a cluster. Fast validation of conversion logic.

#### Basic Migration Test

```bash
# Requires cluster setup
./setup-cluster.sh
./test-basic-migration.sh
```

Full end-to-end migration workflow:

1. Deploy via operator
2. Convert configuration
3. Migrate to Helm
4. Verify services
5. Clean up operator resources

#### Secret Migration Test

```bash
./setup-cluster.sh
./test-secret-migration.sh
```

Tests secret extraction and reuse:

1. Extract operator secrets
2. Verify format compatibility
3. Install Helm with existing secrets
4. Validate authentication

#### Rollback Test

```bash
./setup-cluster.sh
./test-rollback.sh
```

Simulates failure and rollback:

1. Migrate to Helm
2. Simulate failure
3. Rollback to operator
4. Verify recovery

### Environment Variables

Customize test behavior:

```bash
# Cluster name
export KIND_CLUSTER_NAME="my-test-cluster"

# Operator version
export SPICEDB_OPERATOR_VERSION="v1.30.0"

# Skip cleanup (for debugging)
export SKIP_CLEANUP="true"

# Run tests
./setup-cluster.sh
./run-all-tests.sh
```

## Test Scenarios

### Scenario 1: Minimal Migration

**Use Case**: Migrate simple operator deployment to Helm

**Steps**:

```bash
./setup-cluster.sh
./test-basic-migration.sh
```

**Validates**:

- Basic operator → Helm migration
- Service continuity
- Secret reuse
- No data loss

### Scenario 2: Complex Configuration

**Use Case**: Migrate production-like setup with TLS, HA, dispatch

**Steps**:

```bash
./setup-cluster.sh

# Deploy complex cluster manually
kubectl apply -f fixtures/complex-cluster.yaml

# Convert and migrate
./common/convert-cr-to-values.sh spicedb-complex -n spicedb-migration-test -o complex-values.yaml

# Scale operator down
kubectl patch spicedbcluster spicedb-complex -n spicedb-migration-test --type=merge -p '{"spec":{"replicas":0}}'

# Install via Helm
helm install spicedb-complex ../../../../.. -n spicedb-migration-test -f complex-values.yaml
```

**Validates**:

- TLS configuration migration
- Dispatch cluster preservation
- HA replica management
- Resource limit conversion

### Scenario 3: Secret Migration

**Use Case**: Verify existing secrets work with Helm

**Steps**:

```bash
./setup-cluster.sh
./test-secret-migration.sh
```

**Validates**:

- Secret key compatibility
- `existingSecret` reference
- Authentication continuity
- No secret regeneration needed

### Scenario 4: Rollback After Failure

**Use Case**: Recover from failed migration

**Steps**:

```bash
./setup-cluster.sh
./test-rollback.sh
```

**Validates**:

- Helm uninstall works cleanly
- Operator resumes control
- Data persistence maintained
- Service restoration successful

## Helper Scripts

### validation-checks.sh

Reusable validation functions:

```bash
# Source in your tests
source common/validation-checks.sh

# Validate pod health
validate_pod_health "$NAMESPACE" "app.kubernetes.io/name=spicedb"

# Validate endpoints
validate_endpoints "$NAMESPACE" "spicedb" "$TOKEN"

# Validate data integrity
validate_data_integrity "$NAMESPACE" "spicedb" "$TOKEN"

# Validate secrets
validate_secrets "$NAMESPACE" "spicedb-config" "preshared-key" "datastore-uri"

# Validate PDB
validate_pdb "$NAMESPACE" "spicedb"

# Validate service endpoints
validate_service_endpoints "$NAMESPACE" "spicedb"

# Validate migration complete
validate_migration_complete "$NAMESPACE" "old-selector" "new-selector"
```

### convert-cr-to-values.sh

Convert SpiceDBCluster CR to Helm values:

```bash
# From live cluster
./common/convert-cr-to-values.sh spicedb -n production -o prod-values.yaml

# From file
./common/convert-cr-to-values.sh -f spicedbcluster.yaml -o values.yaml

# From stdin
kubectl get spicedbcluster spicedb -o yaml | ./common/convert-cr-to-values.sh -f - -o values.yaml
```

**Output**: Helm-compatible values.yaml with:

- Replica count
- Image version
- Datastore configuration
- TLS settings
- Dispatch configuration
- Resource limits
- Production defaults

## Troubleshooting

### Common Issues

#### 1. Kind Cluster Creation Fails

**Symptom**:

```text
ERROR: failed to create cluster: node(s) already exist for a cluster with the name "spicedb-migration-test"
```

**Solution**:

```bash
kind delete cluster --name spicedb-migration-test
./setup-cluster.sh
```

#### 2. Operator Installation Fails

**Symptom**:

```text
error: unable to fetch SpiceDB operator manifest
```

**Solution**:

```bash
# Check internet connectivity
curl -I https://github.com

# Use specific operator version
export SPICEDB_OPERATOR_VERSION="v1.30.0"
./setup-cluster.sh
```

#### 3. PostgreSQL Not Ready

**Symptom**:

```text
error: timed out waiting for the condition on pods/postgresql-0
```

**Solution**:

```bash
# Check PostgreSQL logs
kubectl logs postgresql-0 -n spicedb-migration-test

# Check PVC binding
kubectl get pvc -n spicedb-migration-test

# Increase timeout
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n spicedb-migration-test --timeout=600s
```

#### 4. Conversion Script Fails

**Symptom**:

```text
jq: command not found
```

**Solution**:

```bash
# Install jq
brew install jq  # macOS
apt-get install jq  # Ubuntu/Debian
yum install jq  # CentOS/RHEL
```

#### 5. Helm Template Rendering Fails

**Symptom**:

```text
Error: template: spicedb/templates/deployment.yaml:XX:XX: executing "spicedb/templates/deployment.yaml" ...
```

**Solution**:

```bash
# Validate generated values
cat /tmp/helm-values.yaml

# Test rendering manually
helm template test-spicedb ../../../../.. -f /tmp/helm-values.yaml --debug

# Check for required fields
grep -E "replicaCount|datastoreEngine|image.tag" /tmp/helm-values.yaml
```

#### 6. Migration Test Hangs

**Symptom**:
Tests appear stuck waiting for pods

**Solution**:

```bash
# Check pod status
kubectl get pods -n spicedb-migration-test

# Check events
kubectl get events -n spicedb-migration-test --sort-by='.lastTimestamp'

# Check resource usage
kubectl top nodes
kubectl top pods -n spicedb-migration-test

# Set shorter timeouts
export TEST_TIMEOUT=300  # 5 minutes
```

#### 7. Rollback Test Fails

**Symptom**:
Operator doesn't recreate pods after rollback

**Solution**:

```bash
# Check SpiceDBCluster status
kubectl get spicedbcluster spicedb-minimal -n spicedb-migration-test -o yaml

# Check operator controller logs
kubectl logs -n spicedb-operator-system -l control-plane=controller-manager --tail=100

# Force reconciliation
kubectl annotate spicedbcluster spicedb-minimal -n spicedb-migration-test force-reconcile="$(date +%s)"
```

### Debugging Tips

#### Enable Verbose Logging

```bash
# Run tests with set -x for detailed output
bash -x ./test-basic-migration.sh

# Enable Helm debug output
export HELM_DEBUG=1
```

#### Inspect Test Artifacts

```bash
# View generated Helm values
cat /tmp/helm-values.yaml

# View rendered templates
cat /tmp/helm-templates.yaml

# View exported operator config
cat /tmp/spicedbcluster-export.yaml
```

#### Keep Cluster for Investigation

```bash
# Skip cleanup
export SKIP_CLEANUP=true
./run-all-tests.sh

# Access cluster
export KUBECONFIG=$(kind get kubeconfig --name spicedb-migration-test)
kubectl get all -n spicedb-migration-test

# Cleanup manually when done
./cleanup-cluster.sh --force
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Operator Migration Tests

on:
  pull_request:
    paths:
      - 'charts/spicedb/**'
      - 'charts/spicedb/tests/integration/migration/**'

jobs:
  migration-tests:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        operator-version: [v1.29.0, v1.30.0, latest]

    steps:
      - uses: actions/checkout@v4

      - name: Set up Kind
        uses: helm/kind-action@v1
        with:
          cluster_name: spicedb-migration-test
          wait: 300s

      - name: Install dependencies
        run: |
          curl -Lo jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
          chmod +x jq
          sudo mv jq /usr/local/bin/

      - name: Run migration tests
        env:
          SPICEDB_OPERATOR_VERSION: ${{ matrix.operator-version }}
        run: |
          cd charts/spicedb/tests/integration/migration/operator-to-helm
          ./setup-cluster.sh
          ./run-all-tests.sh

      - name: Upload test logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: test-logs-${{ matrix.operator-version }}
          path: /tmp/*.yaml
          retention-days: 7
```

## Contributing

When adding new migration tests:

1. Follow existing test patterns
2. Use common validation functions
3. Add proper error handling
4. Update this README
5. Test locally before submitting PR

## License

This test suite is part of the SpiceDB Helm chart and follows the same Apache 2.0 license.

## Support

- **Issues**: [GitHub Issues](https://github.com/salekseev/helm-charts/issues)
- **Migration Guide**: See [operator-to-helm.md](../../../../docs/migration/operator-to-helm.md)
- **Discussions**: [GitHub Discussions](https://github.com/salekseev/helm-charts/discussions)
