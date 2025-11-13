#!/bin/bash
set -euo pipefail

export CLUSTER_NAME="${KIND_CLUSTER_NAME:-spicedb-test}"
export NAMESPACE="spicedb-test"
export RELEASE_NAME="${HELM_RELEASE_NAME:-spicedb}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_PATH="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"

SPICEDB_INITIAL_VERSION="${SPICEDB_INITIAL_VERSION:-v1.44.4}"
SPICEDB_UPGRADE_VERSION="${SPICEDB_UPGRADE_VERSION:-v1.46.2}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }
log_section() { echo -e "${CYAN}[====]${NC} $1 ${CYAN}[====]${NC}"; }

FAILURES=0

cleanup() {
    local exit_code=$?

    if [ $exit_code -ne 0 ] || [ $FAILURES -gt 0 ]; then
        log_error "Test failed with exit code $exit_code and $FAILURES failure(s)"
        capture_logs
    fi

    if [ "${SKIP_CLEANUP:-false}" != "true" ]; then
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

capture_logs() {
    log_info "Capturing logs to $LOG_DIR..."
    mkdir -p "$LOG_DIR"

    for pod in $(kubectl get pods -n "$NAMESPACE" -o name 2>/dev/null || true); do
        pod_name=$(echo "$pod" | cut -d/ -f2)
        log_debug "Capturing logs for $pod_name"
        kubectl logs -n "$NAMESPACE" "$pod" --all-containers=true \
            > "$LOG_DIR/${pod_name}.log" 2>&1 || true
    done

    kubectl describe pods -n "$NAMESPACE" > "$LOG_DIR/pods-describe.txt" 2>&1 || true
    kubectl describe jobs -n "$NAMESPACE" > "$LOG_DIR/jobs-describe.txt" 2>&1 || true
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' \
        > "$LOG_DIR/events.txt" 2>&1 || true
    helm get values "$RELEASE_NAME" -n "$NAMESPACE" \
        > "$LOG_DIR/helm-values.yaml" 2>&1 || true
    helm get manifest "$RELEASE_NAME" -n "$NAMESPACE" \
        > "$LOG_DIR/helm-manifest.yaml" 2>&1 || true

    log_info "Logs captured in $LOG_DIR"
    ls -lh "$LOG_DIR"
}

setup_kind_cluster() {
    log_section "Setting up Kind cluster"

    if kubectl cluster-info > /dev/null 2>&1; then
        log_info "Kubernetes cluster already available, skipping Kind setup"
        log_info "Using existing cluster context: $(kubectl config current-context)"

        log_info "Waiting for cluster to be ready..."
        kubectl wait --for=condition=Ready nodes --all --timeout=120s
        log_info "[PASS] Cluster ready"
        return 0
    fi

    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_warn "Cluster $CLUSTER_NAME already exists, deleting..."
        kind delete cluster --name "$CLUSTER_NAME"
    fi

    log_info "Creating Kind cluster: $CLUSTER_NAME"
    kind create cluster --name "$CLUSTER_NAME" --config="$SCRIPT_DIR/kind-cluster-config.yaml"

    kubectl config use-context "kind-${CLUSTER_NAME}"

    log_info "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=120s

    log_info "[PASS] Kind cluster ready"
}

deploy_postgres() {
    log_section "Deploying PostgreSQL"

    log_info "Applying PostgreSQL manifests..."
    kubectl apply -f "$SCRIPT_DIR/postgres-deployment.yaml"

    log_info "Waiting for PostgreSQL StatefulSet to be ready..."
    kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
        statefulset/postgres \
        -n "$NAMESPACE" \
        --timeout=300s

    log_info "Verifying PostgreSQL connectivity..."
    local max_attempts=10
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        log_debug "Attempt $attempt/$max_attempts to connect to PostgreSQL..."

        if kubectl exec -n "$NAMESPACE" postgres-0 -- \
            psql -U spicedb -d spicedb -c "SELECT 1" > /dev/null 2>&1; then
            log_info "[PASS] PostgreSQL is ready and accepting connections"
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

    log_info "Checking for existing Helm releases..."
    if helm list -A 2>/dev/null | grep -q "^${RELEASE_NAME}[[:space:]]"; then
        EXISTING_NS=$(helm list -A | grep "^${RELEASE_NAME}[[:space:]]" | awk '{print $2}')
        log_warn "Found existing release '$RELEASE_NAME' in namespace '$EXISTING_NS', uninstalling..."
        helm uninstall "$RELEASE_NAME" -n "$EXISTING_NS" --wait --timeout=2m || true
        sleep 5
    fi

    if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
        log_info "Namespace $NAMESPACE exists, cleaning up leftover resources..."
        kubectl delete jobs -n "$NAMESPACE" \
            -l "app.kubernetes.io/name=spicedb" \
            --ignore-not-found=true --wait=true --timeout=60s || true
        sleep 2
    fi

    log_info "Installing Helm chart: $RELEASE_NAME"
    helm install "$RELEASE_NAME" "$CHART_PATH" \
        --namespace "$NAMESPACE" \
        --set replicaCount=1 \
        --set dispatch.enabled=false \
        --set config.autogenerateSecret=true \
        --set config.datastoreEngine=postgres \
        --set config.datastore.hostname=postgres.spicedb-test.svc.cluster.local \
        --set config.datastore.port=5432 \
        --set config.datastore.username=spicedb \
        --set config.datastore.password=testpassword123 \
        --set config.datastore.database=spicedb \
        --set config.presharedKey="insecure-default-key-change-in-production" \
        --set image.tag=${SPICEDB_INITIAL_VERSION} \
        --wait --timeout=10m || {
        log_error "Helm install failed"
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' || true
        kubectl get pods -n "$NAMESPACE" || true
        return 1
    }

    log_info "[PASS] Helm install completed successfully (migration succeeded)"

    log_info "Verifying SpiceDB pods are ready..."
    kubectl wait --for=condition=ready pod \
        -l "app.kubernetes.io/name=spicedb" \
        -n "$NAMESPACE" \
        --timeout=300s

    log_info "Waiting for post-install hooks (cleanup job) to complete..."
    sleep 5  # Give hooks time to start
    kubectl wait --for=condition=complete job \
        -l "app.kubernetes.io/component=migration-cleanup" \
        -n "$NAMESPACE" \
        --timeout=120s || {
        log_warn "Cleanup job wait timed out or failed (non-fatal)"
    }

    log_info "[PASS] SpiceDB chart installed successfully"
}

load_test_data() {
    log_section "Loading test schema and data"

    log_info "Running initial data load..."
    "$SCRIPT_DIR/verify-persistence.sh" initial || {
        log_error "Failed to load initial test data"
        ((FAILURES++))
        return 1
    }

    log_info "[PASS] Test data loaded successfully"
}

upgrade_chart() {
    log_section "Performing Helm upgrade"

    log_info "Capturing pre-upgrade migration job state..."
    "$SCRIPT_DIR/verify-cleanup.sh" before || {
        log_warn "Failed to capture pre-upgrade state"
    }

    log_info "Upgrading Helm chart to new version with HA+dispatch enabled..."
    helm upgrade "$RELEASE_NAME" "$CHART_PATH" \
        --namespace "$NAMESPACE" \
        --set replicaCount=2 \
        --set dispatch.enabled=true \
        --set config.autogenerateSecret=true \
        --set config.datastoreEngine=postgres \
        --set config.datastore.hostname=postgres.spicedb-test.svc.cluster.local \
        --set config.datastore.port=5432 \
        --set config.datastore.username=spicedb \
        --set config.datastore.password=testpassword123 \
        --set config.datastore.database=spicedb \
        --set config.presharedKey="insecure-default-key-change-in-production" \
        --set image.tag=${SPICEDB_UPGRADE_VERSION} \
        --set probes.startup.failureThreshold=60 \
        --wait --timeout=15m || {
        log_error "Helm upgrade failed"
        kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' || true
        kubectl get pods -n "$NAMESPACE" || true
        return 1
    }

    log_info "[PASS] Helm upgrade completed successfully (migration succeeded)"

    log_info "Verifying SpiceDB pods are ready after upgrade..."
    kubectl wait --for=condition=ready pod \
        -l "app.kubernetes.io/name=spicedb" \
        -n "$NAMESPACE" \
        --timeout=300s

    log_info "Waiting for post-upgrade hooks (cleanup job) to complete..."
    sleep 5  # Give hooks time to start
    kubectl wait --for=condition=complete job \
        -l "app.kubernetes.io/component=migration-cleanup" \
        -n "$NAMESPACE" \
        --timeout=120s || {
        log_warn "Cleanup job wait timed out or failed (non-fatal)"
    }

    log_info "[PASS] Helm upgrade and migration verification complete"
}

verify_persistence() {
    log_section "Verifying data persistence"

    log_info "Running persistence verification..."
    "$SCRIPT_DIR/verify-persistence.sh" verify || {
        log_error "Data persistence verification failed"
        ((FAILURES++))
        return 1
    }

    log_info "[PASS] Data persistence verified"
}

verify_cleanup() {
    log_section "Verifying migration job cleanup"

    log_info "Running cleanup verification..."
    "$SCRIPT_DIR/verify-cleanup.sh" after || {
        log_error "Cleanup verification failed"
        ((FAILURES++))
        return 1
    }

    log_info "[PASS] Migration job cleanup verified"
}

test_idempotency() {
    log_section "Testing idempotent upgrades"

    log_info "Running second upgrade with same values..."
    helm upgrade "$RELEASE_NAME" "$CHART_PATH" \
        --namespace "$NAMESPACE" \
        --set replicaCount=2 \
        --set dispatch.enabled=true \
        --set config.autogenerateSecret=true \
        --set config.datastoreEngine=postgres \
        --set config.datastore.hostname=postgres.spicedb-test.svc.cluster.local \
        --set config.datastore.port=5432 \
        --set config.datastore.username=spicedb \
        --set config.datastore.password=testpassword123 \
        --set config.datastore.database=spicedb \
        --set config.presharedKey="insecure-default-key-change-in-production" \
        --set image.tag=${SPICEDB_UPGRADE_VERSION} \
        --set probes.startup.failureThreshold=60 \
        --wait --timeout=15m

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

    log_info "[PASS] Idempotent upgrade successful"
}

main() {
    log_section "SpiceDB Integration Test Suite"
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Namespace: $NAMESPACE"
    log_info "Release: $RELEASE_NAME"
    log_info "Chart: $CHART_PATH"
    echo ""

    setup_kind_cluster
    deploy_postgres

    install_chart
    load_test_data

    upgrade_chart
    verify_persistence
    verify_cleanup

    test_idempotency

    log_section "Test Summary"
    if [ $FAILURES -eq 0 ]; then
        log_info "[PASS] All tests passed successfully!"
        log_info ""
        log_info "Test coverage:"
        log_info "  [PASS] Kind cluster setup"
        log_info "  [PASS] PostgreSQL deployment"
        log_info "  [PASS] SpiceDB chart installation"
        log_info "  [PASS] Migration job execution"
        log_info "  [PASS] Schema and data loading"
        log_info "  [PASS] Helm upgrade with new version"
        log_info "  [PASS] Data persistence across upgrades"
        log_info "  [PASS] Migration job cleanup (hook-delete-policy)"
        log_info "  [PASS] Idempotent migrations"
        return 0
    else
        log_error "[FAIL] $FAILURES test(s) failed"
        return 1
    fi
}

main "$@"
