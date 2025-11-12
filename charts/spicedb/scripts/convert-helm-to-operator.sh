#!/usr/bin/env bash
#
# convert-helm-to-operator.sh
#
# Converts Helm values.yaml to SpiceDB Operator SpiceDBCluster CRD YAML
#
# Usage:
#   ./convert-helm-to-operator.sh [OPTIONS] <input-values.yaml>
#
# Options:
#   --input FILE, -i FILE    Input Helm values.yaml file (default: values.yaml)
#   --output FILE, -o FILE   Output SpiceDBCluster YAML file (default: stdout)
#   --name NAME             SpiceDBCluster resource name (default: spicedb)
#   --namespace NS          Kubernetes namespace (default: default)
#   --dry-run               Validate without producing output
#   --help, -h              Show this help message
#
# Examples:
#   # Convert development preset
#   ./convert-helm-to-operator.sh -i values-presets/development.yaml
#
#   # Convert production preset to file
#   ./convert-helm-to-operator.sh -i values-presets/production-postgres.yaml -o spicedb-cluster.yaml
#
#   # Test conversion without output
#   ./convert-helm-to-operator.sh -i values.yaml --dry-run
#
# Limitations:
#   - NetworkPolicy: Not supported by operator (Helm chart exclusive feature)
#   - Ingress: Not managed by operator (manual setup required)
#   - ServiceMonitor: Not supported by operator
#   - PodDisruptionBudget: Operator manages this differently
#   - Custom Service configurations: Operator provides fixed service structure
#
# Field Mapping Reference:
#   Helm values.yaml              → SpiceDBCluster CRD
#   =====================================================================================================
#   replicaCount                  → spec.config.replicas
#   image.repository:tag          → spec.version (tag only), spec.image (full reference if custom)
#   config.datastoreEngine        → spec.config.datastoreEngine
#   config.existingSecret         → spec.secretName
#   config.logLevel               → spec.config.logLevel
#   tls.grpc.secretName           → spec.config.tlsSecretName
#   dispatch.enabled              → spec.config.dispatchEnabled
#   dispatch.upstreamCASecretName → spec.config.dispatchUpstreamCASecretName
#   resources                     → spec.config.resources
#   serviceAccount.name           → spec.config.serviceAccountName
#

set -euo pipefail

# Default values
INPUT_FILE="values.yaml"
OUTPUT_FILE=""
CLUSTER_NAME="spicedb"
NAMESPACE="default"
DRY_RUN=false

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--input)
            INPUT_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            if [[ -f "$1" ]]; then
                INPUT_FILE="$1"
                shift
            else
                echo "Error: Unknown option or file not found: $1" >&2
                echo "Use --help for usage information" >&2
                exit 1
            fi
            ;;
    esac
done

# Check for yq
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed." >&2
    echo "Install yq v4+: https://github.com/mikefarah/yq#install" >&2
    exit 2
fi

# Validate yq version (need v4+)
YQ_VERSION=$(yq --version | grep -oP 'version \K[0-9]+' | head -1)
if [[ "$YQ_VERSION" -lt 4 ]]; then
    echo "Error: yq version 4+ is required (found version $YQ_VERSION)" >&2
    exit 2
fi

# Validate input file exists
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Input file not found: $INPUT_FILE" >&2
    exit 1
fi

# Validate input is valid YAML
if ! yq eval '.' "$INPUT_FILE" > /dev/null 2>&1; then
    echo "Error: Input file is not valid YAML: $INPUT_FILE" >&2
    exit 1
fi

# Extract values from Helm values.yaml
REPLICA_COUNT=$(yq eval '.replicaCount // 1' "$INPUT_FILE")
DATASTORE_ENGINE=$(yq eval '.config.datastoreEngine // "memory"' "$INPUT_FILE")
EXISTING_SECRET=$(yq eval '.config.existingSecret // ""' "$INPUT_FILE")
LOG_LEVEL=$(yq eval '.logging.level // "info"' "$INPUT_FILE")
IMAGE_TAG=$(yq eval '.image.tag // ""' "$INPUT_FILE")
IMAGE_REPO=$(yq eval '.image.repository // "authzed/spicedb"' "$INPUT_FILE")

# TLS configuration
TLS_ENABLED=$(yq eval '.tls.enabled // false' "$INPUT_FILE")
TLS_GRPC_SECRET=$(yq eval '.tls.grpc.secretName // ""' "$INPUT_FILE")

# Dispatch configuration
DISPATCH_ENABLED=$(yq eval '.dispatch.enabled // false' "$INPUT_FILE")
DISPATCH_CA_SECRET=$(yq eval '.dispatch.upstreamCASecretName // ""' "$INPUT_FILE")

# Resources
RESOURCES_REQUESTS_CPU=$(yq eval '.resources.requests.cpu // "500m"' "$INPUT_FILE")
RESOURCES_REQUESTS_MEM=$(yq eval '.resources.requests.memory // "1Gi"' "$INPUT_FILE")
RESOURCES_LIMITS_CPU=$(yq eval '.resources.limits.cpu // "2000m"' "$INPUT_FILE")
RESOURCES_LIMITS_MEM=$(yq eval '.resources.limits.memory // "4Gi"' "$INPUT_FILE")

