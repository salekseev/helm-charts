#!/usr/bin/env bash
#
# convert-operator-to-helm.sh
#
# Converts SpiceDB Operator SpiceDBCluster CRD YAML to Helm values.yaml format
#
# Usage:
#   ./convert-operator-to-helm.sh [OPTIONS] <input-spicedbcluster.yaml>
#
# Options:
#   --input FILE, -i FILE    Input SpiceDBCluster YAML file (required)
#   --output FILE, -o FILE   Output values.yaml file (default: stdout)
#   --preset NAME            Base preset to use (development, production-postgres, production-cockroachdb, production-ha)
#   --dry-run                Validate without producing output
#   --help, -h               Show this help message
#
# Examples:
#   # Convert SpiceDBCluster to values.yaml
#   ./convert-operator-to-helm.sh -i spicedb-cluster.yaml
#
#   # Convert and save to file
#   ./convert-operator-to-helm.sh -i spicedb-cluster.yaml -o my-values.yaml
#
#   # Use production preset as base and overlay operator config
#   ./convert-operator-to-helm.sh -i spicedb-cluster.yaml --preset production-postgres -o values.yaml
#
#   # Test conversion without output
#   ./convert-operator-to-helm.sh -i spicedb-cluster.yaml --dry-run
#
# Operator-Exclusive Features (not directly convertible):
#   - spec.channel: Operator manages version updates via channels (stable, latest)
#     → Helm requires manual image.tag updates
#   - spec.patches: Operator-specific JSON patches for advanced customization
#     → Must be manually applied to Helm values
#
# Recommended Helm Features to Configure Manually:
#   - NetworkPolicy: Fine-grained network isolation (not in operator)
#   - Ingress: Kubernetes Ingress resource configuration
#   - ServiceMonitor: Prometheus Operator integration
#   - PodDisruptionBudget: More control over disruption budgets
#
# Field Mapping Reference:
#   SpiceDBCluster CRD                  → Helm values.yaml
#   =====================================================================================================
#   spec.version                        → image.tag
#   spec.image                          → image.repository + image.tag
#   spec.config.replicas                → replicaCount
#   spec.config.datastoreEngine         → config.datastoreEngine
#   spec.secretName                     → config.existingSecret
#   spec.config.logLevel                → logging.level
#   spec.config.tlsSecretName           → tls.grpc.secretName + tls.enabled=true
#   spec.config.dispatchEnabled         → dispatch.enabled
#   spec.config.dispatchUpstreamCASecretName → dispatch.upstreamCASecretName
#   spec.config.resources               → resources
#   spec.config.serviceAccountName      → serviceAccount.name
#

set -euo pipefail

# Default values
INPUT_FILE=""
OUTPUT_FILE=""
PRESET=""
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
        --preset)
            PRESET="$2"
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

# Validate input file is provided
if [[ -z "$INPUT_FILE" ]]; then
    echo "Error: Input file is required. Use -i or --input to specify." >&2
    echo "Use --help for usage information" >&2
    exit 1
fi

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

# Validate this is a SpiceDBCluster resource
KIND=$(yq eval '.kind' "$INPUT_FILE")
API_VERSION=$(yq eval '.apiVersion' "$INPUT_FILE")
if [[ "$KIND" != "SpiceDBCluster" ]] || [[ "$API_VERSION" != "authzed.com/v1alpha1" ]]; then
    echo "Error: Input file is not a SpiceDBCluster resource" >&2
    echo "Found: kind=$KIND, apiVersion=$API_VERSION" >&2
    echo "Expected: kind=SpiceDBCluster, apiVersion=authzed.com/v1alpha1" >&2
    exit 1
fi

# Extract values from SpiceDBCluster
SPEC_VERSION=$(yq eval '.spec.version // ""' "$INPUT_FILE")
SPEC_IMAGE=$(yq eval '.spec.image // ""' "$INPUT_FILE")
SECRET_NAME=$(yq eval '.spec.secretName // ""' "$INPUT_FILE")

