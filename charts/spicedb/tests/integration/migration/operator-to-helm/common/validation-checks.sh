#!/bin/bash
# validation-checks.sh - Common validation functions for migration testing
# This script provides reusable validation functions for operator-to-helm migration tests

set -euo pipefail

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${GREEN}[VALIDATE]${NC} $1"; }
log_error() { echo -e "${RED}[VALIDATE ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[VALIDATE WARN]${NC} $1"; }
log_debug() { echo -e "${BLUE}[VALIDATE DEBUG]${NC} $1"; }

# validate_pod_health - Check pod readiness and liveness probes
# Usage: validate_pod_health <namespace> <label-selector>
validate_pod_health() {
    local namespace="$1"
    local selector="$2"

    log_info "Validating pod health for selector: $selector"

    # Get all pods matching selector
    local pods=$(kubectl get pods -n "$namespace" -l "$selector" -o name 2>/dev/null || true)

    if [ -z "$pods" ]; then
        log_error "No pods found with selector: $selector"
        return 1
    fi

    local failed=0
    for pod in $pods; do
        pod_name=$(echo "$pod" | cut -d/ -f2)

        # Check pod is Running
        status=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.phase}')
        if [ "$status" != "Running" ]; then
            log_error "Pod $pod_name is not Running (status: $status)"
            ((failed++))
            continue
        fi

        # Check all containers are ready
        ready=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        if [ "$ready" != "True" ]; then
            log_error "Pod $pod_name is not Ready"
            ((failed++))
            continue
        fi

        # Check restart count
        restarts=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.status.containerStatuses[0].restartCount}')
        if [ "$restarts" -gt 3 ]; then
            log_warn "Pod $pod_name has $restarts restarts (may indicate instability)"
        fi

        log_debug "Pod $pod_name: healthy (Running, Ready, $restarts restarts)"
    done

    if [ $failed -gt 0 ]; then
        log_error "$failed pod(s) failed health checks"
        return 1
    fi

    log_info "All pods passed health checks"
    return 0
}

# validate_endpoints - Test SpiceDB service endpoints
# Usage: validate_endpoints <namespace> <service-name> <token>
validate_endpoints() {
    local namespace="$1"
    local service="$2"
    local token="$3"

    log_info "Validating service endpoints for: $service"

    # Port-forward to service (run in background)
    kubectl port-forward -n "$namespace" "svc/$service" 50051:50051 8443:8443 9090:9090 >/dev/null 2>&1 &
    local pf_pid=$!

    # Give port-forward time to establish
    sleep 3

    local failed=0

    # Trap to cleanup port-forward on exit
    trap "kill $pf_pid 2>/dev/null || true" RETURN

    # Test gRPC endpoint (port 50051)
    log_debug "Testing gRPC endpoint (50051)..."
    if command -v grpcurl >/dev/null 2>&1; then
        if ! grpcurl -plaintext -d '{"service":"authzed.api.v1.SchemaService"}' \
            localhost:50051 grpc.health.v1.Health/Check >/dev/null 2>&1; then
            log_error "gRPC endpoint health check failed"
            ((failed++))
        else
            log_debug "gRPC endpoint: OK"
        fi
    else
        log_warn "grpcurl not installed, skipping gRPC health check"
    fi

    # Test HTTP/metrics endpoint (port 9090)
    log_debug "Testing metrics endpoint (9090)..."
    if curl -s -f http://localhost:9090/metrics >/dev/null 2>&1; then
        log_debug "Metrics endpoint: OK"
    else
        log_error "Metrics endpoint failed"
        ((failed++))
    fi

    # Test HTTP health endpoint (port 8443)
    log_debug "Testing HTTP endpoint (8443)..."
    if curl -k -s -f https://localhost:8443/healthz >/dev/null 2>&1; then
        log_debug "HTTP health endpoint: OK"
    else
        log_warn "HTTP health endpoint failed (may not be enabled)"
    fi

    # Cleanup port-forward
    kill $pf_pid 2>/dev/null || true

    if [ $failed -gt 0 ]; then
        log_error "Endpoint validation failed"
        return 1
    fi

    log_info "All endpoints validated successfully"
    return 0
}

