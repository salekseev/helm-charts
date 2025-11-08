#!/bin/bash
# verify-persistence.sh - Verify SpiceDB schema and relationship data persists across helm upgrades
set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-spicedb-test}"
RELEASE_NAME="${RELEASE_NAME:-spicedb}"
ENDPOINT="${ENDPOINT:-localhost:50051}"
TOKEN="${TOKEN:-insecure-default-key-change-in-production}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# Temporary files for comparisons
SCHEMA_BEFORE="/tmp/schema-before.zed"
SCHEMA_AFTER="/tmp/schema-after.zed"
RELATIONSHIPS_BEFORE="/tmp/relationships-before.txt"
RELATIONSHIPS_AFTER="/tmp/relationships-after.txt"

# Cleanup temporary files on exit
cleanup_tmp() {
    rm -f "$SCHEMA_BEFORE" "$SCHEMA_AFTER" "$RELATIONSHIPS_BEFORE" "$RELATIONSHIPS_AFTER"
}
trap cleanup_tmp EXIT

# Function to connect to SpiceDB using port-forward
setup_port_forward() {
    log_info "Setting up port-forward to SpiceDB..."
    kubectl port-forward -n "$NAMESPACE" "svc/$RELEASE_NAME-spicedb" 50051:50051 &
    PORT_FORWARD_PID=$!
    sleep 3  # Wait for port-forward to establish
    log_debug "Port-forward PID: $PORT_FORWARD_PID"
}

# Function to stop port-forward
stop_port_forward() {
    if [ -n "${PORT_FORWARD_PID:-}" ]; then
        log_debug "Stopping port-forward (PID: $PORT_FORWARD_PID)"
        kill "$PORT_FORWARD_PID" 2>/dev/null || true
        wait "$PORT_FORWARD_PID" 2>/dev/null || true
    fi
}
trap stop_port_forward EXIT

# Function to wait for SpiceDB to be ready
wait_for_spicedb() {
    log_info "Waiting for SpiceDB to be ready..."
    kubectl wait --for=condition=ready pod \
        -l "app.kubernetes.io/name=spicedb" \
        -n "$NAMESPACE" \
        --timeout=300s
    log_info "SpiceDB pods are ready"
}

# Function to load schema
load_schema() {
    log_info "Loading test schema..."
    if [ ! -f "$SCRIPT_DIR/test-schema.zed" ]; then
        log_error "test-schema.zed not found at $SCRIPT_DIR/test-schema.zed"
        return 1
    fi

    kubectl run -n "$NAMESPACE" zed-schema-load --rm -i --restart=Never \
        --image=authzed/zed:latest \
        --command -- sh -c "cat <<'EOFSCHEMA' | zed schema write --endpoint $RELEASE_NAME-spicedb:50051 --insecure --token $TOKEN
$(cat "$SCRIPT_DIR/test-schema.zed")
EOFSCHEMA" || {
        log_error "Failed to load schema"
        return 1
    }

    log_info "Schema loaded successfully"
}

# Function to write test relationships
write_test_relationships() {
    log_info "Writing test relationships..."

    kubectl run -n "$NAMESPACE" zed-relationships-write --rm -i --restart=Never \
        --image=authzed/zed:latest \
        --command -- sh -c "
set -e
zed relationship create document:doc1 owner user:alice --endpoint $RELEASE_NAME-spicedb:50051 --insecure --token $TOKEN
zed relationship create document:doc1 editor user:bob --endpoint $RELEASE_NAME-spicedb:50051 --insecure --token $TOKEN
zed relationship create document:doc1 viewer user:charlie --endpoint $RELEASE_NAME-spicedb:50051 --insecure --token $TOKEN
zed relationship create document:doc2 owner user:alice --endpoint $RELEASE_NAME-spicedb:50051 --insecure --token $TOKEN
echo 'All relationships created successfully'
" || {
        log_error "Failed to write relationships"
        return 1
    }

    log_info "Test relationships written successfully"
}