# Config fields
REPLICAS=$(yq eval '.spec.config.replicas // 1' "$INPUT_FILE")
DATASTORE_ENGINE=$(yq eval '.spec.config.datastoreEngine // "memory"' "$INPUT_FILE")
LOG_LEVEL=$(yq eval '.spec.config.logLevel // "info"' "$INPUT_FILE")
TLS_SECRET=$(yq eval '.spec.config.tlsSecretName // ""' "$INPUT_FILE")
DISPATCH_ENABLED=$(yq eval '.spec.config.dispatchEnabled // false' "$INPUT_FILE")
DISPATCH_CA_SECRET=$(yq eval '.spec.config.dispatchUpstreamCASecretName // ""' "$INPUT_FILE")
SERVICE_ACCOUNT=$(yq eval '.spec.config.serviceAccountName // ""' "$INPUT_FILE")

# Resources
RESOURCES_REQUESTS_CPU=$(yq eval '.spec.config.resources.requests.cpu // "500m"' "$INPUT_FILE")
RESOURCES_REQUESTS_MEM=$(yq eval '.spec.config.resources.requests.memory // "1Gi"' "$INPUT_FILE")
RESOURCES_LIMITS_CPU=$(yq eval '.spec.config.resources.limits.cpu // "2000m"' "$INPUT_FILE")
RESOURCES_LIMITS_MEM=$(yq eval '.spec.config.resources.limits.memory // "4Gi"' "$INPUT_FILE")

# Determine image repository and tag
if [[ -n "$SPEC_IMAGE" ]]; then
    # Custom image specified
    IMAGE_REPO="${SPEC_IMAGE%:*}"
    IMAGE_TAG="${SPEC_IMAGE##*:}"
else
    # Default image with version
    IMAGE_REPO="authzed/spicedb"
    IMAGE_TAG="$SPEC_VERSION"
fi

# Feature warnings
WARNINGS=()

# Check for operator-exclusive features
CHANNEL=$(yq eval '.spec.channel // ""' "$INPUT_FILE")
if [[ -n "$CHANNEL" ]]; then
    WARNINGS+=("Operator channel '$CHANNEL' detected. Helm chart requires manual image.tag updates (no auto-update channel).")
fi

PATCHES=$(yq eval '.spec.patches // []' "$INPUT_FILE")
if [[ "$PATCHES" != "[]" && "$PATCHES" != "null" ]]; then
    WARNINGS+=("Operator patches detected. These must be manually applied to Helm values.yaml.")
fi

# Recommendations for Helm features
WARNINGS+=("RECOMMENDATION: Consider enabling NetworkPolicy in Helm for network isolation (not available in operator).")
WARNINGS+=("RECOMMENDATION: Consider configuring Ingress in Helm for external access (not managed by operator).")
if [[ "$DATASTORE_ENGINE" == "postgres" || "$DATASTORE_ENGINE" == "cockroachdb" ]]; then
    WARNINGS+=("RECOMMENDATION: Consider enabling ServiceMonitor in Helm for Prometheus integration.")
fi

# Print warnings to stderr
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "⚠ Conversion Warnings & Recommendations:" >&2
    for warning in "${WARNINGS[@]}"; do
        echo "  - $warning" >&2
    done
    echo >&2
fi

