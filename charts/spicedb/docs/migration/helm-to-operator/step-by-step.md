# Step-by-Step Migration Procedure

This document provides the complete migration procedure from Helm to SpiceDB
Operator.

## Navigation

- [Overview](./index.md)
- [Prerequisites](./prerequisites.md)
- **Step-by-Step Migration** (this page)
- [Configuration Conversion](./configuration-conversion.md)
- [Post-Migration Validation](./post-migration.md)
- [Troubleshooting](../../guides/troubleshooting/index.md)

## Before You Begin

Ensure you have completed all steps in [Prerequisites](./prerequisites.md).

**Estimated Time**: 10-15 minutes
**Estimated Downtime**: 2-5 minutes

## Step 1: Install SpiceDB Operator

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

**Note**: The operator installs into the `spicedb-operator-system` namespace by
default.

## Step 2: Create Secrets for Operator

The operator requires secrets in specific formats. Convert your Helm secrets:

### Option A: Reuse Existing Secrets (Recommended)

If your existing secrets are in the correct format, you can reference them
directly:

```bash
# Check your current secret format
kubectl get secret spicedb -o yaml

# Operator expects these keys:
# - preshared-key: SpiceDB preshared key
# - datastore-uri: Database connection string
```

If your secret has these keys, you can skip to Step 3 and reference the existing
secret name.

### Option B: Create New Secrets

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

## Step 3: Create SpiceDBCluster Manifest

Create a `spicedb-cluster.yaml` file with your configuration.

### Basic Example (PostgreSQL)

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

### Advanced Example (with TLS and Dispatch)

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

See [Configuration Conversion](./configuration-conversion.md) for complete
mapping reference.

## Step 4: Apply SpiceDBCluster (Pre-validation)

Before applying, validate the manifest:

```bash
# Validate YAML syntax
kubectl apply -f spicedb-cluster.yaml --dry-run=client

# Check if operator can process it
kubectl apply -f spicedb-cluster.yaml --dry-run=server

# Expected output:
# spicedbcluster.authzed.com/spicedb created (server dry run)
```

## Step 5: Scale Helm Deployment to 0

This is the **start of the downtime window**:

```bash
# Scale Helm deployment to 0 replicas
kubectl scale deployment spicedb --replicas=0

# Wait for pods to terminate
kubectl wait --for=delete pod -l app.kubernetes.io/name=spicedb --timeout=60s

# Verify no pods are running
kubectl get pods -l app.kubernetes.io/name=spicedb

# Expected output: No resources found (or all terminating)
```

## Step 6: Apply SpiceDBCluster

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

**Downtime ends** when the first operator-managed pod is ready and serving
traffic.

## Step 7: Verify Operator Deployment

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

# Check logs for errors
kubectl logs -l app.kubernetes.io/name=spicedb --tail=50
```

## Step 8: Test Connectivity

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

# Expected output:
# {"status":"ok"}
```

## Step 9: Delete Helm Release

Once operator deployment is verified, remove the Helm release:

```bash
# Delete Helm release but keep history for rollback
helm uninstall spicedb --keep-history

# Verify Helm release is deleted
helm list --all

# Expected output: spicedb should show as 'uninstalled'

# Clean up any orphaned resources from Helm (if any)
kubectl get all -l app.kubernetes.io/name=spicedb
```

**WARNING**: Do **not** delete the following:

- Database (PostgreSQL/CockroachDB)
- Secrets (unless you created new ones)
- TLS certificates
- PersistentVolumeClaims (if any)

## Step 10: Recreate Helm-Only Resources

The operator doesn't create certain resources that Helm managed. Recreate them
manually:

### NetworkPolicy (if you had networkPolicy.enabled: true)

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

### Ingress (if you had ingress.enabled: true)

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

### ServiceMonitor (if you had monitoring.serviceMonitor.enabled: true)

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

## Step 11: Post-Migration Verification

Complete the verification steps in
[Post-Migration Validation](./post-migration.md).

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

## Next Steps

After completing migration, proceed to
[Post-Migration Validation](./post-migration.md) for complete verification.
