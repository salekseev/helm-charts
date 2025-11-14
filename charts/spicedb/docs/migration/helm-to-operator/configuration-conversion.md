# Configuration Conversion Reference

This document provides a complete reference for converting Helm chart
configuration to SpiceDB Operator configuration.

## Navigation

- [Overview](./index.md)
- [Prerequisites](./prerequisites.md)
- [Step-by-Step Migration](./step-by-step.md)
- **Configuration Conversion** (this page)
- [Post-Migration Validation](./post-migration.md)
- [Troubleshooting](../../guides/troubleshooting/index.md)

## Basic Configuration Mapping

| Helm values.yaml | SpiceDBCluster spec | Notes |
|-----------------|---------------------|-------|
| `replicaCount: 3` | `spec.replicas: 3` | Direct mapping |
| `image.tag: "v1.35.0"` | `spec.version: "v1.35.0"` | Operator manages image |
| `config.presharedKey` | `spec.secretName` | Reference secret with `preshared-key` key |
| N/A | `spec.channel: stable` | Operator-only feature for auto-updates |

## Datastore Configuration

### PostgreSQL

**Helm values.yaml:**

```yaml
config:
  datastoreEngine: postgres
  datastore:
    hostname: postgres.database.svc.cluster.local
    port: 5432
    username: spicedb
    password: changeme
    database: spicedb
    sslMode: require
```

**Operator SpiceDBCluster:**

```yaml
spec:
  datastoreEngine:
    postgres:
      connectionString:
        secretKeyRef:
          name: postgres-uri
          key: datastore-uri
```

**Secret value format:**

```text
postgresql://spicedb:changeme@postgres.database.svc.cluster.local:5432/spicedb?sslmode=require
```

### CockroachDB

**Helm values.yaml:**

```yaml
config:
  datastoreEngine: cockroachdb
  datastore:
    hostname: cockroachdb-public.database.svc.cluster.local
    port: 26257
    username: spicedb
    database: spicedb
    sslMode: verify-full
```

**Operator SpiceDBCluster:**

```yaml
spec:
  datastoreEngine:
    postgres:  # CockroachDB uses postgres protocol
      connectionString:
        secretKeyRef:
          name: cockroachdb-uri
          key: datastore-uri
```

**Secret value format:**

```text
postgresql://spicedb@cockroachdb-public.database.svc.cluster.local:26257/spicedb?sslmode=verify-full
```

### Memory (Development Only)

**Helm values.yaml:**

```yaml
config:
  datastoreEngine: memory
```

**Operator SpiceDBCluster:**

```yaml
spec:
  datastoreEngine:
    memory: {}
```

## TLS Configuration

### Helm Configuration

```yaml
tls:
  enabled: true
  grpc:
    secretName: spicedb-grpc-tls
  http:
    secretName: spicedb-http-tls
  dispatch:
    secretName: spicedb-dispatch-tls
```

### Operator Configuration

```yaml
spec:
  tlsSecretName: spicedb-grpc-tls  # Unified secret for gRPC/HTTP
  dispatchCluster:
    enabled: true
    tlsSecretName: spicedb-dispatch-tls
```

**Important Note**: Operator uses a single TLS secret for both gRPC and HTTP
endpoints, while Helm allows separate secrets. If you have different secrets,
you'll need to consolidate them.

## Dispatch Configuration

### Helm Configuration

```yaml
dispatch:
  enabled: true
  clusterName: "production-cluster"
  upstreamCASecretName: dispatch-ca
```

### Operator Configuration

```yaml
spec:
  dispatchCluster:
    enabled: true
    tlsSecretName: spicedb-dispatch-tls
```

**Note**: The operator's basic configuration doesn't directly expose
`clusterName` and `upstreamCASecretName` parameters. Check operator
documentation for advanced dispatch configuration.

## Resource Configuration

### Helm Configuration

```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

### Operator Configuration

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

**Note**: Direct mapping. Operator sets reasonable defaults if not specified.

## High Availability Configuration

### Helm Configuration

```yaml
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
```

### Operator Configuration

```yaml
spec:
  replicas: 3  # PDB created automatically by operator

  # HPA support (check operator version for availability)
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 80
```

**Note**: The operator automatically creates a PodDisruptionBudget when replicas
> 1.

## Features NOT in Operator

These Helm features must be recreated manually after migration:

| Feature | Helm values.yaml | Manual Resource |
|---------|-----------------|-----------------|
| NetworkPolicy | `networkPolicy.enabled: true` | Create NetworkPolicy YAML |
| Ingress | `ingress.enabled: true` | Create Ingress YAML |
| ServiceMonitor | `monitoring.serviceMonitor.enabled: true` | Create ServiceMonitor YAML |
| Custom Annotations | `podAnnotations` | Patch operator-created pods |
| Custom Labels | `podLabels` | Patch operator-created pods |

## Conversion Script

We provide a helper script to convert Helm values to SpiceDBCluster manifest:

```bash
#!/bin/bash
# scripts/convert-helm-to-operator.sh

set -e