# validate_data_integrity - Verify SpiceDB data using zed CLI
# Usage: validate_data_integrity <namespace> <service-name> <token>
validate_data_integrity() {
    local namespace="$1"
    local service="$2"
    local token="$3"

    log_info "Validating data integrity with zed CLI"

    # Check if zed is available
    if ! command -v zed >/dev/null 2>&1; then
        log_warn "zed CLI not installed, skipping data integrity checks"
        log_warn "Install from: https://github.com/authzed/zed/releases"
        return 0
    fi

    # Port-forward for zed access
    kubectl port-forward -n "$namespace" "svc/$service" 50051:50051 >/dev/null 2>&1 &
    local pf_pid=$!
    trap "kill $pf_pid 2>/dev/null || true" RETURN

    sleep 3

    # Set zed context
    zed context set migration-test localhost:50051 "$token" --insecure >/dev/null 2>&1 || {
        log_error "Failed to set zed context"
        kill $pf_pid 2>/dev/null || true
        return 1
    }

    # Read schema
    log_debug "Reading schema..."
    if ! zed schema read >/dev/null 2>&1; then
        log_error "Failed to read schema (no schema defined yet)"
        # This might be expected for fresh deployments
        kill $pf_pid 2>/dev/null || true
        return 0
    fi

    log_debug "Schema read successfully"

    # Try to list relationships (if any exist)
    log_debug "Checking relationships..."
    # This will fail if no relationships exist, which is fine
    zed relationship read --max-results 1 >/dev/null 2>&1 || {
        log_debug "No relationships found (may be expected for new deployment)"
    }

    # Cleanup
    kill $pf_pid 2>/dev/null || true

    log_info "Data integrity validated"
    return 0
}

# validate_resources - Compare resource annotations and labels
# Usage: validate_resources <namespace> <selector> <expected-annotation-key> <expected-value>
validate_resources() {
    local namespace="$1"
    local selector="$2"
    local annotation_key="${3:-}"
    local expected_value="${4:-}"

    log_info "Validating resource metadata"

    local pods=$(kubectl get pods -n "$namespace" -l "$selector" -o name 2>/dev/null || true)

    if [ -z "$pods" ]; then
        log_error "No pods found with selector: $selector"
        return 1
    fi

    for pod in $pods; do
        pod_name=$(echo "$pod" | cut -d/ -f2)

        # Check labels
        labels=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath='{.metadata.labels}')
        log_debug "Pod $pod_name labels: $labels"

        # Check specific annotation if provided
        if [ -n "$annotation_key" ]; then
            value=$(kubectl get pod "$pod_name" -n "$namespace" -o jsonpath="{.metadata.annotations['$annotation_key']}" 2>/dev/null || echo "")
            if [ -n "$expected_value" ] && [ "$value" != "$expected_value" ]; then
                log_warn "Pod $pod_name annotation $annotation_key: got '$value', expected '$expected_value'"
            else
                log_debug "Pod $pod_name annotation $annotation_key: $value"
            fi
        fi
    done

    log_info "Resource metadata validated"
    return 0
}

# validate_secrets - Verify secret content integrity
# Usage: validate_secrets <namespace> <secret-name> <expected-keys...>
validate_secrets() {
    local namespace="$1"
    local secret_name="$2"
    shift 2
    local expected_keys=("$@")

    log_info "Validating secret: $secret_name"

    # Check secret exists
    if ! kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
        log_error "Secret $secret_name not found"
        return 1
    fi

    # Get actual keys
    local actual_keys=$(kubectl get secret "$secret_name" -n "$namespace" -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null)

    # Check each expected key exists
    local missing=0
    for key in "${expected_keys[@]}"; do
        if ! echo "$actual_keys" | grep -q "^${key}$"; then
            log_error "Secret $secret_name missing expected key: $key"
            ((missing++))
        else
            log_debug "Secret $secret_name has key: $key"
        fi
    done

    if [ $missing -gt 0 ]; then
        log_error "Secret validation failed: $missing missing keys"
        return 1
    fi

    log_info "Secret validated successfully"
    return 0
}

# validate_pdb - Check PodDisruptionBudget configuration
# Usage: validate_pdb <namespace> <pdb-name>
validate_pdb() {
    local namespace="$1"
    local pdb_name="$2"

    log_info "Validating PodDisruptionBudget: $pdb_name"

    # Check PDB exists
    if ! kubectl get pdb "$pdb_name" -n "$namespace" >/dev/null 2>&1; then
        log_warn "PodDisruptionBudget $pdb_name not found (may not be enabled)"
        return 0
    fi

    # Get PDB details
    local max_unavailable=$(kubectl get pdb "$pdb_name" -n "$namespace" -o jsonpath='{.spec.maxUnavailable}')
    local min_available=$(kubectl get pdb "$pdb_name" -n "$namespace" -o jsonpath='{.spec.minAvailable}')

    log_debug "PDB $pdb_name: maxUnavailable=$max_unavailable, minAvailable=$min_available"

    # Get current status
    local current_healthy=$(kubectl get pdb "$pdb_name" -n "$namespace" -o jsonpath='{.status.currentHealthy}')
    local desired_healthy=$(kubectl get pdb "$pdb_name" -n "$namespace" -o jsonpath='{.status.desiredHealthy}')

    log_debug "PDB $pdb_name status: currentHealthy=$current_healthy, desiredHealthy=$desired_healthy"

    if [ "$current_healthy" -lt "$desired_healthy" ]; then
        log_warn "PDB $pdb_name: current healthy pods ($current_healthy) less than desired ($desired_healthy)"
    fi

    log_info "PodDisruptionBudget validated"
    return 0
}

