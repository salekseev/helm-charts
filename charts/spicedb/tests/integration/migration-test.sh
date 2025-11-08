#!/bin/bash
# migration-test.sh - Main orchestration script for SpiceDB integration tests
# Tests PostgreSQL deployment, chart installation, migrations, and data persistence
set -euo pipefail

# Configuration
export CLUSTER_NAME="${KIND_CLUSTER_NAME:-spicedb-test}"
export NAMESPACE="spicedb-test"
export RELEASE_NAME="${HELM_RELEASE_NAME:-spicedb}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_PATH="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }
log_section() { echo -e "${CYAN}[====]${NC} $1 ${CYAN}[====]${NC}"; }

# Track test failures
FAILURES=0

# Cleanup function
cleanup() {
    local exit_code=$?

    if [ $exit_code -ne 0 ] || [ $FAILURES -gt 0 ]; then
        log_error "Test failed with exit code $exit_code and $FAILURES failure(s)"
        capture_logs
    fi

    if [ "${SKIP_CLEANUP:-false}" != "true" ]; then
        # Only delete cluster if we created it (not if GitHub Actions created it)
        if [ -z "${CI:-}" ] && kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
            log_info "Cleaning up Kind cluster: $CLUSTER_NAME"
            kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true
        else
            log_info "Skipping cluster cleanup (managed externally)"
        fi
    else
        log_warn "Skipping cleanup (SKIP_CLEANUP=true)"
        log_info "To access cluster: export KUBECONFIG=$(kind get kubeconfig --name="$CLUSTER_NAME" 2>/dev/null || echo 'managed-by-ci')"
    fi

    if [ $exit_code -ne 0 ] || [ $FAILURES -gt 0 ]; then
        exit 1
    fi
}
trap cleanup EXIT

# Function to capture logs on failure
capture_logs() {
    log_info "Capturing logs to $LOG_DIR..."
    mkdir -p "$LOG_DIR"

    # Capture pod logs
    for pod in $(kubectl get pods -n "$NAMESPACE" -o name 2>/dev/null || true); do
        pod_name=$(echo "$pod" | cut -d/ -f2)
        log_debug "Capturing logs for $pod_name"
        kubectl logs -n "$NAMESPACE" "$pod" --all-containers=true \
            > "$LOG_DIR/${pod_name}.log" 2>&1 || true
    done

    # Capture pod descriptions
    kubectl describe pods -n "$NAMESPACE" > "$LOG_DIR/pods-describe.txt" 2>&1 || true

    # Capture job descriptions
    kubectl describe jobs -n "$NAMESPACE" > "$LOG_DIR/jobs-describe.txt" 2>&1 || true

    # Capture events
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' \
        > "$LOG_DIR/events.txt" 2>&1 || true

    # Capture Helm release info
    helm get values "$RELEASE_NAME" -n "$NAMESPACE" \
        > "$LOG_DIR/helm-values.yaml" 2>&1 || true
    helm get manifest "$RELEASE_NAME" -n "$NAMESPACE" \
        > "$LOG_DIR/helm-manifest.yaml" 2>&1 || true

    log_info "Logs captured in $LOG_DIR"
    ls -lh "$LOG_DIR"
}

# Function to setup Kind cluster
setup_kind_cluster() {
    log_section "Setting up Kind cluster"

    # Check if cluster already exists (e.g., created by GitHub Actions)
    if kubectl cluster-info > /dev/null 2>&1; then
        log_info "Kubernetes cluster already available, skipping Kind setup"
        log_info "Using existing cluster context: $(kubectl config current-context)"

        # Verify cluster is responsive
        log_info "Waiting for cluster to be ready..."
        kubectl wait --for=condition=Ready nodes --all --timeout=120s
        log_info "✓ Cluster ready"
        return 0
    fi

    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_warn "Cluster $CLUSTER_NAME already exists, deleting..."
        kind delete cluster --name "$CLUSTER_NAME"
    fi

    log_info "Creating Kind cluster: $CLUSTER_NAME"

    # Create Kind cluster with extra port mappings for debugging
    cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30051
    hostPort: 50051
    protocol: TCP
  - containerPort: 30443
    hostPort: 8443
    protocol: TCP
EOF

    # Kind automatically sets the kubeconfig context, no need to export KUBECONFIG
    # Just verify we're using the right context
    kubectl config use-context "kind-${CLUSTER_NAME}"

    log_info "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=120s

    log_info "✓ Kind cluster ready"
}

