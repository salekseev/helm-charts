#!/bin/bash
# cleanup-cluster.sh - Clean up test infrastructure after migration tests
# Removes kind cluster and all associated resources

set -euo pipefail

export CLUSTER_NAME="${KIND_CLUSTER_NAME:-spicedb-migration-test}"
export NAMESPACE="spicedb-migration-test"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[CLEANUP]${NC} $1"; }
log_error() { echo -e "${RED}[CLEANUP ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[CLEANUP WARN]${NC} $1"; }
log_debug() { echo -e "${BLUE}[CLEANUP DEBUG]${NC} $1"; }
log_section() { echo -e "${CYAN}[====]${NC} $1 ${CYAN}[====]${NC}"; }

# Clean up resources in namespace
cleanup_namespace() {
    log_section "Cleaning Up Namespace Resources"

    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_info "Namespace $NAMESPACE does not exist, skipping"
        return 0
    fi

    log_info "Deleting Helm releases in $NAMESPACE..."
    helm list -n "$NAMESPACE" -q | while read -r release; do
        log_debug "Uninstalling Helm release: $release"
        helm uninstall "$release" -n "$NAMESPACE" --wait --timeout=2m 2>/dev/null || {
            log_warn "Failed to uninstall $release (may not exist)"
        }
    done

    log_info "Deleting SpiceDBCluster resources..."
    kubectl delete spicedbclusters --all -n "$NAMESPACE" --wait --timeout=2m 2>/dev/null || {
        log_warn "No SpiceDBCluster resources found"
    }

    log_info "Deleting all resources in namespace..."
    kubectl delete all --all -n "$NAMESPACE" --wait --timeout=2m 2>/dev/null || true

    log_info "Namespace resources cleaned up"
}

# Delete kind cluster
delete_cluster() {
    log_section "Deleting Kind Cluster"

    if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_info "Cluster $CLUSTER_NAME does not exist"
        return 0
    fi

    log_info "Deleting kind cluster: $CLUSTER_NAME"
    kind delete cluster --name "$CLUSTER_NAME"

    log_info "Cluster deleted successfully"
}

# Main cleanup function
main() {
    log_section "SpiceDB Migration Test - Cleanup"
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Namespace: $NAMESPACE"
    echo ""

    # Ask for confirmation
    read -p "Are you sure you want to delete cluster $CLUSTER_NAME? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi

    cleanup_namespace
    delete_cluster

    log_section "Cleanup Complete"
    log_info "All test resources have been removed"
}

# Allow force cleanup without confirmation
if [ "${1:-}" = "--force" ] || [ "${1:-}" = "-f" ]; then
    log_info "Force cleanup enabled"
    cleanup_namespace
    delete_cluster
    log_info "Cleanup complete"
    exit 0
fi

main "$@"
