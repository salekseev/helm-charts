#!/bin/bash
# run-all-tests.sh - Run all operator-to-helm migration tests
# Orchestrates test execution with proper cleanup between tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[RUNNER]${NC} $1"; }
log_error() { echo -e "${RED}[RUNNER ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[RUNNER WARN]${NC} $1"; }
log_section() { echo -e "${CYAN}[====]${NC} $1 ${CYAN}[====]${NC}"; }

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Run a single test
run_test() {
    local test_name="$1"
    local test_script="$2"

    ((TOTAL_TESTS++))

    log_section "Running Test: $test_name"

    if "$test_script"; then
        log_info "Test PASSED: $test_name"
        ((PASSED_TESTS++))
        return 0
    else
        log_error "Test FAILED: $test_name"
        ((FAILED_TESTS++))
        return 1
    fi
}

# Cleanup between tests
cleanup_between_tests() {
    log_info "Cleaning up between tests..."

    # Delete any Helm releases
    helm list -n spicedb-migration-test -q 2>/dev/null | while read -r release; do
        helm uninstall "$release" -n spicedb-migration-test --wait --timeout=2m 2>/dev/null || true
    done

    # Delete SpiceDBCluster resources
    kubectl delete spicedbclusters --all -n spicedb-migration-test --wait --timeout=2m 2>/dev/null || true

    # Wait for pods to terminate
    kubectl wait --for=delete pod -l app.kubernetes.io/name=spicedb -n spicedb-migration-test --timeout=2m 2>/dev/null || true

    sleep 5
}

main() {
    log_section "Operator-to-Helm Migration Test Suite"
    echo ""

    # Check if cluster is set up
    if ! kubectl get namespace spicedb-migration-test >/dev/null 2>&1; then
        log_error "Test infrastructure not set up"
        log_info "Run ./setup-cluster.sh first"
        exit 1
    fi

    log_info "Running all migration tests..."
    echo ""

    # Test 1: Configuration Conversion (standalone, no cluster needed)
    run_test "Configuration Conversion" "$SCRIPT_DIR/test-config-conversion.sh"
    echo ""

    # Test 2: Basic Migration
    cleanup_between_tests
    run_test "Basic Migration" "$SCRIPT_DIR/test-basic-migration.sh"
    echo ""

    # Test 3: Secret Migration
    cleanup_between_tests
    run_test "Secret Migration" "$SCRIPT_DIR/test-secret-migration.sh"
    echo ""

    # Test 4: Rollback
    cleanup_between_tests
    run_test "Rollback Procedure" "$SCRIPT_DIR/test-rollback.sh"
    echo ""

    # Final summary
    log_section "Test Suite Summary"
    echo ""
    log_info "Total tests:  $TOTAL_TESTS"
    log_info "Passed:       $PASSED_TESTS"
    if [ $FAILED_TESTS -gt 0 ]; then
        log_error "Failed:       $FAILED_TESTS"
    else
        log_info "Failed:       $FAILED_TESTS"
    fi
    echo ""

    if [ $FAILED_TESTS -eq 0 ]; then
        log_section "All Tests Passed!"
        log_info "Operator-to-Helm migration testing complete"
        log_info ""
        log_info "Migration test suite verified:"
        log_info "  - Configuration conversion works correctly"
        log_info "  - Basic migration preserves functionality"
        log_info "  - Secrets can be migrated and reused"
        log_info "  - Rollback procedure is reliable"
        return 0
    else
        log_section "Some Tests Failed"
        log_error "$FAILED_TESTS test(s) did not pass"
        log_info "Review logs above for details"
        return 1
    fi
}

main "$@"