# Function to check permissions
check_permission() {
    local resource=$1
    local permission=$2
    local subject=$3
    local expected=$4  # "true" or "false"

    log_debug "Checking: $subject can $permission on $resource (expect: $expected)"

    local result
    result=$(kubectl run -n "$NAMESPACE" zed-check-$RANDOM --rm -i --restart=Never \
        --image=authzed/zed:latest \
        --command -- sh -c "
        zed permission check $resource $permission $subject \
            --endpoint $RELEASE_NAME-spicedb:50051 \
            --insecure \
            --token $TOKEN" 2>&1) || true

    if echo "$result" | grep -q "true"; then
        if [ "$expected" = "true" ]; then
            log_info "✓ $subject can $permission $resource"
            return 0
        else
            log_error "✗ $subject should NOT be able to $permission $resource"
            return 1
        fi
    else
        if [ "$expected" = "false" ]; then
            log_info "✓ $subject cannot $permission $resource (expected)"
            return 0
        else
            log_error "✗ $subject should be able to $permission $resource"
            return 1
        fi
    fi
}

# Function to run all permission checks
run_permission_checks() {
    log_info "Running permission checks..."
    local failed=0

    # Alice is owner of doc1 - should have all permissions
    check_permission "document:doc1" "view" "user:alice" "true" || ((failed++))
    check_permission "document:doc1" "edit" "user:alice" "true" || ((failed++))
    check_permission "document:doc1" "delete" "user:alice" "true" || ((failed++))

    # Bob is editor of doc1 - can view and edit but not delete
    check_permission "document:doc1" "view" "user:bob" "true" || ((failed++))
    check_permission "document:doc1" "edit" "user:bob" "true" || ((failed++))
    check_permission "document:doc1" "delete" "user:bob" "false" || ((failed++))

    # Charlie is viewer of doc1 - can only view
    check_permission "document:doc1" "view" "user:charlie" "true" || ((failed++))
    check_permission "document:doc1" "edit" "user:charlie" "false" || ((failed++))
    check_permission "document:doc1" "delete" "user:charlie" "false" || ((failed++))

    # Bob and Charlie have no access to doc2
    check_permission "document:doc2" "view" "user:bob" "false" || ((failed++))
    check_permission "document:doc2" "edit" "user:charlie" "false" || ((failed++))

    if [ $failed -gt 0 ]; then
        log_error "Permission checks failed: $failed errors"
        return 1
    fi

    log_info "All permission checks passed!"
    return 0
}

# Function to export schema
export_schema() {
    local output_file=$1
    log_info "Exporting schema to $output_file..."

    kubectl run -n "$NAMESPACE" zed-schema-export-$RANDOM --rm -i --restart=Never \
        --image=authzed/zed:latest \
        --command -- sh -c "
        zed schema read \
            --endpoint $RELEASE_NAME-spicedb:50051 \
            --insecure \
            --token $TOKEN" > "$output_file" 2>/dev/null || {
        log_error "Failed to export schema"
        return 1
    }

    log_debug "Schema exported to $output_file"
}

# Function to export relationships
export_relationships() {
    local output_file=$1
    log_info "Exporting relationships to $output_file..."

    kubectl run -n "$NAMESPACE" zed-rel-export-$RANDOM --rm -i --restart=Never \
        --image=authzed/zed:latest \
        --command -- sh -c "
        zed relationship read document --endpoint $RELEASE_NAME-spicedb:50051 --insecure --token $TOKEN" \
        > "$output_file" 2>/dev/null || {
        log_error "Failed to export relationships"
        return 1
    }

    log_debug "Relationships exported to $output_file"
}

# Function to compare schemas
compare_schemas() {
    log_info "Comparing schemas before and after upgrade..."

    if diff -u "$SCHEMA_BEFORE" "$SCHEMA_AFTER" > /dev/null; then
        log_info "✓ Schema unchanged after upgrade"
        return 0
    else
        log_error "✗ Schema changed after upgrade:"
        diff -u "$SCHEMA_BEFORE" "$SCHEMA_AFTER" || true
        return 1
    fi
}

# Function to compare relationships
compare_relationships() {
    log_info "Comparing relationships before and after upgrade..."

    # Sort both files before comparison (order may vary)
    sort "$RELATIONSHIPS_BEFORE" > "${RELATIONSHIPS_BEFORE}.sorted"
    sort "$RELATIONSHIPS_AFTER" > "${RELATIONSHIPS_AFTER}.sorted"

    if diff -u "${RELATIONSHIPS_BEFORE}.sorted" "${RELATIONSHIPS_AFTER}.sorted" > /dev/null; then
        log_info "✓ Relationships unchanged after upgrade"
        return 0
    else
        log_error "✗ Relationships changed after upgrade:"
        diff -u "${RELATIONSHIPS_BEFORE}.sorted" "${RELATIONSHIPS_AFTER}.sorted" || true
        return 1
    fi
}

# Main execution
main() {
    local mode="${1:-initial}"

    case "$mode" in
        initial)
            log_info "=== Initial Setup: Loading schema and test data ==="
            wait_for_spicedb
            load_schema
            write_test_relationships
            log_info "Waiting 5 seconds for data to propagate..."
            sleep 5
            run_permission_checks
            export_schema "$SCHEMA_BEFORE"
            export_relationships "$RELATIONSHIPS_BEFORE"
            log_info "=== Initial setup complete ==="
            ;;

        verify)
            log_info "=== Verifying Data Persistence After Upgrade ==="
            wait_for_spicedb
            log_info "Waiting 5 seconds for pods to stabilize..."
            sleep 5
            run_permission_checks
            export_schema "$SCHEMA_AFTER"
            export_relationships "$RELATIONSHIPS_AFTER"
            compare_schemas
            compare_relationships
            log_info "=== Persistence verification complete ==="
            ;;

        *)
            log_error "Usage: $0 {initial|verify}"
            log_error "  initial - Load schema and test data"
            log_error "  verify  - Verify data persisted after upgrade"
            exit 1
            ;;
    esac
}

main "$@"
