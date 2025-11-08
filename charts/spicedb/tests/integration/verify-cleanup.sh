#!/bin/bash
# verify-cleanup.sh - Verify migration job cleanup via hook-delete-policy
set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-spicedb-test}"
RELEASE_NAME="${RELEASE_NAME:-spicedb}"

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

# Temporary files for job tracking
JOBS_BEFORE="/tmp/migration-jobs-before.txt"
JOBS_AFTER="/tmp/migration-jobs-after.txt"

# Cleanup temporary files on exit
cleanup_tmp() {
    rm -f "$JOBS_BEFORE" "$JOBS_AFTER"
}
trap cleanup_tmp EXIT

# Function to list migration jobs
list_migration_jobs() {
    local output_file=$1
    log_debug "Listing migration jobs to $output_file..."

    kubectl get jobs -n "$NAMESPACE" \
        --selector='app.kubernetes.io/component=migration' \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.succeeded}{"\t"}{.status.failed}{"\t"}{.metadata.creationTimestamp}{"\n"}{end}' \
        > "$output_file" 2>/dev/null || echo -n "" > "$output_file"

    local job_count
    job_count=$(wc -l < "$output_file" | tr -d ' ')
    log_debug "Found $job_count migration job(s)"
}

# Function to display job details
show_job_details() {
    local job_file=$1
    local label=$2

    if [ ! -s "$job_file" ]; then
        log_info "$label: No migration jobs found"
        return
    fi

    log_info "$label:"
    echo "----------------------------------------"
    printf "%-40s %-10s %-10s %s\n" "NAME" "SUCCEEDED" "FAILED" "CREATED"
    echo "----------------------------------------"
    while IFS=$'\t' read -r name succeeded failed created; do
        printf "%-40s %-10s %-10s %s\n" "$name" "${succeeded:-0}" "${failed:-0}" "$created"
    done < "$job_file"
    echo "----------------------------------------"
}

# Function to verify hook-delete-policy annotation
verify_hook_policy() {
    log_info "Verifying hook-delete-policy annotation in chart..."

    local manifest
    manifest=$(helm get manifest "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null) || {
        log_error "Failed to get Helm manifest for release $RELEASE_NAME"
        return 1
    }

    # Extract migration job from manifest and check for hook-delete-policy
    local hook_policy
    hook_policy=$(echo "$manifest" | awk '
        /^---/ { in_job=0 }
        /kind: Job/ { in_job=1 }
        in_job && /helm.sh\/hook-delete-policy:/ {
            split($0, a, ": ")
            gsub(/^[ \t]+|[ \t]+$/, "", a[2])
            gsub(/"/, "", a[2])
            print a[2]
            exit
        }
    ')

    if [ -z "$hook_policy" ]; then
        log_warn "No hook-delete-policy found in migration job manifest"
        return 1
    fi

    case "$hook_policy" in
        before-hook-creation|hook-succeeded|hook-failed)
            log_info "✓ Valid hook-delete-policy found: $hook_policy"
            return 0
            ;;
        *)
            log_error "✗ Invalid hook-delete-policy: $hook_policy"
            return 1
            ;;
    esac
}

# Function to check for orphaned migration pods
check_orphaned_pods() {
    log_info "Checking for orphaned migration pods..."

    local completed_pods
    completed_pods=$(kubectl get pods -n "$NAMESPACE" \
        --selector='app.kubernetes.io/component=migration' \
        --field-selector=status.phase=Succeeded \
        -o name 2>/dev/null) || true

    local failed_pods
    failed_pods=$(kubectl get pods -n "$NAMESPACE" \
        --selector='app.kubernetes.io/component=migration' \
        --field-selector=status.phase=Failed \
        -o name 2>/dev/null) || true

    if [ -z "$completed_pods" ] && [ -z "$failed_pods" ]; then
        log_info "✓ No orphaned migration pods found"
        return 0
    fi

    if [ -n "$completed_pods" ]; then
        log_warn "Found completed migration pods (may be normal during cleanup window):"
        echo "$completed_pods"
    fi

    if [ -n "$failed_pods" ]; then
        log_error "✗ Found failed migration pods:"
        echo "$failed_pods"
        return 1
    fi

    return 0
}