# Function to deploy PostgreSQL
deploy_postgres() {
    log_section "Deploying PostgreSQL"

    # Clean up any existing Helm releases in the namespace before deploying PostgreSQL
    if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
        log_info "Namespace $NAMESPACE exists, checking for existing releases..."
        if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "^${RELEASE_NAME}[[:space:]]"; then
            log_warn "Cleaning up existing Helm release..."
            helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --wait || true
            sleep 5
        fi
    fi

    log_info "Applying PostgreSQL manifests..."
    kubectl apply -f "$SCRIPT_DIR/postgres-deployment.yaml"

    log_info "Waiting for PostgreSQL StatefulSet to be ready..."
    kubectl wait --for=condition=ready pod \
        -l "app.kubernetes.io/name=postgres" \
        -n "$NAMESPACE" \
        --timeout=300s

    log_info "Verifying PostgreSQL connectivity..."
    local max_attempts=10
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log_debug "Attempt $attempt/$max_attempts to connect to PostgreSQL..."

        if kubectl exec -n "$NAMESPACE" postgres-0 -- \
            psql -U spicedb -d spicedb -c "SELECT 1" > /dev/null 2>&1; then
            log_info "✓ PostgreSQL is ready and accepting connections"
            return 0
        fi

        sleep 3
        attempt=$((attempt + 1))
    done

    log_error "Failed to connect to PostgreSQL after $max_attempts attempts"
    return 1
}

# Function to install SpiceDB chart
install_chart() {
    log_section "Installing SpiceDB chart"

    # Clean up any existing release first
    if helm list -n "$NAMESPACE" | grep -q "^${RELEASE_NAME}[[:space:]]"; then
        log_warn "Existing Helm release found, uninstalling..."
        helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --wait || true
        # Wait a bit for resources to be cleaned up
        sleep 5
    fi

    log_info "Installing Helm chart: $RELEASE_NAME"
    helm install "$RELEASE_NAME" "$CHART_PATH" \
        --namespace "$NAMESPACE" \
        --set config.datastoreEngine=postgres \
        --set config.datastore.hostname=postgres.spicedb-test.svc.cluster.local \
        --set config.datastore.port=5432 \
        --set config.datastore.username=spicedb \
        --set config.datastore.password=testpassword123 \
        --set config.datastore.database=spicedb \
        --set config.presharedKey="insecure-default-key-change-in-production" \
        --set image.tag=v1.35.3 \
        --wait --timeout=10m

    log_info "Waiting for migration job to complete..."
    kubectl wait --for=condition=complete job \
        -l "app.kubernetes.io/component=migration" \
        -n "$NAMESPACE" \
        --timeout=600s || {
        log_error "Migration job failed or timed out"
        kubectl logs -n "$NAMESPACE" -l "app.kubernetes.io/component=migration" --tail=50
        return 1
    }

    log_info "Verifying SpiceDB pods are ready..."
    kubectl wait --for=condition=ready pod \
        -l "app.kubernetes.io/name=spicedb" \
        -n "$NAMESPACE" \
        --timeout=300s

    log_info "✓ SpiceDB chart installed successfully"
}

# Function to load test data
load_test_data() {
    log_section "Loading test schema and data"

    log_info "Running initial data load..."
    "$SCRIPT_DIR/verify-persistence.sh" initial || {
        log_error "Failed to load initial test data"
        ((FAILURES++))
        return 1
    }

    log_info "✓ Test data loaded successfully"
}

