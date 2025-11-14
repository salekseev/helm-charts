# Configuration Conversion: Operator to Helm

**Navigation**: [Overview](./index.md) | [Prerequisites](./prerequisites.md) | [Migration Steps](./step-by-step.md) | **Configuration** | [Post-Migration](./post-migration.md) | [Troubleshooting](../../guides/troubleshooting/index.md)

This guide provides comprehensive mapping for converting SpiceDBCluster specifications to Helm values.yaml.

## Basic Configuration

| SpiceDBCluster spec | Helm values.yaml | Notes |
|---------------------|------------------|-------|
| `spec.replicas: 3` | `replicaCount: 3` | Direct mapping |
| `spec.version: "v1.35.0"` | `image.tag: "v1.35.0"` | Helm also needs image.repository |
| `spec.secretName: spicedb-config` | `config.existingSecret: spicedb-config` | Reuse same secret |
| `spec.channel: stable` | N/A | Operator-only feature, no Helm equivalent |

## Datastore Configuration

### PostgreSQL

**Operator:**

```yaml
spec:
  datastoreEngine:
    postgres:
      connectionString:
        secretKeyRef:
          name: postgres-uri
          key: datastore-uri
```

**Helm:**

```yaml
config:
  datastoreEngine: postgres
  existingSecret: postgres-uri  # Must have 'datastore-uri' key
```

### Memory (Testing Only)

**Operator:**

```yaml
spec:
  datastoreEngine:
    memory: {}
```

**Helm:**

```yaml
config:
  datastoreEngine: memory
```

## TLS Configuration

**Operator:**

```yaml
spec:
  tlsSecretName: spicedb-tls  # Single secret for gRPC + HTTP
  dispatchCluster:
    enabled: true
    tlsSecretName: spicedb-dispatch-tls
```

**Helm:**

```yaml
tls:
  enabled: true
  grpc:
    secretName: spicedb-tls  # Reuse operator secret
  http:
    secretName: spicedb-tls  # Reuse same secret
  dispatch:
    secretName: spicedb-dispatch-tls

dispatch:
  enabled: true
```

## Resource Configuration

**Operator:**

```yaml
spec:
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 4Gi
```

**Helm:**

```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

## New Features in Helm (Not in Operator)

| Feature | Helm Configuration |
|---------|-------------------|
| NetworkPolicy | `networkPolicy.enabled: true` + configuration |
| Ingress | `ingress.enabled: true` + hosts/tls configuration |
| ServiceMonitor | `monitoring.serviceMonitor.enabled: true` |
| Migration cleanup | `migrations.cleanup.enabled: true` |
| PDB control | `podDisruptionBudget.maxUnavailable: 1` |

## Operator Features Without Helm Equivalent

| Operator Feature | Workaround in Helm |
|------------------|-------------------|
| Update channels | Manual version updates via `image.tag` |
| CRD status | Use `kubectl get pods`, `helm status` |
| Automatic rollback | Manual `helm rollback` |
| Dynamic reconciliation | Manual `helm upgrade` to apply changes |

## Feature Mapping Matrix

### Operator → Helm Feature Mapping

| Operator Feature | Helm Equivalent | Notes |
|------------------|-----------------|-------|
| Update channels | Manual updates | Use GitOps tools for automation |
| CRD status | `kubectl`/`helm status` | Less structured, more manual |
| Automatic rollback | `helm rollback` | Manual command required |
| Dynamic reconciliation | `helm upgrade` | Manual trigger required |
| MySQL support | Not supported | Use PostgreSQL or CockroachDB |
| Cloud Spanner | Not supported | Use PostgreSQL or CockroachDB |

### New Capabilities with Helm

| Capability | Description |
|------------|-------------|
| NetworkPolicy | Network isolation and security policies |
| Ingress | External access with path-based routing |
| ServiceMonitor | Prometheus Operator integration |
| Helm unit tests | CI/CD template validation |
| values-examples | Pre-configured deployment scenarios |
| GitOps with Helm | ArgoCD/Flux native support |

## Conversion Script

Helper script to convert SpiceDBCluster to Helm values:

```bash
#!/bin/bash
# scripts/convert-operator-to-helm.sh

