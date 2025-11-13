#!/bin/bash
# convert-cr-to-values.sh - Convert SpiceDBCluster CR to Helm values.yaml
# This script extracts configuration from a SpiceDBCluster custom resource
# and generates an equivalent Helm values.yaml file

set -euo pipefail

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[CONVERT]${NC} $1"; }
log_error() { echo -e "${RED}[CONVERT ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[CONVERT WARN]${NC} $1"; }
log_debug() { echo -e "${BLUE}[CONVERT DEBUG]${NC} $1"; }

# Usage function
usage() {
    cat <<EOF
Usage: $0 [OPTIONS] <spicedbcluster-name>

Convert SpiceDBCluster CR to Helm values.yaml format.

OPTIONS:
    -n, --namespace <namespace>     Kubernetes namespace (default: default)
    -o, --output <file>             Output file (default: values.yaml)
    -f, --file <file>               Read from file instead of cluster
    -h, --help                      Show this help message

EXAMPLES:
    # Convert from live cluster
    $0 spicedb -n production -o prod-values.yaml

    # Convert from saved YAML file
    $0 -f spicedbcluster.yaml -o values.yaml

    # Use with kubectl
    kubectl get spicedbcluster spicedb -o yaml | $0 -f - -o values.yaml
EOF
    exit 1
}

# Parse arguments
NAMESPACE="default"
OUTPUT="values.yaml"
CR_FILE=""
CR_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT="$2"
            shift 2
            ;;
        -f|--file)
            CR_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            CR_NAME="$1"
            shift
            ;;
    esac
done

# Validation
if [ -z "$CR_FILE" ] && [ -z "$CR_NAME" ]; then
    log_error "Either SpiceDBCluster name or --file must be provided"
    usage
fi

# Check dependencies
if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required but not installed"
    exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
    log_warn "yq not found, using jq only (some conversions may be limited)"
fi

# Get CR YAML
TMP_CR="/tmp/spicedbcluster-$$.yaml"
trap "rm -f $TMP_CR" EXIT

if [ -n "$CR_FILE" ]; then
    if [ "$CR_FILE" = "-" ]; then
        log_info "Reading SpiceDBCluster from stdin..."
        cat > "$TMP_CR"
    else
        log_info "Reading SpiceDBCluster from file: $CR_FILE"
        cp "$CR_FILE" "$TMP_CR"
    fi
else
    log_info "Fetching SpiceDBCluster: $CR_NAME from namespace: $NAMESPACE"
    if ! kubectl get spicedbcluster "$CR_NAME" -n "$NAMESPACE" -o yaml > "$TMP_CR" 2>/dev/null; then
        log_error "Failed to fetch SpiceDBCluster $CR_NAME"
        exit 1
    fi
fi

# Convert YAML to JSON for easier parsing
TMP_JSON="/tmp/spicedbcluster-$$.json"
trap "rm -f $TMP_CR $TMP_JSON" EXIT

if command -v yq >/dev/null 2>&1; then
    yq eval -o=json "$TMP_CR" > "$TMP_JSON"
else
    # Fallback: use kubectl if available
    if command -v kubectl >/dev/null 2>&1 && [ -n "$CR_NAME" ]; then
        kubectl get spicedbcluster "$CR_NAME" -n "$NAMESPACE" -o json > "$TMP_JSON" 2>/dev/null || {
            log_error "Failed to convert YAML to JSON"
            exit 1
        }
    else
        log_error "Cannot convert YAML to JSON (install yq or kubectl)"
        exit 1
    fi
fi

log_debug "Parsing SpiceDBCluster configuration..."

# Extract values
REPLICAS=$(jq -r '.spec.replicas // 1' "$TMP_JSON")
VERSION=$(jq -r '.spec.version // "v1.35.0"' "$TMP_JSON")
SECRET_NAME=$(jq -r '.spec.secretName // ""' "$TMP_JSON")

# Datastore configuration
DATASTORE_ENGINE=$(jq -r '.spec.datastoreEngine | keys[0] // "memory"' "$TMP_JSON")

# TLS configuration
TLS_SECRET=$(jq -r '.spec.tlsSecretName // ""' "$TMP_JSON")

# Dispatch configuration
DISPATCH_ENABLED=$(jq -r '.spec.dispatchCluster.enabled // false' "$TMP_JSON")
DISPATCH_TLS=$(jq -r '.spec.dispatchCluster.tlsSecretName // ""' "$TMP_JSON")

# Resource requests/limits
CPU_REQUEST=$(jq -r '.spec.resources.requests.cpu // "500m"' "$TMP_JSON")
MEM_REQUEST=$(jq -r '.spec.resources.requests.memory // "1Gi"' "$TMP_JSON")
CPU_LIMIT=$(jq -r '.spec.resources.limits.cpu // "2000m"' "$TMP_JSON")
MEM_LIMIT=$(jq -r '.spec.resources.limits.memory // "4Gi"' "$TMP_JSON")

# Additional config
EXTRA_ARGS=$(jq -r '.spec.extraArgs // [] | join(",")' "$TMP_JSON")

log_debug "Extracted configuration:"
log_debug "  Replicas: $REPLICAS"
log_debug "  Version: $VERSION"
log_debug "  Datastore: $DATASTORE_ENGINE"
log_debug "  TLS: ${TLS_SECRET:-none}"
log_debug "  Dispatch: $DISPATCH_ENABLED"

# Generate Helm values.yaml
log_info "Generating Helm values.yaml: $OUTPUT"