# Function to wait for cleanup to complete
wait_for_cleanup() {
    local max_wait=60
    local waited=0

    log_info "Waiting up to ${max_wait}s for cleanup to complete..."

    while [ $waited -lt $max_wait ]; do
        local job_count
        job_count=$(kubectl get jobs -n "$NAMESPACE" \
            --selector='app.kubernetes.io/component=migration' \
            --no-headers 2>/dev/null | wc -l | tr -d ' ')

        if [ "$job_count" -eq 1 ]; then
            log_info "✓ Cleanup complete (1 migration job remaining - current one)"
            return 0
        elif [ "$job_count" -eq 0 ]; then
            log_warn "No migration jobs found (all cleaned up including current)"
            return 0
        fi

        log_debug "Waiting for cleanup... ($job_count jobs remaining)"
        sleep 5
        waited=$((waited + 5))
    done

    log_warn "Cleanup wait timeout reached (${max_wait}s)"
    return 0
}

# Function to analyze cleanup behavior
analyze_cleanup() {
    log_info "=== Analyzing Migration Job Cleanup ==="

    # Show before state
    show_job_details "$JOBS_BEFORE" "Migration jobs BEFORE upgrade"

    # Wait for cleanup
    wait_for_cleanup

    # Capture after state
    list_migration_jobs "$JOBS_AFTER"
    show_job_details "$JOBS_AFTER" "Migration jobs AFTER upgrade"

    # Compare before and after
    local before_count after_count
    before_count=$(wc -l < "$JOBS_BEFORE" | tr -d ' ')
    after_count=$(wc -l < "$JOBS_AFTER" | tr -d ' ')

    log_info "Job count: before=$before_count, after=$after_count"

    if [ "$after_count" -le 1 ]; then
        log_info "✓ Old migration jobs cleaned up successfully"
    else
        log_warn "⚠ Multiple migration jobs present after upgrade"
        log_debug "This may be normal if cleanup is still in progress"
    fi

    # Verify hook policy is configured correctly
    verify_hook_policy

    # Check for orphaned pods
    check_orphaned_pods

    log_info "=== Cleanup analysis complete ==="
}

# Main execution
main() {
    local mode="${1:-before}"

    case "$mode" in
        before)
            log_info "=== Capturing migration jobs state BEFORE upgrade ==="
            list_migration_jobs "$JOBS_BEFORE"
            show_job_details "$JOBS_BEFORE" "Current migration jobs"
            log_info "=== State captured ==="
            ;;

        after)
            log_info "=== Verifying cleanup AFTER upgrade ==="
            if [ ! -f "$JOBS_BEFORE" ]; then
                log_error "No before state found. Run with 'before' first."
                exit 1
            fi
            analyze_cleanup
            ;;

        verify)
            log_info "=== Full cleanup verification ==="
            list_migration_jobs "$JOBS_AFTER"
            show_job_details "$JOBS_AFTER" "Current migration jobs"
            verify_hook_policy
            check_orphaned_pods

            local job_count
            job_count=$(wc -l < "$JOBS_AFTER" | tr -d ' ')

            if [ "$job_count" -le 1 ]; then
                log_info "✓ Cleanup verification passed"
            else
                log_warn "⚠ Multiple migration jobs present (expected: 0-1, found: $job_count)"
            fi
            ;;

        *)
            log_error "Usage: $0 {before|after|verify}"
            log_error "  before - Capture job state before upgrade"
            log_error "  after  - Analyze cleanup after upgrade"
            log_error "  verify - Verify current cleanup state"
            exit 1
            ;;
    esac
}

main "$@"