set -e

if [ $# -lt 1 ]; then
  echo "Usage: $0 <spicedbcluster-name> [namespace] [output-file.yaml]"
  exit 1
fi

CLUSTER_NAME="$1"
NAMESPACE="${2:-default}"
OUTPUT="${3:-values.yaml}"

# Get SpiceDBCluster
kubectl get spicedbcluster "$CLUSTER_NAME" -n "$NAMESPACE" -o json > /tmp/cluster.json

# Extract values (requires jq)
REPLICAS=$(jq -r '.spec.replicas // 3' /tmp/cluster.json)
VERSION=$(jq -r '.spec.version // "v1.35.0"' /tmp/cluster.json)
SECRET=$(jq -r '.spec.secretName // "spicedb"' /tmp/cluster.json)
TLS_SECRET=$(jq -r '.spec.tlsSecretName // ""' /tmp/cluster.json)
DISPATCH_ENABLED=$(jq -r '.spec.dispatchCluster.enabled // false' /tmp/cluster.json)
DISPATCH_TLS=$(jq -r '.spec.dispatchCluster.tlsSecretName // ""' /tmp/cluster.json)

# Detect datastore engine
DATASTORE_TYPE=$(jq -r '.spec.datastoreEngine | keys[0]' /tmp/cluster.json)

# Generate Helm values
cat > "$OUTPUT" <<EOF
# Generated from SpiceDBCluster: $CLUSTER_NAME
# Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)

replicaCount: $REPLICAS

image:
  repository: authzed/spicedb
  tag: "$VERSION"

config:
  datastoreEngine: $DATASTORE_TYPE
  existingSecret: $SECRET
EOF

# Add TLS if configured
if [ -n "$TLS_SECRET" ] && [ "$TLS_SECRET" != "null" ]; then
  cat >> "$OUTPUT" <<EOF

tls:
  enabled: true
  grpc:
    secretName: $TLS_SECRET
  http:
    secretName: $TLS_SECRET
EOF
fi

# Add dispatch if enabled
if [ "$DISPATCH_ENABLED" = "true" ]; then
  cat >> "$OUTPUT" <<EOF

dispatch:
  enabled: true
EOF

  if [ -n "$DISPATCH_TLS" ] && [ "$DISPATCH_TLS" != "null" ]; then
    cat >> "$OUTPUT" <<EOF

tls:
  dispatch:
    secretName: $DISPATCH_TLS
EOF
  fi
fi

# Add production defaults
cat >> "$OUTPUT" <<EOF

# Production defaults
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi

migrations:
  enabled: true

monitoring:
  enabled: true
EOF

echo "Generated Helm values: $OUTPUT"
echo ""
echo "IMPORTANT: Review and add if needed:"
echo "  - NetworkPolicy configuration"
echo "  - Ingress configuration"
echo "  - ServiceMonitor configuration"
echo "  - Resource limits (based on actual usage)"
echo ""
echo "Run: helm install spicedb charts/spicedb -f $OUTPUT --dry-run"

# Cleanup
rm /tmp/cluster.json
```

### Usage

```bash
# Make script executable
chmod +x scripts/convert-operator-to-helm.sh

# Convert SpiceDBCluster to Helm values
./scripts/convert-operator-to-helm.sh spicedb default values.yaml

# Review generated values
cat values.yaml

# Validate with Helm
helm install spicedb charts/spicedb -f values.yaml --dry-run
```

## Next Steps

1. **[Start Migration](./step-by-step.md)** - Use your converted configuration to migrate
2. **[Add Enhancements](./post-migration.md)** - Configure new Helm-only features

**Navigation**: [Overview](./index.md) | [Prerequisites](./prerequisites.md) | [Migration Steps](./step-by-step.md) | **Configuration** | [Post-Migration](./post-migration.md) | [Troubleshooting](../../guides/troubleshooting/index.md)
