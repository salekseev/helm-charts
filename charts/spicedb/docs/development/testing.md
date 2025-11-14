# Testing Guide

This guide covers running tests for the SpiceDB Helm chart, including unit tests, integration tests, and CI workflows.

## Test Structure

The chart has comprehensive test coverage organized into several test suites:

```
tests/
├── hooks/                    # Migration hook tests (113 tests)
│   ├── migration-job_test.yaml
│   ├── migration-validation_test.yaml
│   ├── migration-cleanup_test.yaml
│   └── ...
├── unit/                     # Unit tests (197+ tests)
│   ├── deployment_test.yaml
│   ├── service_test.yaml
│   ├── preset_*_test.yaml
│   └── ...
└── integration/              # Integration test scripts
    ├── test-migration-tracking.sh
    └── migration-test.sh
```

## Prerequisites

### Required Tools

```bash
# Helm (3.8+)
helm version

# Helm unittest plugin
helm plugin install https://github.com/helm-unittest/helm-unittest.git

# kubectl (for integration tests)
kubectl version

# Kind (for local Kubernetes testing)
kind version

# jq (for script-based tests)
jq --version
```

### Optional Tools

```bash
# Chart Testing (ct) for CI validation
ct version

# Conftest for security policy validation
conftest --version
```

## Running Tests

### Quick Test (All Unit Tests)

```bash
# Run all unit and hook tests
helm unittest . --file 'tests/unit/*.yaml' --file 'tests/hooks/*.yaml'
```

**Expected Output:**

```
Charts:      1 passed, 1 total
Test Suites: 24 passed, 24 total
Tests:       310 passed, 310 total
```

### Specific Test Suites

```bash
# Migration hooks only (113 tests)
helm unittest . --file 'tests/hooks/*.yaml'

# Deployment tests
helm unittest . --file 'tests/unit/deployment*.yaml'

# Preset validation
helm unittest . --file 'tests/unit/preset_*.yaml'

# Auto-secret generation
helm unittest . --file 'tests/unit/auto-secret_test.yaml'
```

### Watch Mode

```bash
# Auto-rerun tests on file changes
helm unittest . --file 'tests/**/*.yaml' --watch
```

## Template Rendering Tests

Validate that templates render correctly:

```bash
# Test default values
helm template test .

# Test with production-postgres preset
helm template test . -f values-presets/production-postgres.yaml \
  --set config.existingSecret=test-secret

# Test with all presets
for preset in values-presets/*.yaml; do
  echo "Testing $preset..."
  helm template test . -f "$preset" --set config.existingSecret=test-secret
done
```

### Dry-Run Validation

Validate rendered manifests against Kubernetes API:

```bash
# Render and validate
helm template test . | kubectl apply --dry-run=client -f -

# With production preset
helm template test . \
  -f values-presets/production-postgres.yaml \
  --set config.existingSecret=test-secret | \
  kubectl apply --dry-run=client -f -
```

## Integration Tests

### Local Integration Testing with Kind

```bash
# Create Kind cluster
kind create cluster --name spicedb-test

# Install with default values
helm install spicedb-test . --wait --timeout 5m

# Verify deployment
kubectl get pods -l app.kubernetes.io/name=spicedb
kubectl logs -l app.kubernetes.io/name=spicedb

# Check with status script
./scripts/status.sh --namespace default --release spicedb-test

# Clean up
helm uninstall spicedb-test
kind delete cluster --name spicedb-test
```

### Testing with PostgreSQL Backend

```bash
# Deploy PostgreSQL
kubectl create namespace spicedb-test
helm install postgres bitnami/postgresql -n spicedb-test \
  --set auth.password=testpassword

# Create secret
kubectl create secret generic spicedb-config -n spicedb-test \
  --from-literal=preshared-key="$(openssl rand -base64 32)" \
  --from-literal=datastore-uri="postgresql://postgres:testpassword@postgres-postgresql:5432/postgres"

# Install SpiceDB
helm install spicedb . -n spicedb-test \
  -f values-presets/production-postgres.yaml \
  --set config.existingSecret=spicedb-config \
  --wait --timeout 10m

# Verify migration job completed
kubectl get jobs -n spicedb-test -l app.kubernetes.io/component=migration

# Check deployment status
./scripts/status.sh -n spicedb-test -r spicedb

# Clean up
helm uninstall spicedb postgres -n spicedb-test
kubectl delete namespace spicedb-test
```

