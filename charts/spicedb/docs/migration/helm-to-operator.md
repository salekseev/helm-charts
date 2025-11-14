# Migration Guide: Helm Chart to SpiceDB Operator

This guide provides step-by-step instructions for migrating an existing SpiceDB deployment from the Helm chart to the SpiceDB Operator.

## Table of Contents

- [Why Migrate?](#why-migrate)
- [Prerequisites](#prerequisites)
- [Pre-Migration Checklist](#pre-migration-checklist)
- [Migration Overview](#migration-overview)
- [Step-by-Step Migration Procedure](#step-by-step migration-procedure)
- [Configuration Conversion](#configuration-conversion)
- [Rollback Procedure](#rollback-procedure)
- [Post-Migration Validation](#post-migration-validation)
- [Common Issues and Troubleshooting](#common-issues-and-troubleshooting)
- [FAQ](#faq)

## Why Migrate?

Consider migrating from Helm to the Operator if you want:

- **Automated updates**: Automatic version management with release channels
- **Simplified configuration**: 10-line CRD vs 50+ line values.yaml
- **Self-healing**: Automatic reconciliation and drift correction
- **Status reporting**: Structured health information via CRD status
- **Kubernetes-native API**: Manage SpiceDB with kubectl like any other resource

**Keep using Helm if you need:**

- NetworkPolicy for network isolation
- Ingress configuration
- GitOps with Helm-specific tooling
- Fine-grained control over resources

See [OPERATOR_COMPARISON.md](./OPERATOR_COMPARISON.md) for a detailed comparison.

## Prerequisites

### Required

1. **Kubernetes Cluster**: Version 1.19+ with admin access
2. **kubectl**: Configured to access your cluster
3. **Helm**: Version 3.12+ (to manage existing chart)
4. **Current Helm Installation**: Working SpiceDB deployment via this Helm chart
5. **Database Backup**: Recent backup of your SpiceDB datastore

### Recommended

1. **Staging Environment**: Test migration in non-production first
2. **Maintenance Window**: Plan for brief downtime during migration
3. **Monitoring**: Have monitoring/alerting in place to verify migration success

### Compatibility

- **Operator Version**: Latest stable release recommended
- **SpiceDB Version**: Operator supports v1.13.0+
- **Datastore**: PostgreSQL, CockroachDB, MySQL (Operator adds MySQL and Spanner support)

## Pre-Migration Checklist

### 1. Document Current Configuration

Export your current Helm values:

```bash
# Export current values
helm get values spicedb -o yaml > helm-values-backup.yaml

# Export full release information
helm get all spicedb > helm-release-backup.yaml

# Document current release version
helm list -n <namespace>
```

### 2. Backup Database

Create a backup of your datastore **before** proceeding:

**PostgreSQL:**

```bash
# Using pg_dump
kubectl exec -n database postgresql-0 -- \
  pg_dump -U spicedb spicedb -F custom -f /tmp/spicedb-backup.dump

# Copy backup locally
kubectl cp database/postgresql-0:/tmp/spicedb-backup.dump ./spicedb-backup.dump
```

**CockroachDB:**

```bash
# Create backup using CockroachDB BACKUP command
kubectl exec -n database cockroachdb-0 -- \
  cockroach sql --insecure -e \
  "BACKUP DATABASE spicedb TO 'nodelocal://1/spicedb-backup';"
```

### 3. Document Current State

Record current deployment information:

```bash
# Get current pod status
kubectl get pods -l app.kubernetes.io/name=spicedb -o wide

# Get current service configuration
kubectl get svc spicedb -o yaml > service-backup.yaml

# Get current secrets
kubectl get secret spicedb -o yaml > secret-backup.yaml

# Get current ConfigMaps (if any)
kubectl get configmap -l app.kubernetes.io/name=spicedb -o yaml > configmap-backup.yaml

# Document resource usage
kubectl top pods -l app.kubernetes.io/name=spicedb
```

### 4. Test in Staging

**CRITICAL**: Never perform this migration in production without testing in staging first.

1. Deploy identical Helm configuration in staging
2. Follow this guide completely in staging
3. Validate application functionality
4. Measure actual downtime
5. Document any issues encountered

### 5. Review Helm-Specific Features

Identify features you're using that are **exclusive to Helm**:

- **NetworkPolicy**: Operator doesn't manage NetworkPolicy - you'll need to create manually
- **Ingress**: Operator doesn't create Ingress - you'll need to create manually
- **ServiceMonitor**: Operator doesn't create ServiceMonitor - you'll need to create manually

See the [Configuration Conversion](#configuration-conversion) section for how to handle these.

## Migration Overview

The migration process follows these high-level steps:

1. **Install Operator**: Deploy SpiceDB Operator to cluster
2. **Convert Configuration**: Map Helm values to SpiceDBCluster CRD
3. **Create SpiceDBCluster**: Apply operator configuration (operator creates new deployment)
4. **Scale Down Helm**: Set Helm deployment to 0 replicas
5. **Verify Operator**: Ensure operator deployment is healthy
6. **Cleanup Helm**: Delete Helm release (keeping history for rollback)
7. **Recreate Helm-Only Resources**: Create NetworkPolicy, Ingress, ServiceMonitor manually

**Estimated Downtime**: 2-5 minutes (time between scaling Helm down and operator up)

**Data Loss Risk**: None (both use same database, no schema changes)

## Step-by-Step Migration Procedure

### Step 1: Install SpiceDB Operator

Install the operator in your cluster:

```bash
# Install latest operator
kubectl apply -f https://github.com/authzed/spicedb-operator/releases/latest/download/bundle.yaml

# Verify operator is running
kubectl get pods -n spicedb-operator-system

# Expected output:
# NAME                                           READY   STATUS    RESTARTS   AGE
# spicedb-operator-controller-manager-xxxxx      2/2     Running   0          30s

# Verify CRDs are installed
kubectl get crd spicedbclusters.authzed.com

# Expected output:
# NAME                              CREATED AT
# spicedbclusters.authzed.com       2024-11-11T...
```

**Note**: The operator installs into the `spicedb-operator-system` namespace by default.

### Step 2: Create Secrets for Operator

The operator requires secrets in specific formats. Convert your Helm secrets:

#### Option A: Reuse Existing Secrets (Recommended)

If your existing secrets are in the correct format, you can reference them directly:

```bash
# Check your current secret format
kubectl get secret spicedb -o yaml

# Operator expects these keys:
# - preshared-key: SpiceDB preshared key
# - datastore-uri: Database connection string
```

#### Option B: Create New Secrets

Create operator-compatible secrets:

```bash
# Extract values from Helm secret
export PRESHARED_KEY=$(kubectl get secret spicedb -o jsonpath='{.data.preshared-key}' | base64 -d)
export DATASTORE_URI=$(kubectl get secret spicedb -o jsonpath='{.data.datastore-uri}' | base64 -d)

# Create operator secret
kubectl create secret generic spicedb-operator-config \
  --from-literal=preshared-key="$PRESHARED_KEY" \
  --from-literal=datastore-uri="$DATASTORE_URI" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Step 3: Create SpiceDBCluster Manifest

Create a `spicedb-cluster.yaml` file with your configuration:

**Basic Example (PostgreSQL):**

```yaml
apiVersion: authzed.com/v1alpha1
kind: SpiceDBCluster
metadata:
  name: spicedb
  namespace: default  # Use your namespace
spec:
  # Version - must match or be compatible with Helm deployment
  version: "v1.35.0"  # Check: helm get values spicedb | grep tag

  # Update channel (stable for automatic updates within major version)
  channel: stable

  # Replicas - should match Helm replicaCount
  replicas: 3

  # Secret containing preshared key and datastore URI
  secretName: spicedb-operator-config  # Or reuse 'spicedb' if format matches

  # Datastore configuration
  datastoreEngine:
    postgres:
      connectionString:
        secretKeyRef:
          name: spicedb-operator-config  # Or your existing secret
          key: datastore-uri
```

**Advanced Example (with TLS and Dispatch):**

```yaml
apiVersion: authzed.com/v1alpha1
kind: SpiceDBCluster
metadata:
  name: spicedb
  namespace: default
spec:
  version: "v1.35.0"
  channel: stable
  replicas: 3
  secretName: spicedb-operator-config

  # TLS configuration (if you had tls.enabled: true in Helm)
  tlsSecretName: spicedb-grpc-tls  # Reference existing TLS secret

  # Dispatch clustering (if you had dispatch.enabled: true in Helm)
  dispatchCluster:
    enabled: true
    tlsSecretName: spicedb-dispatch-tls

  # Datastore configuration
  datastoreEngine:
    postgres:
      connectionString:
        secretKeyRef:
          name: spicedb-operator-config
          key: datastore-uri

  # Resource requests/limits (optional, operator sets good defaults)
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 4Gi
```

See [Configuration Conversion](#configuration-conversion) for complete mapping.

### Step 4: Apply SpiceDBCluster (Pre-validation)

Before applying, validate the manifest:

```bash
# Validate YAML syntax
kubectl apply -f spicedb-cluster.yaml --dry-run=client

# Check if operator can process it
kubectl apply -f spicedb-cluster.yaml --dry-run=server
```

### Step 5: Scale Helm Deployment to 0

This is the start of the brief downtime window:

```bash
# Scale Helm deployment to 0 replicas
kubectl scale deployment spicedb --replicas=0

# Wait for pods to terminate
kubectl wait --for=delete pod -l app.kubernetes.io/name=spicedb --timeout=60s

# Verify no pods are running
kubectl get pods -l app.kubernetes.io/name=spicedb

# Expected output: No resources found (or all terminating)
```

### Step 6: Apply SpiceDBCluster

Deploy the operator-managed cluster:

```bash
# Apply the SpiceDBCluster
kubectl apply -f spicedb-cluster.yaml

# Watch operator create resources
kubectl get spicedbcluster spicedb -w

# Expected progression:
# NAME      READY   STATUS    AGE
# spicedb   False   Pending   5s
# spicedb   False   Creating  10s
# spicedb   True    Running   45s

# Watch pods come up
kubectl get pods -l app.kubernetes.io/name=spicedb -w
```

**Downtime ends when**: First operator-managed pod is ready and serving traffic.

### Step 7: Verify Operator Deployment

Verify the operator deployment is healthy:

```bash
# Check SpiceDBCluster status
kubectl get spicedbcluster spicedb -o yaml

# Check status.conditions for health
kubectl get spicedbcluster spicedb -o jsonpath='{.status.conditions}' | jq

# Expected conditions:
# [
#   {
#     "type": "Ready",
#     "status": "True"
#   },
#   {
#     "type": "Migrated",
#     "status": "True"
#   }
# ]

# Check pods are running
kubectl get pods -l app.kubernetes.io/name=spicedb

# Expected output:
# NAME                       READY   STATUS    RESTARTS   AGE
# spicedb-0                  1/1     Running   0          2m
# spicedb-1                  1/1     Running   0          2m
# spicedb-2                  1/1     Running   0          2m

# Check logs
kubectl logs -l app.kubernetes.io/name=spicedb --tail=50
```

### Step 8: Test Connectivity

Verify SpiceDB is accessible and functional:

```bash
# Port-forward to operator-managed deployment
kubectl port-forward pod/spicedb-0 50051:50051 &

# Test with zed CLI (if installed)
export SPICEDB_TOKEN=$(kubectl get secret spicedb-operator-config -o jsonpath='{.data.preshared-key}' | base64 -d)
zed context set migrated localhost:50051 "$SPICEDB_TOKEN" --insecure
zed schema read

# Test gRPC health check
grpcurl -plaintext -d '{"service":"authzed.api.v1.SchemaService"}' \
  localhost:50051 grpc.health.v1.Health/Check

# Test HTTP health endpoint
curl -k https://localhost:8443/healthz
```

### Step 9: Delete Helm Release

Once operator deployment is verified, remove the Helm release:

```bash
# Delete Helm release but keep history for rollback
helm uninstall spicedb --keep-history

# Verify Helm release is deleted
helm list --all

# Expected output: spicedb should show as 'uninstalled'

# Clean up any orphaned resources from Helm (if any)
# These might include PVCs, Services, etc. that Helm didn't delete
kubectl get all -l app.kubernetes.io/name=spicedb
```

**WARNING**: Do **not** delete the following:

- Database (PostgreSQL/CockroachDB)
- Secrets (unless you created new ones)
- TLS certificates
- PersistentVolumeClaims (if any)

### Step 10: Recreate Helm-Only Resources

The operator doesn't create certain resources that Helm managed. Recreate them manually:

#### NetworkPolicy (if you had networkPolicy.enabled: true)

Create `spicedb-networkpolicy.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: spicedb
  namespace: default
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: spicedb
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow from ingress controller
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
    ports:
    - protocol: TCP
      port: 50051
    - protocol: TCP
      port: 8443
  # Allow from Prometheus
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
    ports:
    - protocol: TCP
      port: 9090
  # Allow inter-pod dispatch
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: spicedb
    ports:
    - protocol: TCP
      port: 50053
  egress:
  # Allow to database
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: database
    ports:
    - protocol: TCP
      port: 5432  # Or 26257 for CockroachDB
  # Allow DNS
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
```

Apply it:

```bash
kubectl apply -f spicedb-networkpolicy.yaml
```

#### Ingress (if you had ingress.enabled: true)

Create `spicedb-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: spicedb
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: spicedb.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: spicedb  # Operator creates this service
            port:
              number: 50051
  tls:
  - secretName: spicedb-tls
    hosts:
    - spicedb.example.com
```

Apply it:

```bash
kubectl apply -f spicedb-ingress.yaml
```

#### ServiceMonitor (if you had monitoring.serviceMonitor.enabled: true)

Create `spicedb-servicemonitor.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: spicedb
  namespace: default
  labels:
    prometheus: kube-prometheus  # Match your Prometheus selector
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: spicedb
  endpoints:
  - port: metrics  # Operator service includes this port
    interval: 30s
    scrapeTimeout: 10s
    path: /metrics
```

Apply it:

```bash
kubectl apply -f spicedb-servicemonitor.yaml
```

### Step 11: Post-Migration Verification

See [Post-Migration Validation](#post-migration-validation) section below.

## Configuration Conversion

Use this reference to convert Helm `values.yaml` to SpiceDBCluster spec:

### Basic Configuration

| Helm values.yaml | SpiceDBCluster spec | Notes |
|-----------------|---------------------|-------|
| `replicaCount: 3` | `spec.replicas: 3` | Direct mapping |
| `image.tag: "v1.35.0"` | `spec.version: "v1.35.0"` | Operator manages image |
| `config.presharedKey` | `spec.secretName` | Reference secret with `preshared-key` key |
| N/A | `spec.channel: stable` | Operator-only feature |

### Datastore Configuration

**PostgreSQL:**

Helm:

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

Operator:

```yaml
spec:
  datastoreEngine:
    postgres:
      connectionString:
        secretKeyRef:
          name: postgres-uri
          key: datastore-uri
          # Secret value format:
          # postgresql://spicedb:changeme@postgres.database.svc.cluster.local:5432/spicedb?sslmode=require
```

**CockroachDB:**

Helm:

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

Operator:

```yaml
spec:
  datastoreEngine:
    postgres:  # CockroachDB uses postgres protocol
      connectionString:
        secretKeyRef:
          name: cockroachdb-uri
          key: datastore-uri
          # Secret value format:
          # postgresql://spicedb@cockroachdb-public.database.svc.cluster.local:26257/spicedb?sslmode=verify-full
```

**Memory (Development):**

Helm:

```yaml
config:
  datastoreEngine: memory
```

Operator:

```yaml
spec:
  datastoreEngine:
    memory: {}
```

### TLS Configuration

Helm:

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

Operator:

```yaml
spec:
  tlsSecretName: spicedb-grpc-tls  # Unified secret for gRPC/HTTP
  dispatchCluster:
    enabled: true
    tlsSecretName: spicedb-dispatch-tls
```

**Note**: Operator uses a single TLS secret for both gRPC and HTTP endpoints.

### Dispatch Configuration

Helm:

```yaml
dispatch:
  enabled: true
  clusterName: "production-cluster"
  upstreamCASecretName: dispatch-ca
```

Operator:

```yaml
spec:
  dispatchCluster:
    enabled: true
    tlsSecretName: spicedb-dispatch-tls
  # Note: clusterName and upstreamCASecretName not directly supported in basic operator config
```

### Resource Configuration

Helm:

```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

Operator:

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

### High Availability Configuration

Helm:

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

Operator:

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

### Features NOT in Operator

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

Usage:

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

## Rollback Procedure

If migration fails or you need to rollback to Helm:

### Quick Rollback (During Migration)

If still in maintenance window and operator deployment fails:

```bash
# Delete SpiceDBCluster
kubectl delete spicedbcluster spicedb

# Wait for operator to clean up
kubectl wait --for=delete pod -l app.kubernetes.io/name=spicedb --timeout=60s

# Scale Helm deployment back up
kubectl scale deployment spicedb --replicas=3

# Wait for Helm pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=spicedb --timeout=120s

# Verify Helm deployment is working
kubectl get pods -l app.kubernetes.io/name=spicedb
```

### Full Rollback (After Helm Uninstall)

If you've already run `helm uninstall` but kept history:

```bash
# Check Helm history
helm history spicedb

# Rollback to previous release
helm rollback spicedb

# Verify Helm deployment is restored
kubectl get pods -l app.kubernetes.io/name=spicedb

# Delete SpiceDBCluster if still exists
kubectl delete spicedbcluster spicedb --ignore-not-found

# Uninstall operator if no longer needed
kubectl delete -f https://github.com/authzed/spicedb-operator/releases/latest/download/bundle.yaml
```

### Complete Rollback (Fresh Helm Install)

If Helm history was deleted or rollback fails:

```bash
# Delete operator deployment
kubectl delete spicedbcluster spicedb

# Reinstall with Helm using backed-up values
helm install spicedb charts/spicedb -f helm-values-backup.yaml

# Restore any NetworkPolicy, Ingress, ServiceMonitor
kubectl apply -f service-backup.yaml
kubectl apply -f networkpolicy-backup.yaml  # If you backed these up
kubectl apply -f ingress-backup.yaml
```

## Post-Migration Validation

### 1. Check Pod Status

```bash
# All pods should be Running
kubectl get pods -l app.kubernetes.io/name=spicedb

# Expected output:
# NAME        READY   STATUS    RESTARTS   AGE
# spicedb-0   1/1     Running   0          5m
# spicedb-1   1/1     Running   0          5m
# spicedb-2   1/1     Running   0          5m

# Check for restarts (should be 0 or low)
kubectl get pods -l app.kubernetes.io/name=spicedb -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}'
```

### 2. Check SpiceDBCluster Status

```bash
# Check overall status
kubectl get spicedbcluster spicedb

# Expected output:
# NAME      READY   STATUS    AGE
# spicedb   True    Running   5m

# Check detailed status
kubectl get spicedbcluster spicedb -o jsonpath='{.status}' | jq

# Expected conditions:
# {
#   "conditions": [
#     {
#       "type": "Ready",
#       "status": "True",
#       "reason": "AllReplicasReady"
#     },
#     {
#       "type": "Migrated",
#       "status": "True",
#       "reason": "MigrationComplete"
#     }
#   ],
#   "availableReplicas": 3,
#   "version": "v1.35.0"
# }
```

### 3. Test gRPC Connectivity

```bash
# Port-forward
kubectl port-forward pod/spicedb-0 50051:50051 &

# Get preshared key
export SPICEDB_TOKEN=$(kubectl get secret spicedb-operator-config -o jsonpath='{.data.preshared-key}' | base64 -d)

# Test with zed (if installed)
zed context set migrated localhost:50051 "$SPICEDB_TOKEN" --insecure

# Read schema (should succeed)
zed schema read

# Test permission check (if you have schema)
zed permission check document:1 view user:alice
```

### 4. Test HTTP Connectivity

```bash
# Port-forward HTTP
kubectl port-forward pod/spicedb-0 8443:8443 &

# Check health endpoint
curl -k https://localhost:8443/healthz

# Expected output:
# {"status":"ok"}

# Check metrics
curl -k https://localhost:8443/metrics | grep spicedb
```

### 5. Verify Database Connectivity

```bash
# Check logs for database connection
kubectl logs -l app.kubernetes.io/name=spicedb --tail=100 | grep -i database

# Should see successful connection messages
# No error messages about connections

# Verify migrations ran
kubectl logs -l app.kubernetes.io/name=spicedb --tail=100 | grep -i migration
```

### 6. Monitor Logs

```bash
# Check for errors in last 10 minutes
kubectl logs -l app.kubernetes.io/name=spicedb --since=10m | grep -i error

# Monitor realtime logs
kubectl logs -l app.kubernetes.io/name=spicedb -f

# Look for:
# - Successful startup messages
# - No connection errors
# - No authentication errors
# - No migration errors
```

### 7. Verify NetworkPolicy (if created)

```bash
# Check NetworkPolicy exists
kubectl get networkpolicy spicedb

# Test connectivity from allowed namespace (e.g., ingress)
kubectl run -n ingress-nginx test-pod --rm -it --image=curlimages/curl -- \
  curl -v http://spicedb.default.svc.cluster.local:50051

# Test connectivity from denied namespace (should fail)
kubectl run -n other test-pod --rm -it --image=curlimages/curl -- \
  curl -v http://spicedb.default.svc.cluster.local:50051
```

### 8. Verify Ingress (if created)

```bash
# Check Ingress exists
kubectl get ingress spicedb

# Get Ingress URL
export INGRESS_URL=$(kubectl get ingress spicedb -o jsonpath='{.spec.rules[0].host}')

# Test external access (requires DNS and cert setup)
grpcurl -d '{"service":"authzed.api.v1.SchemaService"}' \
  $INGRESS_URL:443 grpc.health.v1.Health/Check
```

### 9. Verify Metrics Collection

```bash
# Check ServiceMonitor exists (if created)
kubectl get servicemonitor spicedb

# Query Prometheus for SpiceDB metrics (if Prometheus installed)
curl -s 'http://prometheus:9090/api/v1/query?query=up{job="spicedb"}' | jq

# Expected output should show targets up:
# {
#   "status": "success",
#   "data": {
#     "result": [
#       {
#         "metric": {
#           "job": "spicedb"
#         },
#         "value": [timestamp, "1"]
#       }
#     ]
#   }
# }
```

### 10. Performance Baseline

Compare performance before and after migration:

```bash
# Measure latency with zed
time zed permission check document:1 view user:alice

# Expected: Similar latency to pre-migration

# Check resource usage
kubectl top pods -l app.kubernetes.io/name=spicedb

# Expected: Similar CPU/memory to pre-migration
```

## Common Issues and Troubleshooting

### Issue: SpiceDBCluster stuck in "Pending" status

**Symptoms:**

```bash
kubectl get spicedbcluster spicedb
# NAME      READY   STATUS    AGE
# spicedb   False   Pending   5m
```

**Diagnosis:**

```bash
# Check operator logs
kubectl logs -n spicedb-operator-system -l control-plane=controller-manager --tail=100

# Check SpiceDBCluster events
kubectl describe spicedbcluster spicedb
```

**Common Causes:**

1. **Invalid secret reference**: Secret doesn't exist or has wrong keys

   ```bash
   # Verify secret exists
   kubectl get secret spicedb-operator-config

   # Check secret has required keys
   kubectl get secret spicedb-operator-config -o jsonpath='{.data}' | jq 'keys'
   # Expected: ["datastore-uri", "preshared-key"]
   ```

2. **Invalid version**: Version doesn't exist or is incompatible

   ```bash
   # Check available versions at https://github.com/authzed/spicedb/releases
   # Update spec.version to valid version
   ```

3. **Database connection failure**: Can't connect to datastore

   ```bash
   # Test database connection from cluster
   kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
     psql "$DATASTORE_URI"
   ```

**Resolution:**

```bash
# Fix the issue (update secret, version, etc.)
# Update SpiceDBCluster
kubectl apply -f spicedb-cluster.yaml

# Operator will retry automatically
```

### Issue: Pods crash-looping after migration

**Symptoms:**

```bash
kubectl get pods -l app.kubernetes.io/name=spicedb
# NAME        READY   STATUS             RESTARTS   AGE
# spicedb-0   0/1     CrashLoopBackOff   5          5m
```

**Diagnosis:**

```bash
# Check pod logs
kubectl logs spicedb-0 --previous

# Check pod events
kubectl describe pod spicedb-0
```

**Common Causes:**

1. **Missing secret**: Preshared key or datastore URI not found

   ```bash
   # Check logs for error like:
   # "failed to load secret"

   # Verify secret exists and is referenced correctly
   kubectl get secret spicedb-operator-config
   ```

2. **Database migration failure**: Migration failed during startup

   ```bash
   # Check logs for migration errors
   kubectl logs spicedb-0 | grep -i migration

   # Manually run migration to see error
   kubectl run -it --rm spicedb-migrate \
     --image=authzed/spicedb:v1.35.0 \
     --restart=Never -- \
     migrate head --datastore-engine postgres --datastore-conn-uri "$DATASTORE_URI"
   ```

3. **TLS certificate issues**: Invalid or missing TLS certificates

   ```bash
   # Check TLS secret exists
   kubectl get secret spicedb-grpc-tls

   # Verify certificate is valid
   kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
   ```

**Resolution:**

```bash
# Fix the underlying issue
# Delete the pod to force restart
kubectl delete pod spicedb-0

# Operator will recreate it automatically
```

### Issue: Service ports don't match

**Symptoms:**
Clients can't connect using same port as before migration

**Diagnosis:**

```bash
# Check operator-created service
kubectl get svc spicedb -o yaml

# Compare to Helm service backup
diff <(kubectl get svc spicedb -o yaml) service-backup.yaml
```

**Common Causes:**
Operator creates service with standard ports that may differ from Helm customization

**Resolution:**

```bash
# Option 1: Update client configuration to use new ports
# Option 2: Patch service to use original ports
kubectl patch svc spicedb --type=json -p='[
  {"op": "replace", "path": "/spec/ports/0/port", "value": 50051}
]'

# Option 3: Create a separate service with original ports pointing to operator pods
```

### Issue: NetworkPolicy blocks traffic after migration

**Symptoms:**
Clients can't connect even though pods are ready

**Diagnosis:**

```bash
# Check if NetworkPolicy exists
kubectl get networkpolicy spicedb

# Test connectivity
kubectl run -it --rm test --image=curlimages/curl -- \
  curl -v http://spicedb:50051
```

**Common Causes:**
NetworkPolicy from Helm may not match operator-created pod labels

**Resolution:**

```bash
# Check pod labels created by operator
kubectl get pods -l app.kubernetes.io/name=spicedb --show-labels

# Update NetworkPolicy podSelector to match
kubectl edit networkpolicy spicedb

# Or recreate NetworkPolicy with correct labels
```

### Issue: Ingress returns 503 after migration

**Symptoms:**
External clients get 503 Service Unavailable

**Diagnosis:**

```bash
# Check Ingress configuration
kubectl get ingress spicedb -o yaml

# Check Ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100 | grep spicedb

# Check service endpoints
kubectl get endpoints spicedb
```

**Common Causes:**

1. Ingress backend points to wrong service
2. Service selector doesn't match operator pods
3. Ingress annotation incompatible with operator service

**Resolution:**

```bash
# Verify Ingress backend
kubectl get ingress spicedb -o jsonpath='{.spec.rules[0].http.paths[0].backend}'

# Should point to operator-created service
# Update if incorrect:
kubectl patch ingress spicedb --type=json -p='[
  {"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "spicedb"}
]'
```

### Issue: Metrics not appearing in Prometheus

**Symptoms:**
Prometheus doesn't scrape SpiceDB metrics

**Diagnosis:**

```bash
# Check ServiceMonitor
kubectl get servicemonitor spicedb

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-k8s 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="spicedb")'

# Check if manual curl works
kubectl port-forward pod/spicedb-0 9090:9090 &
curl http://localhost:9090/metrics
```

**Common Causes:**

1. ServiceMonitor selector doesn't match service labels
2. Service doesn't have metrics port
3. Prometheus serviceMonitorSelector doesn't match ServiceMonitor labels

**Resolution:**

```bash
# Check service labels
kubectl get svc spicedb --show-labels

# Update ServiceMonitor selector
kubectl edit servicemonitor spicedb

# Add labels to ServiceMonitor if needed
kubectl label servicemonitor spicedb prometheus=kube-prometheus
```

## FAQ

### Can I migrate without downtime?

**No** - Brief downtime (2-5 minutes) is unavoidable during migration. Both Helm and Operator deployments manage the same statefulset, and you cannot run both simultaneously without conflicts.

For zero-downtime migration, you would need:

1. Blue-green deployment (separate databases)
2. Dual-write to both deployments
3. Cutover traffic
4. This is complex and not recommended for most use cases

### Will I lose data during migration?

**No** - The migration doesn't touch your database. Both Helm and Operator deployments connect to the same PostgreSQL/CockroachDB database. Your permissions data is safe.

**However**, always backup before migrating as a safety precaution.

### Can I use both Helm and Operator in the same cluster?

**Yes**, but not for the same SpiceDB instance. You can have:

- Helm-managed SpiceDB in namespace `production`
- Operator-managed SpiceDB in namespace `staging`

But you cannot have both managing the same deployment simultaneously.

### What happens to my TLS certificates?

**They are reused** - The operator references the same secret names. Your existing TLS secrets (`spicedb-grpc-tls`, etc.) continue to work.

Note: Operator uses a single secret for both gRPC and HTTP TLS, while Helm allows separate secrets.

### Do I need to reinstall the operator for each cluster?

**Yes** - The operator is installed cluster-wide. Each Kubernetes cluster needs its own operator installation.

After operator is installed once, you can create multiple `SpiceDBCluster` resources in different namespaces.

### Can I migrate back to Helm later?

**Yes** - The migration is reversible. See [MIGRATION_OPERATOR_TO_HELM.md](./MIGRATION_OPERATOR_TO_HELM.md) for the reverse migration guide.

### Will automatic updates break my deployment?

**No** - The operator only updates within your specified channel:

- `channel: stable` - Updates to latest stable (e.g., v1.35.0 → v1.35.1 → v1.36.0)
- `channel: v1.35.x` - Only patch updates (e.g., v1.35.0 → v1.35.1, not v1.36.0)
- `channel: manual` - No automatic updates, suggestions only

You can pin to specific version with `spec.version` and `channel: manual`.

### How do I disable automatic updates?

Set `channel: manual` in SpiceDBCluster:

```yaml
spec:
  version: "v1.35.0"
  channel: manual  # Only suggests updates, doesn't apply them
```

Then manually update `spec.version` when ready to upgrade.

### What if my Helm chart is heavily customized?

The operator may not support all customizations. Check the [Configuration Conversion](#configuration-conversion) section.

If you have unsupported customizations:

1. Create additional Kubernetes resources manually (NetworkPolicy, Ingress, etc.)
2. Use pod/service patches to add custom configuration
3. Consider staying with Helm if operator doesn't meet your needs

### Can I test the migration in place?

**Not recommended** - Always test in a staging environment first.

If you must test in production:

1. Scale Helm to 0 during off-hours
2. Apply SpiceDBCluster
3. Verify it works
4. Either continue migration or rollback

### How long does migration take?

**Planning**: 1-2 hours (reading docs, preparing manifests, testing in staging)
**Execution**: 10-15 minutes (actual migration steps)
**Downtime**: 2-5 minutes (time between Helm scale-down and operator ready)

### What versions are supported?

- **Operator**: Latest stable release recommended
- **SpiceDB**: v1.13.0+ supported by operator
- **Kubernetes**: 1.19+ required
- **Helm Chart**: Any version (this migration guide applies to all)

### Where can I get help?

- **Operator Issues**: <https://github.com/authzed/spicedb-operator/issues>
- **Helm Chart Issues**: <https://github.com/salekseev/helm-charts/issues>
- **SpiceDB Discord**: <https://authzed.com/discord>
- **Migration Help**: Open issue with [migration] tag

## Additional Resources

- [SpiceDB Operator Documentation](https://github.com/authzed/spicedb-operator/tree/main/docs)
- [OPERATOR_COMPARISON.md](./OPERATOR_COMPARISON.md) - Feature comparison
- [MIGRATION_OPERATOR_TO_HELM.md](./MIGRATION_OPERATOR_TO_HELM.md) - Reverse migration
- [Helm Chart Documentation](./README.md)
- [SpiceDB Documentation](https://authzed.com/docs)

## Changelog

- **2024-11-11**: Initial version
