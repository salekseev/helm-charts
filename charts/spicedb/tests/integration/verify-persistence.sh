#!/bin/bash
# verify-persistence.sh - Verify SpiceDB schema and relationship data persists across helm upgrades
set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-spicedb-test}"
RELEASE_NAME="${RELEASE_NAME:-spicedb}"
# Use just the release name as the service name matches the release name
SERVICE_NAME="${RELEASE_NAME}"
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

setup_port_forward() {
    log_info "Setting up port-forward to SpiceDB..."
    kubectl port-forward -n "$NAMESPACE" "svc/$SERVICE_NAME" 50051:50051 &
    PORT_FORWARD_PID=$!
    sleep 3  # Wait for port-forward to establish
    log_debug "Port-forward PID: $PORT_FORWARD_PID"
}

stop_port_forward() {
    if [ -n "${PORT_FORWARD_PID:-}" ]; then
        log_debug "Stopping port-forward (PID: $PORT_FORWARD_PID)"
        kill "$PORT_FORWARD_PID" 2>/dev/null || true
        wait "$PORT_FORWARD_PID" 2>/dev/null || true
    fi
}
trap stop_port_forward EXIT

wait_for_spicedb() {
    log_info "Waiting for SpiceDB to be ready..."
    kubectl wait --for=condition=ready pod \
        -l "app.kubernetes.io/name=spicedb" \
        -n "$NAMESPACE" \
        --timeout=300s
    log_info "SpiceDB pods are ready"
}

load_schema() {
    log_info "Loading test schema..."
    if [ ! -f "$SCRIPT_DIR/test-schema.zed" ]; then
        log_error "test-schema.zed not found at $SCRIPT_DIR/test-schema.zed"
        return 1
    fi

    # Use stdin to provide schema to zed command
    kubectl run -n "$NAMESPACE" zed-schema-load --rm -i --restart=Never \
        --image=authzed/zed:latest \
        -- schema write \
        --endpoint "$SERVICE_NAME:50051" \
        --insecure \
        --token "$TOKEN" < "$SCRIPT_DIR/test-schema.zed" || {
        log_error "Failed to load schema"
        return 1
    }

    log_info "Schema loaded successfully"
}

write_test_relationships() {
    log_info "Writing test relationships..."

    # Write each relationship separately since zed doesn't have shell
    local relationships=(
        "document:doc1 owner user:alice"
        "document:doc1 editor user:bob"
        "document:doc1 viewer user:charlie"
        "document:doc2 owner user:alice"
    )

    for rel in "${relationships[@]}"; do
        kubectl run -n "$NAMESPACE" "zed-rel-write-$RANDOM" --rm --attach --restart=Never \
            --image=authzed/zed:latest \
            -- relationship create $rel \
            --endpoint "$SERVICE_NAME:50051" \
            --insecure \
            --token "$TOKEN" || {
            log_error "Failed to write relationship: $rel"
            return 1
        }
    done

    log_info "Test relationships written successfully"
}

check_permission() {
    local resource=$1
    local permission=$2
    local subject=$3
    local expected=$4  # "true" or "false"

    log_debug "Checking: $subject can $permission on $resource (expect: $expected)"

    local pod_name="zed-check-$RANDOM"
    local result

    # Run pod without --attach, then get logs
    kubectl run -n "$NAMESPACE" "$pod_name" --restart=Never \
        --image=authzed/zed:latest \
        -- permission check "$resource" "$permission" "$subject" \
        --endpoint "$SERVICE_NAME:50051" \
        --insecure \
        --token "$TOKEN" > /dev/null 2>&1

    # Wait for pod to complete
    kubectl wait --for=condition=Ready pod/"$pod_name" -n "$NAMESPACE" --timeout=10s > /dev/null 2>&1 || true
    sleep 1

    # Get the logs (actual zed output)
    result=$(kubectl logs "$pod_name" -n "$NAMESPACE" 2>/dev/null || true)

    # Clean up pod
    kubectl delete pod "$pod_name" -n "$NAMESPACE" --wait=false > /dev/null 2>&1 || true

    log_debug "Raw result: '$result'"

    if echo "$result" | grep -q "true"; then
        if [ "$expected" = "true" ]; then
            log_info "checkmark $subject can $permission $resource"
            return 0
        else
            log_error "xmark $subject should NOT be able to $permission $resource"
            return 1
        fi
    else
        if [ "$expected" = "false" ]; then
            log_info "checkmark $subject cannot $permission $resource (expected)"
            return 0
        else
            log_error "xmark $subject should be able to $permission $resource"
            return 1
        fi
    fi
}

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

