# Migration Guide: SpiceDB Operator to Helm Chart

This guide provides step-by-step instructions for migrating an existing SpiceDB deployment from the SpiceDB Operator to the Helm chart.

## Table of Contents

- [Why Migrate?](#why-migrate)
- [Prerequisites](#prerequisites)
- [Pre-Migration Checklist](#pre-migration-checklist)
- [Migration Overview](#migration-overview)
- [Step-by-Step Migration Procedure](#step-by-step-migration-procedure)
- [Configuration Conversion](#configuration-conversion)
- [Rollback Procedure](#rollback-procedure)
- [Post-Migration Enhancements](#post-migration-enhancements)
- [Common Issues and Troubleshooting](#common-issues-and-troubleshooting)
- [FAQ](#faq)

## Why Migrate?

Consider migrating from the Operator to Helm if you need:

- **NetworkPolicy**: Network isolation and security policies (operator doesn't provide)
- **Ingress configuration**: External access with path-based routing (operator doesn't create)
- **GitOps with Helm**: Existing ArgoCD/Flux Helm workflows
- **Fine-grained control**: Explicit configuration over every option
- **No operator dependency**: Simpler cluster setup, fewer moving parts
- **Helm ecosystem**: Integration with Helm-based tools and workflows

**Keep using the Operator if you value:**

- Automated update management with channels
- Simplified CRD-based configuration
- Automatic reconciliation and self-healing
- Built-in status reporting

See [OPERATOR_COMPARISON.md](./OPERATOR_COMPARISON.md) for a detailed comparison.

## Prerequisites

### Required

1. **Kubernetes Cluster**: Version 1.19+ with admin access
2. **kubectl**: Configured to access your cluster
3. **Helm**: Version 3.12+ installed
4. **Current Operator Deployment**: Working SpiceDB via operator
5. **Database Backup**: Recent backup of your SpiceDB datastore

### Recommended

1. **Staging Environment**: Test migration in non-production first
2. **Maintenance Window**: Plan for brief downtime during migration
3. **Monitoring**: Have monitoring in place to verify migration success

### Understanding Feature Loss

When migrating to Helm, you will **lose** these operator-exclusive features:

| Operator Feature | Helm Equivalent | Impact |
|------------------|-----------------|--------|
| Automatic updates via channels | Manual `helm upgrade` | Must manually update |
| CRD status reporting | kubectl commands | Less structured status |
| Automatic rollback on failure | Manual helm rollback | More manual intervention |
| Dynamic reconciliation | Helm upgrade to reconcile | Manual drift correction |

You will **gain** these Helm-exclusive features:

| Helm Feature | Benefit |
|--------------|---------|
| NetworkPolicy | Network isolation and security |
| Ingress | External access configuration |
| ServiceMonitor | Automated Prometheus scraping |
| Helm unit tests | CI/CD validation |
| values-examples | Reference configurations |

## Pre-Migration Checklist

### 1. Document Current Operator Configuration

Export your SpiceDBCluster configuration:

```bash
# Export SpiceDBCluster YAML
kubectl get spicedbcluster spicedb -o yaml > spicedbcluster-backup.yaml

# Save for conversion to Helm values
cat spicedbcluster-backup.yaml

# Document operator version
kubectl get deployment -n spicedb-operator-system spicedb-operator-controller-manager -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### 2. Backup Database

Create a backup of your datastore **before** proceeding:

**PostgreSQL:**

```bash
# Extract connection string from secret
export DATASTORE_URI=$(kubectl get spicedbcluster spicedb -o jsonpath='{.spec.datastoreEngine.postgres.connectionString.secretKeyRef.name}' | xargs -I {} kubectl get secret {} -o jsonpath='{.data.datastore-uri}' | base64 -d)

# Create backup
kubectl run -it --rm pg-backup --image=postgres:15 --restart=Never -- \
  pg_dump "$DATASTORE_URI" -F custom -f /tmp/spicedb-backup.dump

# Or backup from database pod
kubectl exec -n database postgresql-0 -- \
  pg_dump -U spicedb spicedb -F custom -f /tmp/spicedb-backup.dump

# Copy backup locally
kubectl cp database/postgresql-0:/tmp/spicedb-backup.dump ./spicedb-backup.dump
```

**CockroachDB:**

```bash
# Create backup
kubectl exec -n database cockroachdb-0 -- \
  cockroach sql --insecure -e \
  "BACKUP DATABASE spicedb TO 'nodelocal://1/spicedb-backup';"
```

### 3. Document Current State

Record information about the operator deployment:

```bash
# Get current pods
kubectl get pods -l app.kubernetes.io/name=spicedb -o wide > pods-backup.txt

# Get current services
kubectl get svc -l app.kubernetes.io/name=spicedb -o yaml > operator-services-backup.yaml

# Get current secrets
kubectl get spicedbcluster spicedb -o jsonpath='{.spec.secretName}' | \
  xargs -I {} kubectl get secret {} -o yaml > operator-secrets-backup.yaml

# Get resource usage
kubectl top pods -l app.kubernetes.io/name=spicedb > resource-usage.txt

# Get SpiceDBCluster status
kubectl get spicedbcluster spicedb -o jsonpath='{.status}' | jq > spicedbcluster-status.json
```

### 4. Extract Configuration Values

Extract key configuration values for Helm conversion:

```bash
# Get current replica count
export REPLICAS=$(kubectl get spicedbcluster spicedb -o jsonpath='{.spec.replicas}')

# Get current version
export VERSION=$(kubectl get spicedbcluster spicedb -o jsonpath='{.spec.version}')

# Get secret name
export SECRET_NAME=$(kubectl get spicedbcluster spicedb -o jsonpath='{.spec.secretName}')

# Get datastore engine
export DATASTORE_ENGINE=$(kubectl get spicedbcluster spicedb -o jsonpath='{.spec.datastoreEngine}' | jq -r 'keys[0]')

# Get TLS configuration
export TLS_SECRET=$(kubectl get spicedbcluster spicedb -o jsonpath='{.spec.tlsSecretName}')

# Display extracted values
echo "Replicas: $REPLICAS"
echo "Version: $VERSION"
echo "Secret: $SECRET_NAME"
echo "Datastore: $DATASTORE_ENGINE"
echo "TLS Secret: $TLS_SECRET"
```

### 5. Test in Staging

**CRITICAL**: Never perform this migration in production without testing in staging first.

1. Deploy identical operator configuration in staging
2. Follow this guide completely in staging
3. Validate application functionality
4. Measure actual downtime
5. Document any issues encountered

## Migration Overview

The migration process follows these high-level steps:

1. **Prepare Helm Configuration**: Convert SpiceDBCluster spec to values.yaml
2. **Create Required Secrets**: Ensure secrets are in Helm-compatible format
3. **Scale Operator to 0**: Set SpiceDBCluster replicas to 0
4. **Install Helm Chart**: Deploy with Helm using converted configuration
5. **Verify Helm Deployment**: Ensure Helm deployment is healthy
6. **Delete SpiceDBCluster**: Remove operator-managed resources
7. **Create Additional Resources**: Add NetworkPolicy, Ingress, ServiceMonitor
8. **Uninstall Operator** (optional): Remove operator from cluster

**Estimated Downtime**: 2-5 minutes (time between operator scale-down and Helm ready)

**Data Loss Risk**: None (both use same database, no schema changes)

## Step-by-Step Migration Procedure

### Step 1: Create Helm values.yaml

Convert your SpiceDBCluster configuration to Helm values. Use the [Configuration Conversion](#configuration-conversion) section as reference.

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

See [Configuration Conversion](#configuration-conversion) for complete mapping.

### Step 2: Create Required Secrets

Ensure secrets are in Helm-compatible format:

#### Option A: Reuse Operator Secrets (Recommended)

The operator secrets should work with Helm if they have the correct keys:

```bash
# Check operator secret format
kubectl get secret spicedb-operator-config -o jsonpath='{.data}' | jq 'keys'

# Expected keys: ["datastore-uri", "preshared-key"]
# Helm expects: ["datastore-uri", "preshared-key"]
# ✅ Compatible - can reuse directly

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

## Post-Migration Enhancements

Now that you're using Helm, you can add features that the operator didn't provide:

### 1. Add NetworkPolicy for Security

Create `spicedb-networkpolicy.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: spicedb
  namespace: default
  labels:
    app.kubernetes.io/name: spicedb
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
      port: 50051  # gRPC
    - protocol: TCP
      port: 8443   # HTTP

  # Allow from Prometheus
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
    ports:
    - protocol: TCP
      port: 9090  # Metrics

  # Allow inter-pod dispatch communication
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: spicedb
    ports:
    - protocol: TCP
      port: 50053  # Dispatch

  egress:
  # Allow to PostgreSQL
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: database
    ports:
    - protocol: TCP
      port: 5432  # PostgreSQL (or 26257 for CockroachDB)

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

Apply:

```bash
kubectl apply -f spicedb-networkpolicy.yaml

# Verify NetworkPolicy
kubectl get networkpolicy spicedb
kubectl describe networkpolicy spicedb
```

Or add to values.yaml:

```yaml
networkPolicy:
  enabled: true
  ingressControllerNamespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: ingress-nginx
  prometheusNamespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: monitoring
  databaseEgress:
    ports:
    - protocol: TCP
      port: 5432
    to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: database
```

Then upgrade:

```bash
helm upgrade spicedb charts/spicedb -f values.yaml
```

### 2. Configure Ingress for External Access

Create `spicedb-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: spicedb
  namespace: default
  annotations:
    # Automatic TLS with cert-manager
    cert-manager.io/cluster-issuer: letsencrypt-prod

    # NGINX-specific configuration for gRPC
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/grpc-backend: "true"
spec:
  ingressClassName: nginx

  rules:
  # gRPC API endpoint
  - host: api.spicedb.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: spicedb
            port:
              number: 50051

  # Metrics endpoint (separate subdomain)
  - host: metrics.spicedb.example.com
    http:
      paths:
      - path: /metrics
        pathType: Exact
        backend:
          service:
            name: spicedb
            port:
              number: 9090

  tls:
  - secretName: spicedb-api-tls
    hosts:
    - api.spicedb.example.com
  - secretName: spicedb-metrics-tls
    hosts:
    - metrics.spicedb.example.com
```

Apply:

```bash
kubectl apply -f spicedb-ingress.yaml

# Verify Ingress
kubectl get ingress spicedb
kubectl describe ingress spicedb

# Test external access
grpcurl -d '{"service":"authzed.api.v1.SchemaService"}' \
  api.spicedb.example.com:443 grpc.health.v1.Health/Check
```

Or add to values.yaml:

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
  hosts:
  - host: api.spicedb.example.com
    paths:
    - path: /
      pathType: Prefix
      servicePort: grpc
  tls:
  - secretName: spicedb-api-tls
    hosts:
    - api.spicedb.example.com
```

Then upgrade:

```bash
helm upgrade spicedb charts/spicedb -f values.yaml
```

### 3. Add ServiceMonitor for Prometheus

Create `spicedb-servicemonitor.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: spicedb
  namespace: default
  labels:
    app.kubernetes.io/name: spicedb
    prometheus: kube-prometheus  # Match your Prometheus selector
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: spicedb

  endpoints:
  - port: metrics
    interval: 30s
    scrapeTimeout: 10s
    path: /metrics
    scheme: http
```

Apply:

```bash
kubectl apply -f spicedb-servicemonitor.yaml

# Verify ServiceMonitor
kubectl get servicemonitor spicedb

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="spicedb")'
```

Or add to values.yaml:

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
    additionalLabels:
      prometheus: kube-prometheus
```

Then upgrade:

```bash
helm upgrade spicedb charts/spicedb -f values.yaml
```

### 4. Enable HorizontalPodAutoscaler

Add to values.yaml:

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80
```

Upgrade:

```bash
helm upgrade spicedb charts/spicedb -f values.yaml

# Verify HPA
kubectl get hpa spicedb
kubectl describe hpa spicedb

# Watch HPA autoscaling
kubectl get hpa spicedb -w
```

## Configuration Conversion

Reference for converting SpiceDBCluster spec to Helm values.yaml:

### Basic Configuration

| SpiceDBCluster spec | Helm values.yaml | Notes |
|---------------------|------------------|-------|
| `spec.replicas: 3` | `replicaCount: 3` | Direct mapping |
| `spec.version: "v1.35.0"` | `image.tag: "v1.35.0"` | Helm also needs image.repository |
| `spec.secretName: spicedb-config` | `config.existingSecret: spicedb-config` | Reuse same secret |
| `spec.channel: stable` | N/A | Operator-only feature, no Helm equivalent |

### Datastore Configuration

**PostgreSQL:**

Operator:

```yaml
spec:
  datastoreEngine:
    postgres:
      connectionString:
        secretKeyRef:
          name: postgres-uri
          key: datastore-uri
```

Helm:

```yaml
config:
  datastoreEngine: postgres
  existingSecret: postgres-uri  # Must have 'datastore-uri' key
```

**Memory:**

Operator:

```yaml
spec:
  datastoreEngine:
    memory: {}
```

Helm:

```yaml
config:
  datastoreEngine: memory
```

### TLS Configuration

Operator:

```yaml
spec:
  tlsSecretName: spicedb-tls  # Single secret for gRPC + HTTP
  dispatchCluster:
    enabled: true
    tlsSecretName: spicedb-dispatch-tls
```

Helm:

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

### Resource Configuration

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

### Features to Add in Helm (Not in Operator)

| Feature | Helm Configuration |
|---------|-------------------|
| NetworkPolicy | `networkPolicy.enabled: true` + configuration |
| Ingress | `ingress.enabled: true` + hosts/tls configuration |
| ServiceMonitor | `monitoring.serviceMonitor.enabled: true` |
| Migration cleanup | `migrations.cleanup.enabled: true` |
| PDB control | `podDisruptionBudget.maxUnavailable: 1` |

### Operator Features Without Helm Equivalent

| Operator Feature | Workaround in Helm |
|------------------|-------------------|
| Update channels | Manual version updates via `image.tag` |
| CRD status | Use `kubectl get pods`, `helm status` |
| Automatic rollback | Manual `helm rollback` |
| Dynamic reconciliation | Manual `helm upgrade` to apply changes |

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
echo "⚠️  IMPORTANT: Review and add if needed:"
echo "  - NetworkPolicy configuration"
echo "  - Ingress configuration"
echo "  - ServiceMonitor configuration"
echo "  - Resource limits (based on actual usage)"
echo ""
echo "Run: helm install spicedb charts/spicedb -f $OUTPUT --dry-run"

# Cleanup
rm /tmp/cluster.json
```

Usage:

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

## Rollback Procedure

If migration fails or you need to rollback to the operator:

### Quick Rollback (During Migration)

If still in maintenance window and Helm deployment fails:

```bash
# Uninstall Helm release
helm uninstall spicedb

# Wait for Helm resources to be deleted
kubectl wait --for=delete pod -l app.kubernetes.io/name=spicedb --timeout=60s

# Restore SpiceDBCluster replicas
kubectl patch spicedbcluster spicedb --type=merge -p '{"spec":{"replicas":3}}'

# Wait for operator to recreate pods
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=spicedb --timeout=120s

# Verify operator deployment
kubectl get spicedbcluster spicedb
kubectl get pods -l app.kubernetes.io/name=spicedb
```

### Full Rollback (After Deleting SpiceDBCluster)

If you've already deleted the SpiceDBCluster:

```bash
# Uninstall Helm if installed
helm uninstall spicedb

# Recreate SpiceDBCluster from backup
kubectl apply -f spicedbcluster-backup.yaml

# Wait for operator to recreate resources
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=spicedb --timeout=120s

# Verify operator deployment
kubectl get spicedbcluster spicedb
```

### Reinstall Operator (If Uninstalled)

If you uninstalled the operator:

```bash
# Reinstall operator
kubectl apply -f https://github.com/authzed/spicedb-operator/releases/latest/download/bundle.yaml

# Wait for operator to be ready
kubectl wait --for=condition=ready pod -n spicedb-operator-system -l control-plane=controller-manager --timeout=60s

# Recreate SpiceDBCluster
kubectl apply -f spicedbcluster-backup.yaml

# Verify
kubectl get spicedbcluster spicedb
```

## Common Issues and Troubleshooting

### Issue: Helm pods crash with "secret not found"

**Symptoms:**

```bash
kubectl get pods -l app.kubernetes.io/name=spicedb
# NAME                       READY   STATUS             RESTARTS   AGE
# spicedb-xxxxx-yyyyy        0/1     CrashLoopBackOff   3          2m
```

**Diagnosis:**

```bash
kubectl logs spicedb-xxxxx-yyyyy

# Error: failed to load secret "spicedb-operator-config": secret not found
```

**Common Causes:**
Secret name in values.yaml doesn't match actual secret

**Resolution:**

```bash
# Check secret exists
kubectl get secret spicedb-operator-config

# If missing, check what secrets exist
kubectl get secrets

# Update values.yaml with correct secret name
# config:
#   existingSecret: <actual-secret-name>

# Upgrade Helm release
helm upgrade spicedb charts/spicedb -f values.yaml
```

### Issue: Helm and operator both trying to manage resources

**Symptoms:**
Pods being created/deleted repeatedly, services changing

**Diagnosis:**

```bash
kubectl get pods -l app.kubernetes.io/name=spicedb -o yaml | grep ownerReferences

# If both Helm and operator owner references exist, conflict
```

**Common Causes:**
SpiceDBCluster wasn't scaled to 0 before Helm install

**Resolution:**

```bash
# Scale SpiceDBCluster to 0
kubectl patch spicedbcluster spicedb --type=merge -p '{"spec":{"replicas":0}}'

# Wait for operator pods to be deleted
kubectl wait --for=delete pod -l app.kubernetes.io/name=spicedb --timeout=60s

# Delete and reinstall Helm release
helm uninstall spicedb
helm install spicedb charts/spicedb -f values.yaml
```

### Issue: NetworkPolicy blocks all traffic

**Symptoms:**
Clients can't connect after creating NetworkPolicy

**Diagnosis:**

```bash
# Check NetworkPolicy exists
kubectl get networkpolicy spicedb -o yaml

# Test connectivity
kubectl run -it --rm test --image=curlimages/curl -- \
  curl -v http://spicedb:50051
```

**Common Causes:**
NetworkPolicy is too restrictive or has wrong selectors

**Resolution:**

```bash
# Delete NetworkPolicy temporarily
kubectl delete networkpolicy spicedb

# Test if connectivity restored
# If yes, NetworkPolicy was the issue

# Recreate with correct configuration
# Ensure podSelector matches Helm pods
kubectl get pods -l app.kubernetes.io/name=spicedb --show-labels
```

### Issue: Ingress returns 404 or 503

**Symptoms:**
External requests fail through Ingress

**Diagnosis:**

```bash
# Check Ingress
kubectl get ingress spicedb -o yaml

# Check Ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100 | grep spicedb

# Check service endpoints
kubectl get endpoints spicedb
```

**Common Causes:**

1. Service name in Ingress doesn't match Helm service
2. Port numbers incorrect
3. Ingress annotations wrong for gRPC

**Resolution:**

```bash
# Verify service name
kubectl get svc -l app.kubernetes.io/name=spicedb

# Update Ingress backend to match
kubectl patch ingress spicedb --type=json -p='[
  {"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "spicedb"}
]'

# Ensure gRPC annotations for NGINX
kubectl annotate ingress spicedb \
  nginx.ingress.kubernetes.io/backend-protocol=GRPC \
  --overwrite
```

### Issue: Metrics not in Prometheus after migration

**Symptoms:**
Prometheus targets show no spicedb metrics

**Diagnosis:**

```bash
# Check ServiceMonitor
kubectl get servicemonitor spicedb

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="spicedb")'

# Manually test metrics endpoint
kubectl port-forward svc/spicedb 9090:9090 &
curl http://localhost:9090/metrics
```

**Common Causes:**
ServiceMonitor not created or has wrong labels

**Resolution:**

```bash
# Add ServiceMonitor to values.yaml
# monitoring:
#   serviceMonitor:
#     enabled: true
#     additionalLabels:
#       prometheus: kube-prometheus

# Upgrade Helm release
helm upgrade spicedb charts/spicedb -f values.yaml

# Verify ServiceMonitor created
kubectl get servicemonitor spicedb
```

## FAQ

### Can I migrate without downtime?

**No** - Brief downtime (2-5 minutes) is unavoidable. Both operator and Helm manage StatefulSet/Deployment, and you cannot run both simultaneously.

### Will I lose data?

**No** - The migration doesn't touch your database. Backup before migrating as a safety precaution.

### Can I keep using operator channels for updates?

**No** - Helm doesn't support operator update channels. You'll need to manually update via `helm upgrade` with new `image.tag`.

Consider using Renovate or Dependabot to automate Helm updates.

### What happens to my secrets?

**They are reused** - Helm references the same secrets. Your existing secrets continue to work.

### Do I need to recreate the database?

**No** - Helm connects to the same database as the operator. No database changes are needed.

### Can I migrate back to the operator later?

**Yes** - See [MIGRATION_HELM_TO_OPERATOR.md](./MIGRATION_HELM_TO_OPERATOR.md) for reverse migration.

### Will Helm manage the same resources as the operator?

**Similar, but not identical**:

- Helm creates: Deployment/StatefulSet, Service, ConfigMap, Secret, Job (migrations)
- Operator creates: StatefulSet, Service
- Helm adds: NetworkPolicy, Ingress, ServiceMonitor (if configured)

### How do I update SpiceDB version with Helm?

```bash
# Update values.yaml
# image:
#   tag: "v1.36.0"

# Upgrade
helm upgrade spicedb charts/spicedb -f values.yaml

# Or inline
helm upgrade spicedb charts/spicedb --set image.tag=v1.36.0
```

### Can I use both Helm and operator in the same cluster?

**Yes**, but not for the same SpiceDB instance. You can have:

- Operator-managed SpiceDB in `production` namespace
- Helm-managed SpiceDB in `staging` namespace

### What if I have customized the operator deployment?

Check [Configuration Conversion](#configuration-conversion) for supported customizations.

If you have unsupported customizations:

- Use Helm hooks for custom logic
- Use initContainers for custom setup
- Patch Helm resources with kubectl

### How do I automate Helm updates?

Use GitOps tools:

- **ArgoCD**: Auto-sync Helm releases
- **Flux**: HelmRelease with automated updates
- **Renovate**: Automated PRs for version updates
- **Dependabot**: Automated dependency updates

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

## Additional Resources

- [Helm Chart Documentation](./README.md)
- [OPERATOR_COMPARISON.md](./OPERATOR_COMPARISON.md) - Feature comparison
- [MIGRATION_HELM_TO_OPERATOR.md](./MIGRATION_HELM_TO_OPERATOR.md) - Reverse migration
- [PRODUCTION_GUIDE.md](./PRODUCTION_GUIDE.md) - Production deployment guide
- [SpiceDB Operator Docs](https://github.com/authzed/spicedb-operator/tree/main/docs)

## Support

- **Helm Chart Issues**: <https://github.com/salekseev/helm-charts/issues>
- **SpiceDB Discord**: <https://authzed.com/discord>
- **Migration Help**: Open issue with [migration] tag

## Changelog

- **2024-11-11**: Initial version