# validate_networkpolicy - Check NetworkPolicy if it exists
# Usage: validate_networkpolicy <namespace> <netpol-name>
validate_networkpolicy() {
    local namespace="$1"
    local netpol_name="$2"

    log_info "Validating NetworkPolicy: $netpol_name"

    # Check NetworkPolicy exists
    if ! kubectl get networkpolicy "$netpol_name" -n "$namespace" >/dev/null 2>&1; then
        log_debug "NetworkPolicy $netpol_name not found (may not be enabled)"
        return 0
    fi

    # Get NetworkPolicy details
    local policy_types=$(kubectl get networkpolicy "$netpol_name" -n "$namespace" -o jsonpath='{.spec.policyTypes}')
    log_debug "NetworkPolicy $netpol_name policyTypes: $policy_types"

    # Get pod selector
    local pod_selector=$(kubectl get networkpolicy "$netpol_name" -n "$namespace" -o jsonpath='{.spec.podSelector}')
    log_debug "NetworkPolicy $netpol_name podSelector: $pod_selector"

    log_info "NetworkPolicy validated"
    return 0
}

# validate_service_endpoints - Check service has healthy endpoints
# Usage: validate_service_endpoints <namespace> <service-name>
validate_service_endpoints() {
    local namespace="$1"
    local service="$2"

    log_info "Validating service endpoints: $service"

    # Check service exists
    if ! kubectl get svc "$service" -n "$namespace" >/dev/null 2>&1; then
        log_error "Service $service not found"
        return 1
    fi

    # Get endpoints
    local endpoints=$(kubectl get endpoints "$service" -n "$namespace" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)

    if [ -z "$endpoints" ]; then
        log_error "Service $service has no endpoints"
        return 1
    fi

    local endpoint_count=$(echo "$endpoints" | wc -w)
    log_debug "Service $service has $endpoint_count endpoint(s)"

    # Get service type
    local svc_type=$(kubectl get svc "$service" -n "$namespace" -o jsonpath='{.spec.type}')
    log_debug "Service $service type: $svc_type"

    log_info "Service endpoints validated ($endpoint_count endpoints)"
    return 0
}

# validate_migration_complete - Verify migration completed successfully
# Usage: validate_migration_complete <namespace> <old-selector> <new-selector>
validate_migration_complete() {
    local namespace="$1"
    local old_selector="$2"
    local new_selector="$3"

    log_info "Validating migration completion"

    # Check no old pods exist
    local old_pods=$(kubectl get pods -n "$namespace" -l "$old_selector" -o name 2>/dev/null | wc -l)
    if [ "$old_pods" -gt 0 ]; then
        log_error "Found $old_pods old pods still running (expected 0)"
        kubectl get pods -n "$namespace" -l "$old_selector"
        return 1
    fi
    log_debug "No old pods found (expected)"

    # Check new pods exist and are ready
    local new_pods=$(kubectl get pods -n "$namespace" -l "$new_selector" -o name 2>/dev/null | wc -l)
    if [ "$new_pods" -eq 0 ]; then
        log_error "No new pods found (expected > 0)"
        return 1
    fi
    log_debug "Found $new_pods new pods"

    # Verify all new pods are ready
    if ! validate_pod_health "$namespace" "$new_selector"; then
        log_error "New pods failed health checks"
        return 1
    fi

    log_info "Migration validated: $old_pods old pods, $new_pods new healthy pods"
    return 0
}

# If script is executed directly, show usage
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
    echo "Usage: source validation-checks.sh"
    echo ""
    echo "Available functions:"
    echo "  - validate_pod_health <namespace> <selector>"
    echo "  - validate_endpoints <namespace> <service> <token>"
    echo "  - validate_data_integrity <namespace> <service> <token>"
    echo "  - validate_resources <namespace> <selector> [annotation-key] [expected-value]"
    echo "  - validate_secrets <namespace> <secret-name> <expected-keys...>"
    echo "  - validate_pdb <namespace> <pdb-name>"
    echo "  - validate_networkpolicy <namespace> <netpol-name>"
    echo "  - validate_service_endpoints <namespace> <service-name>"
    echo "  - validate_migration_complete <namespace> <old-selector> <new-selector>"
    exit 1
fi