cat > "$OUTPUT" <<EOF
# Generated Helm values from SpiceDBCluster CR
# Source: ${CR_NAME:-$CR_FILE}
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Namespace: $NAMESPACE

# Replica count from spec.replicas
replicaCount: $REPLICAS

# SpiceDB version from spec.version
image:
  repository: authzed/spicedb
  pullPolicy: IfNotPresent
  tag: "$VERSION"

# Datastore configuration from spec.datastoreEngine
config:
  datastoreEngine: $DATASTORE_ENGINE
EOF

# Add secret reference if exists
if [ -n "$SECRET_NAME" ] && [ "$SECRET_NAME" != "null" ]; then
    cat >> "$OUTPUT" <<EOF

  # Use existing secret from operator
  existingSecret: $SECRET_NAME
EOF
else
    log_warn "No secret name found, you'll need to configure datastore connection"
    cat >> "$OUTPUT" <<EOF

  # No existingSecret found - configure datastore connection
  # datastore:
  #   hostname: postgres.database.svc.cluster.local
  #   port: 5432
  #   username: spicedb
  #   database: spicedb
  #   password: changeme
  #   sslMode: require

  # Or generate secret automatically
  autogenerateSecret: true
  presharedKey: "insecure-default-key-change-in-production"
EOF
fi

# Add TLS configuration if exists
if [ -n "$TLS_SECRET" ] && [ "$TLS_SECRET" != "null" ]; then
    log_debug "Adding TLS configuration"
    cat >> "$OUTPUT" <<EOF

# TLS configuration from spec.tlsSecretName
tls:
  enabled: true
  grpc:
    secretName: $TLS_SECRET
  http:
    secretName: $TLS_SECRET  # Operator uses same secret for both
EOF
fi

# Add dispatch configuration if enabled
if [ "$DISPATCH_ENABLED" = "true" ]; then
    log_debug "Adding dispatch configuration"
    cat >> "$OUTPUT" <<EOF

# Dispatch cluster configuration from spec.dispatchCluster
dispatch:
  enabled: true
EOF

    if [ -n "$DISPATCH_TLS" ] && [ "$DISPATCH_TLS" != "null" ]; then
        cat >> "$OUTPUT" <<EOF

  # Dispatch TLS from spec.dispatchCluster.tlsSecretName
  # Note: Configure in tls.dispatch.secretName
EOF
    fi
fi

# Add TLS dispatch secret if configured
if [ -n "$DISPATCH_TLS" ] && [ "$DISPATCH_TLS" != "null" ]; then
    # Check if tls section exists, append or create
    if grep -q "^tls:" "$OUTPUT"; then
        # Append to existing tls section
        sed -i "/^tls:/a\\  dispatch:\\n    secretName: $DISPATCH_TLS" "$OUTPUT"
    else
        cat >> "$OUTPUT" <<EOF

tls:
  dispatch:
    secretName: $DISPATCH_TLS
EOF
    fi
fi

# Add resource configuration
cat >> "$OUTPUT" <<EOF

# Resource configuration from spec.resources
resources:
  requests:
    cpu: $CPU_REQUEST
    memory: $MEM_REQUEST
  limits:
    cpu: $CPU_LIMIT
    memory: $MEM_LIMIT
EOF

# Add production defaults
cat >> "$OUTPUT" <<EOF

# Production defaults (recommended for migrated deployments)
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1

migrations:
  enabled: true

monitoring:
  enabled: true
EOF

# Add extra args if any
if [ -n "$EXTRA_ARGS" ] && [ "$EXTRA_ARGS" != "null" ] && [ "$EXTRA_ARGS" != "" ]; then
    log_debug "Adding extra arguments"
    cat >> "$OUTPUT" <<EOF

# Additional arguments from spec.extraArgs
extraArgs:
$(echo "$EXTRA_ARGS" | tr ',' '\n' | sed 's/^/  - /')
EOF
fi

# Add migration notes
cat >> "$OUTPUT" <<EOF

# Migration Notes:
# ---------------
# 1. Verify all secrets exist in the target namespace
# 2. Review and adjust resource limits based on actual usage
# 3. Consider adding these Helm-exclusive features:
#    - NetworkPolicy for network isolation
#    - Ingress for external access
#    - ServiceMonitor for Prometheus integration
#    - HorizontalPodAutoscaler for auto-scaling
#
# 4. Operator features without Helm equivalent:
#    - Update channels (use manual helm upgrade instead)
#    - Automatic rollback (use helm rollback instead)
#    - Dynamic reconciliation (use helm upgrade instead)
#
# 5. Test this configuration before applying:
#    helm template spicedb charts/spicedb -f $OUTPUT | kubectl apply --dry-run=client -f -
EOF

log_info "Conversion complete: $OUTPUT"
log_info ""
log_info "Next steps:"
log_info "  1. Review generated values: cat $OUTPUT"
log_info "  2. Validate with Helm: helm template spicedb charts/spicedb -f $OUTPUT"
log_info "  3. Test installation: helm install spicedb charts/spicedb -f $OUTPUT --dry-run"

# Show summary
cat <<EOF

Configuration Summary:
  Replicas:      $REPLICAS
  Version:       $VERSION
  Datastore:     $DATASTORE_ENGINE
  Secret:        ${SECRET_NAME:-<not configured>}
  TLS:           ${TLS_SECRET:-disabled}
  Dispatch:      $DISPATCH_ENABLED
  Resources:     CPU: $CPU_REQUEST-$CPU_LIMIT, Memory: $MEM_REQUEST-$MEM_LIMIT

EOF

exit 0
