# Step-by-Step Migration Procedure

**Navigation**: [Overview](./index.md) | [Prerequisites](./prerequisites.md) | **Migration Steps** | [Configuration](./configuration-conversion.md) | [Post-Migration](./post-migration.md) | [Troubleshooting](../../guides/troubleshooting/index.md)

This guide provides the core migration procedure from SpiceDB Operator to Helm chart.

## Before You Begin

Ensure you've completed the [Prerequisites](./prerequisites.md) checklist:

- Database backup created
- Current configuration documented
- Tested in staging environment

## Migration Steps

### Step 1: Create Helm values.yaml

Convert your SpiceDBCluster configuration to Helm values. Use the [Configuration Conversion](./configuration-conversion.md) guide as reference.

**Example values.yaml (basic PostgreSQL):**

```yaml
# values.yaml - converted from SpiceDBCluster

# Replicas from spec.replicas
replicaCount: 3

# Version from spec.version
image:
  repository: authzed/spicedb
  tag: "v1.35.0"

# Datastore configuration
config:
  datastoreEngine: postgres

  # Option 1: Use existing secret (recommended)
  existingSecret: spicedb-operator-config

  # Option 2: Specify connection details
  # datastore:
  #   hostname: postgres.database.svc.cluster.local
  #   port: 5432
  #   username: spicedb
  #   database: spicedb
  #   sslMode: require

# Enable production features
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1

# Production resource limits
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi

# Enable migrations
migrations:
  enabled: true

# Enable monitoring
monitoring:
  enabled: true
```

**Example values.yaml (with TLS and dispatch):**

```yaml
replicaCount: 3

image:
  tag: "v1.35.0"

config:
  datastoreEngine: postgres
  existingSecret: spicedb-operator-config

# TLS configuration (from operator spec.tlsSecretName)
tls:
  enabled: true
  grpc:
    secretName: spicedb-grpc-tls
  http:
    secretName: spicedb-grpc-tls  # Operator uses same secret for both
  dispatch:
    secretName: spicedb-dispatch-tls

# Dispatch clustering (from operator spec.dispatchCluster)
dispatch:
  enabled: true

podDisruptionBudget:
  enabled: true

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

See [Configuration Conversion](./configuration-conversion.md) for complete mapping.

### Step 2: Create Required Secrets

Ensure secrets are in Helm-compatible format:

#### Option A: Reuse Operator Secrets (Recommended)

The operator secrets should work with Helm if they have the correct keys:

```bash
# Check operator secret format
kubectl get secret spicedb-operator-config -o jsonpath='{.data}' | jq 'keys'

# Expected keys: ["datastore-uri", "preshared-key"]
# Helm expects: ["datastore-uri", "preshared-key"]
# Compatible - can reuse directly

# In values.yaml:
# config:
#   existingSecret: spicedb-operator-config
```

#### Option B: Create New Helm Secret

If you need to create a new secret or modify format:

```bash
# Extract from operator secret
export PRESHARED_KEY=$(kubectl get secret spicedb-operator-config -o jsonpath='{.data.preshared-key}' | base64 -d)
export DATASTORE_URI=$(kubectl get secret spicedb-operator-config -o jsonpath='{.data.datastore-uri}' | base64 -d)

# Create Helm-compatible secret
kubectl create secret generic spicedb-helm \
  --from-literal=preshared-key="$PRESHARED_KEY" \
  --from-literal=datastore-uri="$DATASTORE_URI" \
  --dry-run=client -o yaml | kubectl apply -f -

# In values.yaml:
# config:
#   existingSecret: spicedb-helm
```

### Step 3: Create TLS Secrets (if using TLS)

Helm uses separate secrets for different TLS endpoints. If operator used a unified secret, you may need to split it:

```bash
# Check operator TLS secret
kubectl get secret spicedb-grpc-tls -o yaml

# Operator uses one secret for gRPC + HTTP
# Helm can use the same secret for both endpoints

# In values.yaml:
# tls:
#   enabled: true
#   grpc:
#     secretName: spicedb-grpc-tls  # Reuse operator secret
#   http:
#     secretName: spicedb-grpc-tls  # Reuse same secret
```

### Step 4: Validate Helm Configuration

Before proceeding, validate your Helm configuration:

```bash
# Test template rendering
helm template spicedb charts/spicedb -f values.yaml > rendered-templates.yaml

# Review rendered templates
less rendered-templates.yaml

# Dry-run install
helm install spicedb charts/spicedb -f values.yaml --dry-run

# Check for any errors or warnings
```

### Step 5: Scale SpiceDBCluster to 0 Replicas

This is the start of the brief downtime window:

```bash
# Scale operator deployment to 0
kubectl patch spicedbcluster spicedb --type=merge -p '{"spec":{"replicas":0}}'