# Generate values.yaml
generate_values_yaml() {
    # Start with preset if specified
    if [[ -n "$PRESET" ]]; then
        PRESET_FILE="values-presets/${PRESET}.yaml"
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        CHART_DIR="$(dirname "$SCRIPT_DIR")"
        PRESET_PATH="${CHART_DIR}/${PRESET_FILE}"

        if [[ ! -f "$PRESET_PATH" ]]; then
            echo "Error: Preset file not found: $PRESET_PATH" >&2
            exit 1
        fi

        # Output preset as base with comment
        cat <<EOF
# Base configuration from preset: ${PRESET}
# Overlaid with values from SpiceDBCluster conversion

EOF
        cat "$PRESET_PATH"
        echo ""
        echo "# Overrides from SpiceDBCluster conversion:"
        echo ""
    fi

    # Generate Helm values
    cat <<EOF
# Image configuration
image:
  repository: "${IMAGE_REPO}"
  tag: "${IMAGE_TAG}"

# Replica count
replicaCount: ${REPLICAS}

# Datastore configuration
config:
  datastoreEngine: "${DATASTORE_ENGINE}"
EOF

    if [[ -n "$SECRET_NAME" ]]; then
        cat <<EOF
  existingSecret: "${SECRET_NAME}"
EOF
    fi

    # Logging
    cat <<EOF

# Logging configuration
logging:
  level: "${LOG_LEVEL}"
  format: "json"  # Recommended for production
EOF

    # TLS
    if [[ -n "$TLS_SECRET" ]]; then
        cat <<EOF

# TLS configuration
tls:
  enabled: true
  grpc:
    secretName: "${TLS_SECRET}"
EOF
    fi

    # Dispatch
    if [[ "$DISPATCH_ENABLED" == "true" ]]; then
        cat <<EOF

# Dispatch cluster configuration
dispatch:
  enabled: true
EOF
        if [[ -n "$DISPATCH_CA_SECRET" ]]; then
            cat <<EOF
  upstreamCASecretName: "${DISPATCH_CA_SECRET}"
EOF
        fi
    fi

    # Resources
    cat <<EOF

# Resource configuration
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

# ServiceAccount configuration
serviceAccount:
  create: false  # Using existing service account
  name: "${SERVICE_ACCOUNT}"
EOF
    fi

    # Add commented-out recommended features
    cat <<EOF

# Recommended Helm chart features (not available in operator):
# Uncomment and configure as needed

# networkPolicy:
#   enabled: true
#   ingress: []
#   egress: []

# ingress:
#   enabled: false
#   className: "nginx"
#   hosts:
#     - host: spicedb.example.com
#       paths:
#         - path: /
#           pathType: Prefix
#           servicePort: grpc

# monitoring:
#   serviceMonitor:
#     enabled: false
#     interval: 30s
EOF
}

# Execute conversion
if [[ "$DRY_RUN" == "true" ]]; then
    echo "✓ Dry-run successful. Input file is valid SpiceDBCluster resource." >&2
    echo "✓ Helm values.yaml would be generated with:" >&2
    echo "  - Image: ${IMAGE_REPO}:${IMAGE_TAG}" >&2
    echo "  - Replicas: ${REPLICAS}" >&2
    echo "  - Datastore: ${DATASTORE_ENGINE}" >&2
    echo "  - TLS: $([[ -n "$TLS_SECRET" ]] && echo "enabled" || echo "disabled")" >&2
    echo "  - Dispatch: $([[ "$DISPATCH_ENABLED" == "true" ]] && echo "enabled" || echo "disabled")" >&2
    exit 0
fi

# Generate and output
YAML_OUTPUT=$(generate_values_yaml)

# Validate generated YAML
if ! echo "$YAML_OUTPUT" | yq eval '.' > /dev/null 2>&1; then
    echo "Error: Generated YAML is invalid" >&2
    exit 1
fi

# Output to file or stdout
if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$YAML_OUTPUT" > "$OUTPUT_FILE"
    echo "✓ Helm values.yaml written to: $OUTPUT_FILE" >&2
else
    echo "$YAML_OUTPUT"
fi

# Success message
echo "✓ Conversion successful!" >&2
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "✓ Review ${#WARNINGS[@]} warning(s) and recommendation(s) above." >&2
fi
echo "✓ Next steps:" >&2
echo "  1. Review and customize the generated values.yaml" >&2
echo "  2. Create required secrets (datastore credentials, TLS certs if needed)" >&2
echo "  3. Test with: helm template test-release . -f <output-file>" >&2
echo "  4. Install with: helm install <release-name> . -f <output-file>" >&2