# Function to perform upgrade
upgrade_chart() {
    log_section "Performing Helm upgrade"

    # Capture pre-upgrade state for cleanup verification
    log_info "Capturing pre-upgrade migration job state..."
    "$SCRIPT_DIR/verify-cleanup.sh" before || {
        log_warn "Failed to capture pre-upgrade state"
    }

    log_info "Upgrading Helm chart with modified values..."
    helm upgrade "$RELEASE_NAME" "$CHART_PATH" \
        --namespace "$NAMESPACE" \
        --set config.datastoreEngine=postgres \
        --set config.datastore.hostname=postgres.spicedb-test.svc.cluster.local \
        --set config.datastore.port=5432 \
        --set config.datastore.username=spicedb \
        --set config.datastore.password=testpassword123 \
        --set config.datastore.database=spicedb \
        --set config.presharedKey="insecure-default-key-change-in-production" \
        --set image.tag=v1.36.0 \
        --set replicaCount=2 \
        --wait --timeout=10m

    log_info "Waiting for upgrade migration job to complete..."
    kubectl wait --for=condition=complete job \
        -l "app.kubernetes.io/component=migration" \
        -n "$NAMESPACE" \
        --timeout=600s || {
        log_error "Upgrade migration job failed or timed out"
        kubectl logs -n "$NAMESPACE" -l "app.kubernetes.io/component=migration" --tail=50
        return 1
    }

    log_info "Verifying SpiceDB pods are ready after upgrade..."
    kubectl wait --for=condition=ready pod \
        -l "app.kubernetes.io/name=spicedb" \
        -n "$NAMESPACE" \
        --timeout=300s

    log_info "✓ Helm upgrade completed successfully"
}

# Function to verify persistence
verify_persistence() {
    log_section "Verifying data persistence"

    log_info "Running persistence verification..."
    "$SCRIPT_DIR/verify-persistence.sh" verify || {
        log_error "Data persistence verification failed"
        ((FAILURES++))
        return 1
    }

    log_info "✓ Data persistence verified"
}

# Function to verify cleanup
verify_cleanup() {
    log_section "Verifying migration job cleanup"

    log_info "Running cleanup verification..."
    "$SCRIPT_DIR/verify-cleanup.sh" after || {
        log_error "Cleanup verification failed"
        ((FAILURES++))
        return 1
    }

    log_info "✓ Migration job cleanup verified"
}

# Function to test idempotency
test_idempotency() {
    log_section "Testing idempotent upgrades"

    log_info "Running second upgrade with same values..."
    helm upgrade "$RELEASE_NAME" "$CHART_PATH" \
        --namespace "$NAMESPACE" \
        --set config.datastoreEngine=postgres \
        --set config.datastore.hostname=postgres.spicedb-test.svc.cluster.local \
        --set config.datastore.port=5432 \
        --set config.datastore.username=spicedb \
        --set config.datastore.password=testpassword123 \
        --set config.datastore.database=spicedb \
        --set config.presharedKey="insecure-default-key-change-in-production" \
        --set image.tag=v1.36.0 \
        --set replicaCount=2 \
        --wait --timeout=10m

    log_info "Waiting for idempotency migration job..."
    kubectl wait --for=condition=complete job \
        -l "app.kubernetes.io/component=migration" \
        -n "$NAMESPACE" \
        --timeout=600s || {
        log_warn "Idempotency migration job failed (may be expected if already at latest)"
    }

    log_info "Verifying data still intact after idempotent upgrade..."
    "$SCRIPT_DIR/verify-persistence.sh" verify || {
        log_error "Data persistence verification failed after idempotent upgrade"
        ((FAILURES++))
        return 1
    }

    log_info "✓ Idempotent upgrade successful"
}

# Main execution
main() {
    log_section "SpiceDB Integration Test Suite"
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Namespace: $NAMESPACE"
    log_info "Release: $RELEASE_NAME"
    log_info "Chart: $CHART_PATH"
    echo ""

    # Phase 1: Setup
    setup_kind_cluster
    deploy_postgres

    # Phase 2: Initial installation
    install_chart
    load_test_data

    # Phase 3: Upgrade testing
    upgrade_chart
    verify_persistence
    verify_cleanup

    # Phase 4: Idempotency testing
    test_idempotency

    # Summary
    log_section "Test Summary"
    if [ $FAILURES -eq 0 ]; then
        log_info "✓ All tests passed successfully!"
        log_info ""
        log_info "Test coverage:"
        log_info "  ✓ Kind cluster setup"
        log_info "  ✓ PostgreSQL deployment"
        log_info "  ✓ SpiceDB chart installation"
        log_info "  ✓ Migration job execution"
        log_info "  ✓ Schema and data loading"
        log_info "  ✓ Helm upgrade with new version"
        log_info "  ✓ Data persistence across upgrades"
        log_info "  ✓ Migration job cleanup (hook-delete-policy)"
        log_info "  ✓ Idempotent migrations"
        return 0
    else
        log_error "✗ $FAILURES test(s) failed"
        return 1
    fi
}

main "$@"