# Wait for operator to scale down pods
kubectl wait --for=delete pod -l app.kubernetes.io/name=spicedb --timeout=60s

# Verify no pods are running
kubectl get pods -l app.kubernetes.io/name=spicedb

# Expected output: No resources found (or all terminating)

# Verify SpiceDBCluster status
kubectl get spicedbcluster spicedb -o jsonpath='{.status.replicas}'
# Expected: 0
```

### Step 6: Install Helm Chart

Deploy SpiceDB with Helm:

```bash
# Install Helm chart
helm install spicedb charts/spicedb -f values.yaml

# Watch Helm deployment
helm status spicedb --show-resources

# Watch pods come up
kubectl get pods -l app.kubernetes.io/name=spicedb -w

# Expected progression:
# NAME                       READY   STATUS    RESTARTS   AGE
# spicedb-xxxxx-yyyyy        0/1     Pending   0          5s
# spicedb-xxxxx-yyyyy        0/1     Running   0          10s
# spicedb-xxxxx-yyyyy        1/1     Running   0          25s
```

**Downtime ends when**: First Helm-managed pod is ready and serving traffic.

### Step 7: Verify Helm Deployment

Verify the Helm deployment is healthy:

```bash
# Check Helm release status
helm status spicedb

# Check pods are running
kubectl get pods -l app.kubernetes.io/name=spicedb

# Expected output:
# NAME                       READY   STATUS    RESTARTS   AGE
# spicedb-xxxxx-yyyyy        1/1     Running   0          2m
# spicedb-xxxxx-zzzzz        1/1     Running   0          2m
# spicedb-xxxxx-aaaaa        1/1     Running   0          2m

# Check service exists
kubectl get svc spicedb

# Check logs for errors
kubectl logs -l app.kubernetes.io/name=spicedb --tail=50 | grep -i error

# Should see no errors, only normal startup logs
```

### Step 8: Test Connectivity

Verify SpiceDB is accessible and functional:

```bash
# Port-forward to Helm deployment
kubectl port-forward deployment/spicedb 50051:50051 &

# Test with zed CLI
export SPICEDB_TOKEN=$(kubectl get secret spicedb-helm -o jsonpath='{.data.preshared-key}' | base64 -d)
zed context set helm-migrated localhost:50051 "$SPICEDB_TOKEN" --insecure
zed schema read

# Test gRPC health
grpcurl -plaintext -d '{"service":"authzed.api.v1.SchemaService"}' \
  localhost:50051 grpc.health.v1.Health/Check

# Test HTTP health
curl -k https://localhost:8443/healthz

# Expected output:
# {"status":"ok"}
```

### Step 9: Delete SpiceDBCluster

Once Helm deployment is verified, delete the operator resource:

```bash
# Delete SpiceDBCluster (operator will not delete database)
kubectl delete spicedbcluster spicedb

# Verify SpiceDBCluster is gone
kubectl get spicedbcluster

# Expected output: No resources found

# Verify operator deleted its resources
kubectl get all -l app.kubernetes.io/name=spicedb

# Should only see Helm-created resources now
```

**Note**: Deleting SpiceDBCluster does **not** delete:

- The database (PostgreSQL/CockroachDB)
- Secrets
- TLS certificates
- PersistentVolumeClaims

### Step 10: Uninstall Operator (Optional)

If you're not using the operator for any other SpiceDB deployments:

```bash
# Check for other SpiceDBCluster resources
kubectl get spicedbcluster --all-namespaces

# If no other clusters, uninstall operator
kubectl delete -f https://github.com/authzed/spicedb-operator/releases/latest/download/bundle.yaml

# Verify operator is removed
kubectl get pods -n spicedb-operator-system

# Expected output: No resources found (or namespace being deleted)

# Verify CRDs are removed
kubectl get crd spicedbclusters.authzed.com

# Expected output: Error from server (NotFound)
```

**Warning**: Only uninstall the operator if you're certain no other SpiceDBCluster resources exist in the cluster.

## Next Steps

After completing the migration:

1. **[Add Post-Migration Enhancements](./post-migration.md)** - Add NetworkPolicy, Ingress, ServiceMonitor
2. **[Review Troubleshooting](../../guides/troubleshooting/index.md)** - If you encounter any issues

**Navigation**: [Overview](./index.md) | [Prerequisites](./prerequisites.md) | **Migration Steps** | [Configuration](./configuration-conversion.md) | [Post-Migration](./post-migration.md) | [Troubleshooting](../../guides/troubleshooting/index.md)