## CI/CD Testing

The chart includes GitHub Actions workflows that run on every PR:

### Unit Tests & Validation Workflow

```yaml
# .github/workflows/ci-unit.yaml
- Helm lint (strict mode)
- Helm unittest (all tests)
- Preset validation (4 presets)
- Security policy validation (Conftest)
- Chart testing (ct lint + ct install)
```

### Running CI Tests Locally

```bash
# Lint
helm lint . --strict

# Unittest
helm unittest . --file 'tests/unit/*.yaml' --file 'tests/hooks/*.yaml'

# Preset validation
for preset in values-presets/*.yaml; do
  helm template test . -f "$preset" \
    --set config.existingSecret=test-secret \
    --set config.autogenerateSecret=false > /dev/null
done

# Chart testing
ct lint --config .github/ct.yaml
```

## Test Coverage

### Current Coverage Statistics

| Test Suite | Tests | Coverage |
|------------|-------|----------|
| Migration hooks | 113 | Complete |
| Deployment configuration | 45 | Complete |
| Service & networking | 18 | Complete |
| Security & RBAC | 24 | Complete |
| Auto-secret generation | 10 | Complete |
| Preset configurations | 21 | Complete |
| Operator-style config | 11 | Complete |
| Health probes | 8 | Complete |
| Anti-affinity & topology | 18 | Complete |
| Strategic merge patches | 18 | Complete |
| **Total** | **310+** | **Comprehensive** |

### Coverage by Feature

- ✅ **Migration System**: 113 tests covering job creation, validation, cleanup, RBAC
- ✅ **Configuration Presets**: All 4 presets validated in CI
- ✅ **Secret Management**: Auto-generation with lookup, existing secret support
- ✅ **High Availability**: Anti-affinity, topology spread, PDB
- ✅ **Security**: TLS/mTLS, NetworkPolicy, Pod Security Standards
- ✅ **Operator Compatibility**: Annotations, deployment patterns

## Writing Tests

### Test File Structure

```yaml
suite: test migration job
templates:
  - templates/hooks/migration-job.yaml
tests:
  - it: should create migration job when migrations enabled
    set:
      migrations.enabled: true
      config.datastoreEngine: postgres
      config.autogenerateSecret: true
    asserts:
      - isKind:
          of: Job
      - equal:
          path: metadata.name
          value: RELEASE-NAME-spicedb-migration
```

### Best Practices

1. **Use descriptive test names** that explain what is being tested
2. **Test both positive and negative cases** (feature enabled/disabled)
3. **Use snapshots sparingly** - prefer explicit assertions
4. **Group related tests** in the same file
5. **Test edge cases** - empty values, special characters, boundary conditions

### Running Single Test

```bash
# Run specific test by name
helm unittest . --file 'tests/hooks/migration-job_test.yaml' \
  -t "should create migration job when migrations enabled"
```

## Debugging Tests

### View Rendered Template

```bash
# Show what a specific template renders to
helm template test . --debug --show-only templates/deployment.yaml
```

### Test Failure Investigation

```bash
# Run with verbose output
helm unittest . --file 'tests/unit/deployment_test.yaml' -v

# Update snapshots if needed
helm unittest . --file 'tests/unit/deployment_test.yaml' --update-snapshot
```

## Known Test Issues

See [Technical Debt](tech-debt.md#pre-existing-unit-test-failures) for details on the 4 pre-existing test failures (unrelated to migration functionality).

## Additional Resources

- [Helm Unittest Documentation](https://github.com/helm-unittest/helm-unittest)
- [Chart Testing (ct) Documentation](https://github.com/helm/chart-testing)
- [Helm Testing Best Practices](https://helm.sh/docs/topics/chart_tests/)

---

**Last Updated:** 2025-11-12
**Maintainer:** @salekseev
