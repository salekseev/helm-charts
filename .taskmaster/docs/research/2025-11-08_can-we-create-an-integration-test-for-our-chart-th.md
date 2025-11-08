---
title: Research Session
query: "can we create an integration test for our chart that will deploy spicedb + postgres to a kind cluster, then perform the upgrade to test out migrations?"
date: 11/8/2025
time: 9:48:11 AM
timestamp: 2025-11-08T14:48:11.824Z
exchanges: 3
---

# Research Session

## Initial Query

**Question:** can we create an integration test for our chart that will deploy spicedb + postgres to a kind cluster, then perform the upgrade to test out migrations?

**Response:**

# Integration Testing SpiceDB Helm Chart with Kind and PostgreSQL

Yes, you can absolutely create an integration test for your SpiceDB Helm chart that deploys both SpiceDB and PostgreSQL to a Kind cluster and tests migrations during upgrades. Based on your project context, you already have the test infrastructure foundation (Task 1) completed. Here's a comprehensive approach:

## Recommended Testing Strategy

### 1. **Kind-based Integration Test Framework**

Create a dedicated integration test that uses Kind as your test Kubernetes cluster. This approach provides:

- **Isolation**: Each test run gets a fresh cluster
- **CI/CD compatibility**: Kind works well in GitHub Actions (already part of your CI setup)
- **Speed**: Faster than full-cluster provisioning
- **Reproducibility**: Consistent environment across local and CI runs

### 2. **Test Structure**

Based on your existing test infrastructure (tests/integration/ directory from Task 1), create a migration-focused integration test:

```bash
tests/integration/
├── migration-test.sh          # Main test orchestration script
├── values-initial.yaml        # Initial deployment values
├── values-upgrade.yaml        # Upgrade deployment values
└── verify-migration.sh        # Post-migration verification
```

### 3. **Implementation Approach**

