#!/bin/bash
set -euo pipefail

# SpiceDB Status Checker
# Check deployment health, migration status, and version information

# Default values
NAMESPACE="default"
RELEASE="spicedb"
FORMAT="text"

# Usage information
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Check SpiceDB deployment status including replicas, versions, and migration state.

Options:
  -n, --namespace NAMESPACE    Kubernetes namespace (default: default)
  -r, --release RELEASE        Helm release name (default: spicedb)
  -f, --format FORMAT          Output format: text or json (default: text)
  -h, --help                   Show this help message

Examples:
  $0
  $0 --namespace spicedb-prod --release my-spicedb
  $0 -n production -r spicedb -f json

Requirements:
  - kubectl command-line tool
  - jq for JSON processing
  - Access to the Kubernetes cluster
EOF
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -r|--release)
      RELEASE="$2"
      shift 2
      ;;
    -f|--format)
      FORMAT="$2"
      if [[ "$FORMAT" != "text" && "$FORMAT" != "json" ]]; then
        echo "Error: format must be 'text' or 'json'" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# Check dependencies
for cmd in kubectl jq; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: $cmd is required but not installed" >&2
    exit 1
  fi
done

# Get Deployment status
DEPLOYMENT=$(kubectl get deployment -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE,app.kubernetes.io/name=spicedb" -o json 2>/dev/null || echo '{"items":[]}')

# Check if deployment exists
DEPLOYMENT_COUNT=$(echo "$DEPLOYMENT" | jq -r '.items | length')
if [ "$DEPLOYMENT_COUNT" -eq 0 ]; then
  if [ "$FORMAT" = "json" ]; then
    echo '{"error":"Deployment not found"}'
  else
    echo "Error: No SpiceDB deployment found with release name '$RELEASE' in namespace '$NAMESPACE'" >&2
  fi
  exit 1
fi

# Get migration status ConfigMap
MIGRATION_STATUS=$(kubectl get configmap -n "$NAMESPACE" "${RELEASE}-migration-status" -o json 2>/dev/null || echo '{}')

# Get Pod status
PODS=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE,app.kubernetes.io/name=spicedb" -o json 2>/dev/null || echo '{"items":[]}')

# Extract deployment data
REPLICAS=$(echo "$DEPLOYMENT" | jq -r '.items[0].spec.replicas // 0')
READY=$(echo "$DEPLOYMENT" | jq -r '.items[0].status.readyReplicas // 0')
AVAILABLE=$(echo "$DEPLOYMENT" | jq -r '.items[0].status.availableReplicas // 0')
UPDATED=$(echo "$DEPLOYMENT" | jq -r '.items[0].status.updatedReplicas // 0')

# Extract annotations
VERSION=$(echo "$DEPLOYMENT" | jq -r '.items[0].spec.template.metadata.annotations["spicedb.authzed.com/version"] // .items[0].metadata.labels["app.kubernetes.io/version"] // "unknown"')
CHART_VERSION=$(echo "$DEPLOYMENT" | jq -r '.items[0].spec.template.metadata.annotations["spicedb.authzed.com/chart-version"] // .items[0].metadata.labels["helm.sh/chart"] // "unknown"')
DATASTORE_ENGINE=$(echo "$DEPLOYMENT" | jq -r '.items[0].spec.template.metadata.annotations["spicedb.authzed.com/datastore-engine"] // "unknown"')
MIGRATION_HASH=$(echo "$DEPLOYMENT" | jq -r '.items[0].spec.template.metadata.annotations["spicedb.authzed.com/migration-hash"] // "unknown"')

# Extract migration status from ConfigMap
if [ "$(echo "$MIGRATION_STATUS" | jq -r 'has("data")')" = "true" ]; then
  MIGRATION_CHART_VERSION=$(echo "$MIGRATION_STATUS" | jq -r '.data.chartVersion // "unknown"')
  MIGRATION_APP_VERSION=$(echo "$MIGRATION_STATUS" | jq -r '.data.appVersion // "unknown"')
  MIGRATION_DATASTORE=$(echo "$MIGRATION_STATUS" | jq -r '.data.datastoreEngine // "unknown"')
  MIGRATION_TARGET=$(echo "$MIGRATION_STATUS" | jq -r '.data.targetMigration // ""')
  MIGRATION_PHASE=$(echo "$MIGRATION_STATUS" | jq -r '.data.targetPhase // ""')
  MIGRATION_TIMESTAMP=$(echo "$MIGRATION_STATUS" | jq -r '.data.timestamp // "unknown"')
  MIGRATION_CONFIG_HASH=$(echo "$MIGRATION_STATUS" | jq -r '.data.migrationHash // "unknown"')
else
  MIGRATION_CHART_VERSION="none"
  MIGRATION_APP_VERSION="none"
  MIGRATION_DATASTORE="none"
  MIGRATION_TARGET="none"
  MIGRATION_PHASE="none"
  MIGRATION_TIMESTAMP="none"
  MIGRATION_CONFIG_HASH="none"
fi

# Get pod states
POD_COUNT=$(echo "$PODS" | jq -r '.items | length')
RUNNING_PODS=$(echo "$PODS" | jq -r '[.items[] | select(.status.phase == "Running")] | length')
PENDING_PODS=$(echo "$PODS" | jq -r '[.items[] | select(.status.phase == "Pending")] | length')
FAILED_PODS=$(echo "$PODS" | jq -r '[.items[] | select(.status.phase == "Failed")] | length')

# Determine overall health
if [ "$READY" -eq "$REPLICAS" ] && [ "$AVAILABLE" -eq "$REPLICAS" ]; then
  HEALTH="healthy"
elif [ "$READY" -gt 0 ]; then
  HEALTH="degraded"
else
  HEALTH="unhealthy"
fi

# Output results
if [ "$FORMAT" = "json" ]; then
  jq -n \
    --arg namespace "$NAMESPACE" \
    --arg release "$RELEASE" \
    --arg health "$HEALTH" \
    --argjson replicas "$REPLICAS" \
    --argjson ready "$READY" \
    --argjson available "$AVAILABLE" \
    --argjson updated "$UPDATED" \
    --arg version "$VERSION" \
    --arg chartVersion "$CHART_VERSION" \
    --arg datastoreEngine "$DATASTORE_ENGINE" \
    --arg migrationHash "$MIGRATION_HASH" \
    --argjson podCount "$POD_COUNT" \
    --argjson runningPods "$RUNNING_PODS" \
    --argjson pendingPods "$PENDING_PODS" \
    --argjson failedPods "$FAILED_PODS" \
    --arg migrationChartVersion "$MIGRATION_CHART_VERSION" \
    --arg migrationAppVersion "$MIGRATION_APP_VERSION" \
    --arg migrationDatastore "$MIGRATION_DATASTORE" \
    --arg migrationTarget "$MIGRATION_TARGET" \
    --arg migrationPhase "$MIGRATION_PHASE" \
    --arg migrationTimestamp "$MIGRATION_TIMESTAMP" \
    --arg migrationConfigHash "$MIGRATION_CONFIG_HASH" \
    '{
      namespace: $namespace,
      release: $release,
      health: $health,
      deployment: {
        replicas: $replicas,
        ready: $ready,
        available: $available,
        updated: $updated
      },
      version: {
        app: $version,
        chart: $chartVersion,
        datastoreEngine: $datastoreEngine,
        migrationHash: $migrationHash
      },
      pods: {
        total: $podCount,
        running: $runningPods,
        pending: $pendingPods,
        failed: $failedPods
      },
      migration: {
        chartVersion: $migrationChartVersion,
        appVersion: $migrationAppVersion,
        datastoreEngine: $migrationDatastore,
        targetMigration: $migrationTarget,
        targetPhase: $migrationPhase,
        timestamp: $migrationTimestamp,
        configHash: $migrationConfigHash
      }
    }'