export_schema() {
    local output_file=$1
    log_info "Exporting schema to $output_file..."

    local pod_name="zed-schema-export-$RANDOM"

    # Run pod without --attach, then get logs
    kubectl run -n "$NAMESPACE" "$pod_name" --restart=Never \
        --image=authzed/zed:latest \
        -- schema read \
        --endpoint "$SERVICE_NAME:50051" \
        --insecure \
        --token "$TOKEN" > /dev/null 2>&1

    # Wait for pod to complete
    kubectl wait --for=condition=Ready pod/"$pod_name" -n "$NAMESPACE" --timeout=10s > /dev/null 2>&1 || true
    sleep 1

    # Get the logs and filter out warning messages
    kubectl logs "$pod_name" -n "$NAMESPACE" 2>/dev/null | \
        grep -v "^{\"level\":\"warn\"" > "$output_file" || {
        log_error "Failed to export schema"
        kubectl delete pod "$pod_name" -n "$NAMESPACE" --wait=false > /dev/null 2>&1 || true
        return 1
    }

    # Clean up pod
    kubectl delete pod "$pod_name" -n "$NAMESPACE" --wait=false > /dev/null 2>&1 || true

    log_debug "Schema exported to $output_file"
}

export_relationships() {
    local output_file=$1
    log_info "Exporting relationships to $output_file..."

    local pod_name="zed-rel-export-$RANDOM"

    # Run pod without --attach, then get logs
    kubectl run -n "$NAMESPACE" "$pod_name" --restart=Never \
        --image=authzed/zed:latest \
        -- relationship read document \
        --endpoint "$SERVICE_NAME:50051" \
        --insecure \
        --token "$TOKEN" > /dev/null 2>&1

    # Wait for pod to complete
    kubectl wait --for=condition=Ready pod/"$pod_name" -n "$NAMESPACE" --timeout=10s > /dev/null 2>&1 || true
    sleep 1

    # Get the logs and filter out warning messages
    kubectl logs "$pod_name" -n "$NAMESPACE" 2>/dev/null | \
        grep -v "^{\"level\":\"warn\"" > "$output_file" || {
        log_error "Failed to export relationships"
        kubectl delete pod "$pod_name" -n "$NAMESPACE" --wait=false > /dev/null 2>&1 || true
        return 1
    }

    # Clean up pod
    kubectl delete pod "$pod_name" -n "$NAMESPACE" --wait=false > /dev/null 2>&1 || true

    log_debug "Relationships exported to $output_file"
}

compare_schemas() {
    log_info "Comparing schemas before and after upgrade..."

    if diff -u "$SCHEMA_BEFORE" "$SCHEMA_AFTER" > /dev/null; then
        log_info "[PASS] Schema unchanged after upgrade"
        return 0
    else
        log_error "[FAIL] Schema changed after upgrade:"
        diff -u "$SCHEMA_BEFORE" "$SCHEMA_AFTER" || true
        return 1
    fi
}

compare_relationships() {
    log_info "Comparing relationships before and after upgrade..."

    # Sort both files before comparison (order may vary)
    sort "$RELATIONSHIPS_BEFORE" > "${RELATIONSHIPS_BEFORE}.sorted"
    sort "$RELATIONSHIPS_AFTER" > "${RELATIONSHIPS_AFTER}.sorted"

    if diff -u "${RELATIONSHIPS_BEFORE}.sorted" "${RELATIONSHIPS_AFTER}.sorted" > /dev/null; then
        log_info "[PASS] Relationships unchanged after upgrade"
        return 0
    else
        log_error "[FAIL] Relationships changed after upgrade:"
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