# ServiceAccount
SERVICE_ACCOUNT=$(yq eval '.serviceAccount.name // ""' "$INPUT_FILE")

# Feature warnings
WARNINGS=()

# Check for Helm-exclusive features
if [[ $(yq eval '.networkPolicy.enabled // false' "$INPUT_FILE") == "true" ]]; then
    WARNINGS+=("NetworkPolicy is enabled but not supported by SpiceDB Operator. Configure NetworkPolicy manually.")
fi

if [[ $(yq eval '.ingress.enabled // false' "$INPUT_FILE") == "true" ]]; then
    WARNINGS+=("Ingress is configured but not managed by SpiceDB Operator. Configure Ingress manually.")
fi

if [[ $(yq eval '.monitoring.serviceMonitor.enabled // false' "$INPUT_FILE") == "true" ]]; then
    WARNINGS+=("ServiceMonitor is enabled but not managed by SpiceDB Operator. Configure ServiceMonitor manually.")
fi

if [[ $(yq eval '.podDisruptionBudget.enabled // false' "$INPUT_FILE") == "true" ]]; then
    WARNINGS+=("PodDisruptionBudget is configured but managed differently by Operator. Review operator PDB settings.")
fi

if [[ $(yq eval '.autoscaling.enabled // false' "$INPUT_FILE") == "true" ]]; then
    WARNINGS+=("HorizontalPodAutoscaler is configured. Operator may handle autoscaling differently.")
fi

# Print warnings to stderr
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "⚠ Conversion Warnings:" >&2
    for warning in "${WARNINGS[@]}"; do
        echo "  - $warning" >&2
    done
    echo >&2
fi

# Generate SpiceDBCluster YAML
generate_spicedbcluster() {
    cat <<EOF
---
apiVersion: authzed.com/v1alpha1
kind: SpiceDBCluster
metadata:
  name: ${CLUSTER_NAME}
  namespace: ${NAMESPACE}
spec:
  version: "${IMAGE_TAG:-latest}"
EOF

    # Add custom image if not default
    if [[ "$IMAGE_REPO" != "authzed/spicedb" ]]; then
        cat <<EOF
  image: "${IMAGE_REPO}:${IMAGE_TAG:-latest}"
EOF
    fi

    # Add secretName
    if [[ -n "$EXISTING_SECRET" ]]; then
        cat <<EOF
  secretName: "${EXISTING_SECRET}"
EOF
    fi

    # Config section
    cat <<EOF
  config:
    replicas: ${REPLICA_COUNT}
    datastoreEngine: "${DATASTORE_ENGINE}"
    logLevel: "${LOG_LEVEL}"
EOF

    # TLS configuration
    if [[ "$TLS_ENABLED" == "true" && -n "$TLS_GRPC_SECRET" ]]; then
        cat <<EOF
    tlsSecretName: "${TLS_GRPC_SECRET}"
EOF
    fi

    # Dispatch configuration
    if [[ "$DISPATCH_ENABLED" == "true" ]]; then
        cat <<EOF
    dispatchEnabled: true
EOF
        if [[ -n "$DISPATCH_CA_SECRET" ]]; then
            cat <<EOF
    dispatchUpstreamCASecretName: "${DISPATCH_CA_SECRET}"
EOF
        fi
    fi

    # Resources
    cat <<EOF
    resources:
      requests:
        cpu: "${RESOURCES_REQUESTS_CPU}"
        memory: "${RESOURCES_REQUESTS_MEM}"
      limits:
        cpu: "${RESOURCES_LIMITS_CPU}"
        memory: "${RESOURCES_LIMITS_MEM}"
EOF

    # ServiceAccount
    if [[ -n "$SERVICE_ACCOUNT" ]]; then
        cat <<EOF
    serviceAccountName: "${SERVICE_ACCOUNT}"
EOF
    fi
}

# Execute conversion
if [[ "$DRY_RUN" == "true" ]]; then
    echo "✓ Dry-run successful. Input file is valid." >&2
    echo "✓ SpiceDBCluster would be created with:" >&2
    echo "  - Name: ${CLUSTER_NAME}" >&2
    echo "  - Namespace: ${NAMESPACE}" >&2
    echo "  - Replicas: ${REPLICA_COUNT}" >&2
    echo "  - Datastore: ${DATASTORE_ENGINE}" >&2
    exit 0
fi

# Generate and output
YAML_OUTPUT=$(generate_spicedbcluster)

# Validate generated YAML
if ! echo "$YAML_OUTPUT" | yq eval '.' > /dev/null 2>&1; then
    echo "Error: Generated YAML is invalid" >&2
    exit 1
fi

# Output to file or stdout
if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$YAML_OUTPUT" > "$OUTPUT_FILE"
    echo "✓ SpiceDBCluster YAML written to: $OUTPUT_FILE" >&2
else
    echo "$YAML_OUTPUT"
fi

# Success message
if [[ ${#WARNINGS[@]} -eq 0 ]]; then
    echo "✓ Conversion successful!" >&2
else
    echo "✓ Conversion complete with ${#WARNINGS[@]} warning(s). Review warnings above." >&2
fi