else
  # Text output
  echo "SpiceDB Status"
  echo "=============="
  echo ""
  echo "Namespace: $NAMESPACE"
  echo "Release:   $RELEASE"
  echo "Health:    $HEALTH"
  echo ""
  echo "Deployment:"
  echo "  Replicas:  $READY/$REPLICAS ready, $AVAILABLE available, $UPDATED updated"
  echo ""
  echo "Version Information:"
  echo "  App Version:      $VERSION"
  echo "  Chart Version:    $CHART_VERSION"
  echo "  Datastore Engine: $DATASTORE_ENGINE"
  echo "  Migration Hash:   $MIGRATION_HASH"
  echo ""
  echo "Pods:"
  echo "  Total:   $POD_COUNT"
  echo "  Running: $RUNNING_PODS"
  echo "  Pending: $PENDING_PODS"
  echo "  Failed:  $FAILED_PODS"
  echo ""
  if [ "$MIGRATION_CHART_VERSION" != "none" ]; then
    echo "Migration Status:"
    echo "  Chart Version:    $MIGRATION_CHART_VERSION"
    echo "  App Version:      $MIGRATION_APP_VERSION"
    echo "  Datastore:        $MIGRATION_DATASTORE"
    echo "  Target Migration: ${MIGRATION_TARGET:-latest}"
    echo "  Target Phase:     ${MIGRATION_PHASE:-all phases}"
    echo "  Timestamp:        $MIGRATION_TIMESTAMP"
    echo "  Config Hash:      $MIGRATION_CONFIG_HASH"
  else
    echo "Migration Status: No migration tracking data found"
  fi
fi

# Exit with appropriate code
if [ "$HEALTH" = "healthy" ]; then
  exit 0
elif [ "$HEALTH" = "degraded" ]; then
  exit 0
else
  exit 1
fi