**Phase 1: Initial Deployment**
- Create Kind cluster with appropriate configuration
- Deploy PostgreSQL (use Bitnami's PostgreSQL chart as dependency or standalone)
- Deploy SpiceDB chart v1.0 with PostgreSQL datastore
- Verify migration job runs successfully (hook weight ensures it runs before main deployment)
- Verify SpiceDB pods are healthy
- Load test schema/data using `zed` CLI or SpiceDB client

**Phase 2: Upgrade & Migration Testing**
- Modify chart values or upgrade to new chart version
- Run `helm upgrade` command
- Verify pre-upgrade migration hook executes
- Monitor migration job logs for successful completion
- Verify SpiceDB pods restart and become healthy
- Validate schema/data integrity post-migration
- Test permission checking functionality

**Phase 3: Cleanup**
- Export logs on failure for debugging
- Delete Kind cluster

### 4. **Key Testing Components**

**PostgreSQL Deployment Options:**

1. **Bitnami PostgreSQL subchart** (recommended):
   ```yaml
   # Chart.yaml
   dependencies:
     - name: postgresql
       version: "~12.x.x"
       repository: "https://charts.bitnami.com/bitnami"
       condition: postgresql.enabled
   ```

2. **Standalone PostgreSQL deployment** in test script:
   ```bash
   helm install postgres bitnami/postgresql \
     --set auth.database=spicedb \
     --set auth.username=spicedb \
     --wait
   ```

**Migration Job Verification:**

Your existing migration infrastructure (Task 4) already includes:
- Pre-install/pre-upgrade hooks with `helm.sh/hook` annotations
- Hook weights ensuring proper execution order
- Job completion monitoring (activeDeadlineSeconds: 600)

The integration test should verify:
```bash
# Wait for migration job to complete
kubectl wait --for=condition=complete job/spicedb-migration --timeout=600s

# Verify migration job succeeded
kubectl get job spicedb-migration -o jsonpath='{.status.succeeded}' | grep -q 1
```

### 5. **Sample Integration Test Script**

```bash
#!/bin/bash
set -euo pipefail

CLUSTER_NAME="spicedb-test"
NAMESPACE="spicedb-test"

# Create Kind cluster
kind create cluster --name "$CLUSTER_NAME" --config tests/integration/kind-config.yaml

# Load Docker images if needed
kind load docker-image authzed/spicedb:latest --name "$CLUSTER_NAME"

# Install PostgreSQL
helm install postgres bitnami/postgresql \
  --namespace "$NAMESPACE" --create-namespace \
  --set auth.database=spicedb \
  --set auth.password=testpass \
  --wait --timeout 5m

# Install SpiceDB v1 (initial)
helm install spicedb ./charts/spicedb \
  --namespace "$NAMESPACE" \
  --values tests/integration/values-initial.yaml \
  --wait --timeout 5m

# Verify migration job completed
kubectl wait --for=condition=complete job/spicedb-migration \
  -n "$NAMESPACE" --timeout=10m

# Load test schema
kubectl run -n "$NAMESPACE" zed-client --rm -i --restart=Never \
  --image=authzed/zed:latest -- \
  zed schema write --endpoint spicedb:50051 --insecure < tests/integration/test-schema.zed

# Upgrade SpiceDB (triggers migration)
helm upgrade spicedb ./charts/spicedb \
  --namespace "$NAMESPACE" \
  --values tests/integration/values-upgrade.yaml \
  --wait --timeout 5m

# Verify upgrade migration completed
kubectl wait --for=condition=complete job/spicedb-migration \
  -n "$NAMESPACE" --timeout=10m

# Verify data integrity
./tests/integration/verify-migration.sh

# Cleanup
kind delete cluster --name "$CLUSTER_NAME"
```

### 6. **GitHub Actions Integration**

Extend your existing `.github/workflows/ci.yaml` with an integration test job:

```yaml
jobs:
  integration-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Kind
        uses: helm/kind-action@v1
        with:
          cluster_name: spicedb-test
          
      - name: Run integration tests
        run: ./tests/integration/migration-test.sh
        
      - name: Export logs on failure
        if: failure()
        run: |
          kubectl logs -n spicedb-test -l app=spicedb --tail=-1 > spicedb.log
          kubectl logs -n spicedb-test -l app=postgresql --tail=-1 > postgres.log
          
      - name: Upload logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: integration-test-logs
          path: "*.log"
```

### 7. **Migration-Specific Test Scenarios**

Test these migration scenarios based on your Task 4 implementation:

1. **Fresh install migration**: Verify `spicedb migrate head` runs on first install
2. **Version upgrade migration**: Change SpiceDB image version and verify migration hook executes
3. **Schema migration**: Add new schema fields and verify migration applies correctly
4. **Failed migration handling**: Inject migration failure and verify backoffLimit (3) and hook-delete-policy work correctly
5. **Migration idempotency**: Run upgrade twice with same values, verify migrations are idempotent
6. **Phased migration testing**: If using migrations.targetPhase, verify partial migrations work

### 8. **Additional Considerations**

- **Test data persistence**: Verify data survives upgrades by writing permissions before upgrade and checking after
- **Connection string handling**: Test both inline secrets and existingSecret scenarios (Task 3)
- **TLS testing**: Optionally test migrations with TLS enabled for datastore connections (Task 5)
- **Cleanup verification**: Ensure hook-delete-policy removes old migration jobs

This comprehensive integration testing approach leverages your existing test infrastructure while providing real-world validation of the migration system you've already built in Task 4.

---

## Follow-up 1

**Question:** Can we use the official postgres container image. Can we also enable local testing of this pipeline with act comand?

**Response:**

# PostgreSQL Container Image and Local Testing with `act`

## Official PostgreSQL Container Image

**Yes, you can absolutely use the official PostgreSQL container image** for your integration tests. In fact, this is a valid alternative to the Bitnami PostgreSQL chart I previously recommended. Here are your options:

### Option 1: Official PostgreSQL Image (Direct Deployment)

The official `postgres:16` (or `postgres:15`, `postgres:14`) image from Docker Hub is production-ready and well-maintained. For Kind-based integration tests, you can deploy it directly via kubectl manifests:

```yaml
# tests/integration/postgres-deployment.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-init
  namespace: spicedb-test
data:
  init.sql: |
    CREATE DATABASE spicedb;
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: spicedb-test
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:16
        env:
        - name: POSTGRES_USER
          value: spicedb
        - name: POSTGRES_PASSWORD
          value: testpassword
        - name: POSTGRES_DB
          value: spicedb
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        ports:
        - containerPort: 5432
          name: postgres
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: spicedb-test
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
```

**Advantages:**
- Minimal dependencies (no Helm chart required)
- Faster startup in tests
- Matches what many users deploy in production
- Smaller attack surface (official image, minimal tooling)

**Deployment in tests:**
```bash
kubectl apply -f tests/integration/postgres-deployment.yaml
kubectl wait --for=condition=ready pod -l app=postgres -n spicedb-test --timeout=5m
```

### Option 2: Bitnami PostgreSQL Chart (Recommended for Production-like Testing)

The Bitnami chart provides additional production features (backup, monitoring, metrics) but adds complexity:

```bash
helm install postgres oci://registry-1.docker.io/bitnamicharts/postgresql \
  --namespace spicedb-test --create-namespace \
  --set auth.database=spicedb \
  --set auth.username=spicedb \
  --set auth.password=testpass \
  --set primary.persistence.enabled=false \
  --wait --timeout 5m
```

**Use this when:** Testing scenarios that require PostgreSQL high-availability or replication features.

## Local Testing with `act`

**Yes, you can use `act` for local GitHub Actions testing**, with some important caveats:

### Setup and Installation

```bash
# Install act (macOS)
brew install act

# Or Linux
curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

# Install Docker or Podman (act requirement)
# act uses container runtime to simulate GitHub Actions runners
```

### Adapting Your CI Workflow for `act`

Your existing `.github/workflows/ci.yaml` will need minor adjustments for local testing:

```yaml
# .github/workflows/ci.yaml
name: CI

on:
  pull_request:
    branches: [master]
  push:
    branches: [master]

jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Helm
        uses: azure/setup-helm@v4
        with:
          version: '3.14.0'
      
      - name: Install helm-unittest
        run: helm plugin install https://github.com/helm-unittest/helm-unittest
        
      - name: Run helm lint
        run: helm lint charts/spicedb
        
      - name: Run helm unittest
        run: helm unittest charts/spicedb

  integration-test:
    runs-on: ubuntu-latest
    # Skip in act by default (resource-intensive)
    if: ${{ !github.event.act }}
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Kind
        uses: helm/kind-action@v1
        with:
          cluster_name: spicedb-test
          
      - name: Run integration tests
        run: ./tests/integration/migration-test.sh
```

### Running Tests Locally with `act`

```bash
# Run all jobs (default event: push)
act

# Run specific job
act -j lint-and-test

# Run with specific event
act pull_request

# Run with secrets (if needed)
act -s GITHUB_TOKEN=<your_token>

# Use specific runner image (smaller, faster)
act -P ubuntu-latest=catthehacker/ubuntu:act-latest

# Dry-run to see what would execute
act --dryrun
```

### Integration Test Considerations for `act`

**Challenge:** Kind-in-Docker requires privileged access, which `act` (running in Docker) cannot easily provide (Docker-in-Docker complexity).

**Solutions:**

**Option 1: Skip Integration Tests in `act`** (recommended)
Use the `if: ${{ !github.event.act }}` condition (shown above) to skip resource-intensive integration tests locally. Run unit tests and lint checks with `act`, but run full integration tests in actual GitHub Actions.

**Option 2: Standalone Local Integration Script**
Create a separate script that runs outside `act` for local integration testing:

```bash
#!/bin/bash
# tests/integration/local-test.sh
# Run this directly on your machine (not via act)

set -euo pipefail

CLUSTER_NAME="spicedb-test-local"
NAMESPACE="spicedb-test"

echo "Creating Kind cluster..."
kind create cluster --name "$CLUSTER_NAME"

echo "Deploying PostgreSQL..."
kubectl apply -f tests/integration/postgres-deployment.yaml
kubectl wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=5m

echo "Installing SpiceDB chart (initial)..."
helm install spicedb ./charts/spicedb \
  --namespace "$NAMESPACE" --create-namespace \
  --set config.datastoreEngine=postgres \
  --set config.datastoreURI="postgres://spicedb:testpassword@postgres:5432/spicedb?sslmode=disable" \
  --wait --timeout 5m

echo "Verifying migration job..."
kubectl wait --for=condition=complete job/spicedb-migration -n "$NAMESPACE" --timeout=10m

echo "Performing upgrade test..."
helm upgrade spicedb ./charts/spicedb \
  --namespace "$NAMESPACE" \
  --set image.tag=v1.35.0 \
  --wait --timeout 5m

echo "Cleanup..."
kind delete cluster --name "$CLUSTER_NAME"
```

**Usage:**
```bash
# Run locally (not via act)
chmod +x tests/integration/local-test.sh
./tests/integration/local-test.sh
```

**Option 3: Use Podman as Runtime for `act`**
If using Podman with privileged containers enabled, you can run Kind inside `act` containers:

```bash
act --container-daemon-socket unix:///run/podman/podman.sock
```

However, this requires additional Podman configuration and is generally more complex than Option 1 or 2.

## Recommended Workflow

### For Local Development:
1. **Unit tests and linting** → Run with `act -j lint-and-test` (fast, reliable)
2. **Integration tests** → Run with standalone `./tests/integration/local-test.sh` (direct Kind access)

### For CI/CD:
1. **All tests** → Run in GitHub Actions (full environment, no restrictions)
2. **Use official PostgreSQL image** in integration tests for simplicity and speed

### Sample Combined Approach

```bash
# Makefile for convenience
.PHONY: test-unit test-integration test-all

test-unit:
	@echo "Running unit tests with act..."
	act -j lint-and-test

test-integration:
	@echo "Running integration tests locally..."
	./tests/integration/local-test.sh

test-all: test-unit test-integration
	@echo "All tests completed!"
```

This approach gives you fast local feedback with `act` for unit tests while maintaining comprehensive integration testing capabilities both locally and in CI.

---

## Follow-up 2

**Question:** Let's use Option 2. Let's also test for sample data persistence and cleanup job.

**Response:**

# Enhanced Integration Testing with Official PostgreSQL and Sample Data Persistence

Based on your requirements to use the official PostgreSQL image and test both data persistence and cleanup jobs, here's a comprehensive approach:

## Option 2 Implementation: Official PostgreSQL Container

### PostgreSQL Deployment Manifest

Create `tests/integration/postgres-deployment.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: spicedb-test
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-config
  namespace: spicedb-test
data:
  POSTGRES_DB: spicedb
  POSTGRES_USER: spicedb
---
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: spicedb-test
type: Opaque
stringData:
  POSTGRES_PASSWORD: testpassword123
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  namespace: spicedb-test
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: spicedb-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:16
        envFrom:
        - configMapRef:
            name: postgres-config
        - secretRef:
            name: postgres-secret
        ports:
        - containerPort: 5432
          name: postgres
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
          subPath: pgdata
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - spicedb
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: postgres-data
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: spicedb-test
spec:
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
```

## Sample Data Persistence Testing

### Test Schema and Data

Create `tests/integration/test-schema.zed`:

```zed
definition user {}

definition document {
    relation writer: user
    relation reader: user
    permission edit = writer
    permission view = reader + writer
}
```

Create `tests/integration/test-data.yaml`:

```yaml
# Sample relationships to write
relationships:
  - resource: "document:testdoc1"
    relation: "writer"
    subject: "user:alice"
  - resource: "document:testdoc1"
    relation: "reader"
    subject: "user:bob"
  - resource: "document:testdoc2"
    relation: "writer"
    subject: "user:charlie"
```

### Data Persistence Verification Script

Create `tests/integration/verify-persistence.sh`:

```bash
#!/bin/bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-spicedb-test}"
ENDPOINT="${ENDPOINT:-spicedb:50051}"
TOKEN="${TOKEN:-insecure-default-key-change-in-production}"

echo "=== Verifying Data Persistence ==="

# Function to check permission using zed
check_permission() {
    local resource=$1
    local permission=$2
    local subject=$3
    
    kubectl run -n "$NAMESPACE" zed-check --rm -i --restart=Never \
        --image=authzed/zed:latest -- \
        zed permission check "$resource" "$permission" "$subject" \
        --endpoint "$ENDPOINT" \
        --insecure \
        --token "$TOKEN"
}

# Verify schema exists
echo "Checking schema..."
kubectl run -n "$NAMESPACE" zed-schema --rm -i --restart=Never \
    --image=authzed/zed:latest -- \
    zed schema read \
    --endpoint "$ENDPOINT" \
    --insecure \
    --token "$TOKEN" | grep -q "definition document"

echo "✓ Schema verified"

# Verify relationships exist
echo "Checking relationships..."
if check_permission "document:testdoc1" "edit" "user:alice"; then
    echo "✓ Alice can edit testdoc1"
else
    echo "✗ Failed: Alice should be able to edit testdoc1"
    exit 1
fi

if check_permission "document:testdoc1" "view" "user:bob"; then
    echo "✓ Bob can view testdoc1"
else
    echo "✗ Failed: Bob should be able to view testdoc1"
    exit 1
fi

# Verify negative permission
if ! check_permission "document:testdoc2" "edit" "user:alice" 2>/dev/null; then
    echo "✓ Alice cannot edit testdoc2 (expected)"
else
    echo "✗ Failed: Alice should NOT be able to edit testdoc2"
    exit 1
fi

echo "=== All persistence checks passed ==="
```

## Cleanup Job Testing

### Hook Cleanup Verification Script

Create `tests/integration/verify-cleanup.sh`:

```bash
#!/bin/bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-spicedb-test}"
RELEASE_NAME="${RELEASE_NAME:-spicedb}"

echo "=== Verifying Hook Cleanup Behavior ==="

# Check for migration jobs
echo "Checking migration job state..."
MIGRATION_JOBS=$(kubectl get jobs -n "$NAMESPACE" -l "app.kubernetes.io/name=spicedb,app.kubernetes.io/component=migration" -o name 2>/dev/null || true)

if [ -z "$MIGRATION_JOBS" ]; then
    echo "✓ No lingering migration jobs (cleaned up by hook-delete-policy)"
else
    echo "Migration jobs found:"
    echo "$MIGRATION_JOBS"
    
    # Check if jobs have deletion timestamp (being cleaned up)
    for job in $MIGRATION_JOBS; do
        DELETION_TS=$(kubectl get "$job" -n "$NAMESPACE" -o jsonpath='{.metadata.deletionTimestamp}')
        if [ -n "$DELETION_TS" ]; then
            echo "✓ $job is being deleted (deletionTimestamp: $DELETION_TS)"
        else
            echo "⚠ $job exists without deletionTimestamp"
        fi
    done
fi

# Verify hook-delete-policy in chart
echo "Verifying hook-delete-policy annotation..."
HOOK_POLICY=$(helm get manifest "$RELEASE_NAME" -n "$NAMESPACE" | \
    yq eval 'select(.kind == "Job" and .metadata.name == "*migration*") | .metadata.annotations."helm.sh/hook-delete-policy"' - 2>/dev/null || echo "not-found")

if [ "$HOOK_POLICY" = "before-hook-creation" ] || [ "$HOOK_POLICY" = "hook-succeeded" ]; then
    echo "✓ Correct hook-delete-policy found: $HOOK_POLICY"
else
    echo "⚠ Hook-delete-policy not found or incorrect: $HOOK_POLICY"
fi

# Check for completed pods from previous migration jobs
COMPLETED_PODS=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/component=migration" --field-selector=status.phase=Succeeded -o name 2>/dev/null || true)

if [ -z "$COMPLETED_PODS" ]; then
    echo "✓ No completed migration pods (cleaned up successfully)"
else
    echo "⚠ Found completed migration pods:"
    echo "$COMPLETED_PODS"
fi

echo "=== Cleanup verification complete ==="
```

## Comprehensive Integration Test Script

Create `tests/integration/migration-test.sh`:

```bash
#!/bin/bash
set -euo pipefail

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-spicedb-test}"
NAMESPACE="spicedb-test"
RELEASE_NAME="spicedb"
CHART_PATH="./charts/spicedb"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

cleanup() {
    log_info "Cleaning up Kind cluster..."
    kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true
}

# Trap cleanup on exit
trap cleanup EXIT

log_info "Creating Kind cluster: $CLUSTER_NAME"
kind create cluster --name "$CLUSTER_NAME" --wait 5m

log_info "Deploying PostgreSQL..."
kubectl apply -f tests/integration/postgres-deployment.yaml
kubectl wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=5m

log_info "Installing SpiceDB chart (initial deployment)..."
helm install "$RELEASE_NAME" "$CHART_PATH" \
    --namespace "$NAMESPACE" \
    --set config.datastoreEngine=postgres \
    --set config.datastoreURI="postgres://spicedb:testpassword123@postgres:5432/spicedb?sslmode=disable" \
    --set config.presharedKey="insecure-default-key-change-in-production" \
    --wait --timeout 10m

log_info "Waiting for migration job to complete..."
kubectl wait --for=condition=complete job -l "app.kubernetes.io/component=migration" \
    -n "$NAMESPACE" --timeout=10m

log_info "Verifying SpiceDB pods are healthy..."
kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=spicedb" \
    -n "$NAMESPACE" --timeout=5m

log_info "Loading test schema..."
kubectl run -n "$NAMESPACE" zed-schema-load --rm -i --restart=Never \
    --image=authzed/zed:latest -- sh -c "cat <<'EOF' | zed schema write --endpoint spicedb:50051 --insecure --token insecure-default-key-change-in-production
$(cat tests/integration/test-schema.zed)
EOF"

log_info "Writing test relationships..."
kubectl run -n "$NAMESPACE" zed-data-load --rm -i --restart=Never \
    --image=authzed/zed:latest -- sh -c "
zed relationship create document:testdoc1 writer user:alice --endpoint spicedb:50051 --insecure --token insecure-default-key-change-in-production
zed relationship create document:testdoc1 reader user:bob --endpoint spicedb:50051 --insecure --token insecure-default-key-change-in-production
zed relationship create document:testdoc2 writer user:charlie --endpoint spicedb:50051 --insecure --token insecure-default-key-change-in-production
"

log_info "Verifying data before upgrade..."
./tests/integration/verify-persistence.sh

log_info "Performing Helm upgrade (triggers pre-upgrade migration)..."
helm upgrade "$RELEASE_NAME" "$CHART_PATH" \
    --namespace "$NAMESPACE" \
    --set config.datastoreEngine=postgres \
    --set config.datastoreURI="postgres://spicedb:testpassword123@postgres:5432/spicedb?sslmode=disable" \
    --set config.presharedKey="insecure-default-key-change-in-production" \
    --set image.tag=v1.35.0 \
    --wait --timeout 10m

log_info "Waiting for upgrade migration to complete..."
kubectl wait --for=condition=complete job -l "app.kubernetes.io/component=migration" \
    -n "$NAMESPACE" --timeout=10m

log_info "Verifying data persistence after upgrade..."
./tests/integration/verify-persistence.sh

log_info "Verifying migration job cleanup..."
./tests/integration/verify-cleanup.sh

log_info "Testing second upgrade (idempotency check)..."
helm upgrade "$RELEASE_NAME" "$CHART_PATH" \
    --namespace "$NAMESPACE" \
    --set config.datastoreEngine=postgres \
    --set config.datastoreURI="postgres://spicedb:testpassword123@postgres:5432/spicedb?sslmode=disable" \
    --set config.presharedKey="insecure-default-key-change-in-production" \
    --set replicas=2 \
    --wait --timeout 10m

log_info "Final data verification..."
./tests/integration/verify-persistence.sh

log_info "All tests passed successfully! ✓"
```

Make all scripts executable:

```bash
chmod +x tests/integration/migration-test.sh
chmod +x tests/integration/verify-persistence.sh
chmod +x tests/integration/verify-cleanup.sh
```

## Local Testing with `act`

### Makefile for Convenience

Create or update `Makefile`:

```makefile
.PHONY: test-unit test-integration test-local test-ci-local

test-unit:
	@echo "Running unit tests..."
	helm unittest charts/spicedb

test-integration:
	@echo "Running integration tests (requires Kind)..."
	./tests/integration/migration-test.sh

test-local: test-unit test-integration
	@echo "All local tests completed!"

test-ci-local:
	@echo "Running CI tests locally with act..."
	act -j lint-and-test --container-architecture linux/amd64
```

### Usage

```bash
# Run all tests locally
make test-local

# Run only integration tests
make test-integration

# Run CI pipeline locally with act
make test-ci-local
```

This comprehensive approach tests:
1. ✅ Official PostgreSQL deployment
2. ✅ Initial migration job execution
3. ✅ Schema and data loading
4. ✅ Data persistence across upgrades
5. ✅ Pre-upgrade migration hooks
6. ✅ Migration job cleanup (hook-delete-policy)
7. ✅ Idempotent migrations (second upgrade)
8. ✅ Permission verification throughout


---

*Generated by Task Master Research Command*  
*Timestamp: 2025-11-08T14:48:11.824Z*