if [ $# -lt 1 ]; then
  echo "Usage: $0 <helm-values.yaml> [output-file.yaml]"
  exit 1
fi

HELM_VALUES="$1"
OUTPUT="${2:-spicedb-cluster.yaml}"

# Extract values (requires yq: https://github.com/mikefarah/yq)
REPLICA_COUNT=$(yq eval '.replicaCount // 3' "$HELM_VALUES")
IMAGE_TAG=$(yq eval '.image.tag // "v1.35.0"' "$HELM_VALUES")
DATASTORE_ENGINE=$(yq eval '.config.datastoreEngine // "memory"' "$HELM_VALUES")
TLS_ENABLED=$(yq eval '.tls.enabled // false' "$HELM_VALUES")
DISPATCH_ENABLED=$(yq eval '.dispatch.enabled // false' "$HELM_VALUES")

# Generate SpiceDBCluster manifest
cat > "$OUTPUT" <<EOF
apiVersion: authzed.com/v1alpha1
kind: SpiceDBCluster
metadata:
  name: spicedb
  namespace: default  # TODO: Update namespace
spec:
  version: "$IMAGE_TAG"
  channel: stable
  replicas: $REPLICA_COUNT
  secretName: spicedb-operator-config  # TODO: Update secret name
EOF

# Add datastore configuration
if [ "$DATASTORE_ENGINE" = "postgres" ] || [ "$DATASTORE_ENGINE" = "cockroachdb" ]; then
  cat >> "$OUTPUT" <<EOF
  datastoreEngine:
    postgres:
      connectionString:
        secretKeyRef:
          name: spicedb-operator-config  # TODO: Update secret name
          key: datastore-uri
EOF
elif [ "$DATASTORE_ENGINE" = "memory" ]; then
  cat >> "$OUTPUT" <<EOF
  datastoreEngine:
    memory: {}
EOF
fi

# Add TLS if enabled
if [ "$TLS_ENABLED" = "true" ]; then
  TLS_SECRET=$(yq eval '.tls.grpc.secretName // "spicedb-grpc-tls"' "$HELM_VALUES")
  cat >> "$OUTPUT" <<EOF
  tlsSecretName: $TLS_SECRET
EOF
fi

# Add dispatch if enabled
if [ "$DISPATCH_ENABLED" = "true" ]; then
  DISPATCH_TLS=$(yq eval '.tls.dispatch.secretName // "spicedb-dispatch-tls"' "$HELM_VALUES")
  cat >> "$OUTPUT" <<EOF
  dispatchCluster:
    enabled: true
    tlsSecretName: $DISPATCH_TLS
EOF
fi

echo "Generated SpiceDBCluster manifest: $OUTPUT"
echo ""
echo "⚠️  IMPORTANT: Review and update the following:"
echo "  - namespace"
echo "  - secretName references"
echo "  - Create secrets with correct keys (preshared-key, datastore-uri)"
echo ""
echo "Run: kubectl apply -f $OUTPUT --dry-run=client"
```

### Using the Conversion Script

```bash
# Make script executable
chmod +x scripts/convert-helm-to-operator.sh

# Convert your Helm values
helm get values spicedb -o yaml > current-values.yaml
./scripts/convert-helm-to-operator.sh current-values.yaml spicedb-cluster.yaml

# Review generated manifest
cat spicedb-cluster.yaml

# Validate
kubectl apply -f spicedb-cluster.yaml --dry-run=client
```

## Complete Examples

### Example 1: Simple Production (PostgreSQL)

**Helm values.yaml:**

```yaml
replicaCount: 3
image:
  tag: "v1.35.0"
config:
  datastoreEngine: postgres
  datastore:
    hostname: postgres.database.svc.cluster.local
    port: 5432
    username: spicedb
    database: spicedb
    sslMode: require
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

**Operator spicedb-cluster.yaml:**

```yaml
apiVersion: authzed.com/v1alpha1
kind: SpiceDBCluster
metadata:
  name: spicedb
  namespace: production
spec:
  version: "v1.35.0"
  channel: stable
  replicas: 3
  secretName: spicedb-config
  datastoreEngine:
    postgres:
      connectionString:
        secretKeyRef:
          name: spicedb-config
          key: datastore-uri
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 4Gi
```

### Example 2: High Security (TLS + Dispatch)

**Helm values.yaml:**

```yaml
replicaCount: 5
image:
  tag: "v1.35.0"
tls:
  enabled: true
  grpc:
    secretName: spicedb-grpc-tls
  dispatch:
    secretName: spicedb-dispatch-tls
dispatch:
  enabled: true
  clusterName: "production-cluster"
config:
  datastoreEngine: postgres
  datastore:
    hostname: postgres.database.svc.cluster.local
    port: 5432
    database: spicedb
    sslMode: verify-full
```

**Operator spicedb-cluster.yaml:**

```yaml
apiVersion: authzed.com/v1alpha1
kind: SpiceDBCluster
metadata:
  name: spicedb
  namespace: production
spec:
  version: "v1.35.0"
  channel: stable
  replicas: 5
  secretName: spicedb-config
  tlsSecretName: spicedb-grpc-tls
  dispatchCluster:
    enabled: true
    tlsSecretName: spicedb-dispatch-tls
  datastoreEngine:
    postgres:
      connectionString:
        secretKeyRef:
          name: spicedb-config
          key: datastore-uri
```

## Next Steps

After converting your configuration, proceed to
[Step-by-Step Migration](./step-by-step.md) to execute the migration.
