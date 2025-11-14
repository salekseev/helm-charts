# SpiceDB Helm Chart - 5-Minute Quickstart

This guide will help you deploy SpiceDB to Kubernetes in 5 minutes using the memory datastore (suitable for development and testing).

## Prerequisites

Before you begin, ensure you have:

- Kubernetes cluster (1.19+) - local (kind, minikube, k3d) or cloud
- `kubectl` configured to access your cluster
- `helm` CLI (3.12+) installed
- *(Optional)* `zed` CLI for interacting with SpiceDB - [Installation guide](https://github.com/authzed/zed#installation)

### Quick Environment Check

```bash
# Verify kubectl can access your cluster
kubectl cluster-info

# Verify Helm is installed
helm version

# Verify zed CLI is installed (optional)
zed version
```

## Step 1: Install SpiceDB

### Option A: Quick Install with Development Preset (Recommended for Testing)

The easiest way to get started is using the development preset:

```bash
# Install with development preset (memory datastore, debug logging)
helm install spicedb charts/spicedb -f values-presets/development.yaml
```

**What this does:**

- Single replica with in-memory datastore (no database needed)
- Debug logging enabled
- Minimal resource requirements
- Perfect for local development and testing

**Warning:** Memory datastore is not persistent. Data is lost when pods restart.

### Option B: Standard Install with Default Values (Basic HA)

Install the chart with default settings (2 replicas, dispatch enabled):

```bash
# Install from local charts directory
helm install spicedb charts/spicedb

# Or once published, install from Helm repository:
# helm repo add authzed https://authzed.github.io/spicedb-helm
# helm repo update
# helm install spicedb authzed/spicedb
```

**What this does:**

- 2 replicas for basic HA (handles single pod failure)
- Dispatch cluster enabled for distributed permission checking
- Memory datastore by default (suitable for testing)
- Matches SpiceDB operator defaults

**Note:** For production, use Option C with persistent datastore.

**Expected output:**

```text
NAME: spicedb
LAST DEPLOYED: ...
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
SpiceDB has been installed!

...
```

### Option C: Production-Ready Install (PostgreSQL)

For a more production-like setup with persistent storage:

```bash
# Create secrets first
kubectl create secret generic spicedb-secrets \
  --from-literal=datastore-uri="postgresql://user:pass@postgres-host:5432/spicedb?sslmode=require" \
  --from-literal=preshared-key="$(openssl rand -base64 32)"

# Install with production preset
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  --set config.existingSecret=spicedb-secrets
```

**Note:** Requires a PostgreSQL instance. See [PRODUCTION_GUIDE.md](./PRODUCTION_GUIDE.md) for database setup.

---

**For this quickstart, we'll continue with Option A (development preset).**

## Step 2: Verify Deployment

Wait for SpiceDB pod to be ready:

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=spicedb

# Wait for ready state (should take 10-30 seconds)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=spicedb --timeout=60s
```

**Expected output:**

```text
NAME                       READY   STATUS    RESTARTS   AGE
spicedb-6d9f8b4c7-xyz12    1/1     Running   0          45s
```

## Step 3: Access SpiceDB Endpoints

### Get Authentication Token

SpiceDB uses a preshared key for authentication. Retrieve it from the created secret:

```bash
export SPICEDB_TOKEN=$(kubectl get secret spicedb -o jsonpath='{.data.preshared-key}' | base64 -d)
echo "Token: $SPICEDB_TOKEN"
```

### Port Forward to Access Locally

SpiceDB exposes multiple endpoints. Forward them to your local machine:

```bash
# gRPC API (primary interface)
kubectl port-forward svc/spicedb 50051:50051 &

# HTTP Dashboard and metrics (optional)
kubectl port-forward svc/spicedb 8443:8443 9090:9090 &

# Check port forwarding is working
ps aux | grep "port-forward"
```

## Step 4: Test SpiceDB with zed CLI

The `zed` CLI is the easiest way to interact with SpiceDB.

### Configure zed Context

```bash
# Create a zed context pointing to your local SpiceDB
zed context set local localhost:50051 "$SPICEDB_TOKEN" --insecure
```

### Load a Sample Schema

Create a simple permissions schema:

```bash
# Create schema file
cat > /tmp/schema.zed <<'EOF'
definition user {}

definition document {
    relation owner: user
    relation editor: user
    relation viewer: user

    permission view = viewer + editor + owner
    permission edit = editor + owner
    permission delete = owner
}
EOF

# Write schema to SpiceDB
zed schema write /tmp/schema.zed
```

### Create Relationships

Define some relationships:

```bash
# Alice owns document:readme
zed relationship create document:readme owner user:alice

# Bob can edit document:readme
zed relationship create document:readme editor user:bob

# Charlie can view document:readme
zed relationship create document:readme viewer user:charlie
```

### Check Permissions

Query permissions to verify everything works:

```bash
# Can Alice delete document:readme? (YES - she's the owner)
zed permission check document:readme delete user:alice

# Can Bob delete document:readme? (NO - he's only an editor)
zed permission check document:readme delete user:bob

# Can Charlie edit document:readme? (NO - he's only a viewer)
zed permission check document:readme edit user:charlie

# Can Charlie view document:readme? (YES - viewers can view)
zed permission check document:readme view user:charlie
```

**Expected outputs:**

```text
true   # Alice can delete
false  # Bob cannot delete
false  # Charlie cannot edit
true   # Charlie can view
```

## Step 5: Access HTTP Dashboard (Optional)

If you forwarded port 8443, you can access the HTTP dashboard:

```bash
# Health check
curl http://localhost:8443/healthz

# Metrics endpoint
curl http://localhost:9090/metrics
```

Open in browser:

- Dashboard: <http://localhost:8443>
- Metrics: <http://localhost:9090/metrics>

## Step 6: Cleanup

When you're done testing, clean up resources:

```bash
# Stop port forwarding
pkill -f "kubectl port-forward svc/spicedb"

# Uninstall SpiceDB
helm uninstall spicedb

# Verify resources are cleaned up
kubectl get pods -l app.kubernetes.io/name=spicedb
kubectl get secrets -l app.kubernetes.io/name=spicedb
```

## What's Next?

Now that you have SpiceDB running, explore these next steps:

### Production Deployment

Memory datastore is not suitable for production. Switch to PostgreSQL or CockroachDB:

**PostgreSQL:**

```bash
helm install spicedb charts/spicedb \
  --set config.datastoreEngine=postgres \
  --set config.datastore.hostname=postgres.database.svc.cluster.local \
  --set config.datastore.username=spicedb \
  --set config.datastore.password=changeme \
  --set config.datastore.database=spicedb \
  --set config.datastore.sslMode=require \
  --set replicaCount=3
```

See [examples/production-postgres.yaml](./examples/production-postgres.yaml) for complete configuration.

### High Availability Setup

The production-postgres preset now includes HA features by default:

```bash
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  --set config.existingSecret=spicedb-config
```

This includes HPA (2-5 replicas), pod anti-affinity, and topology spread constraints.

### Enable Monitoring

Integrate with Prometheus for metrics:

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    additionalLabels:
      prometheus: kube-prometheus
```

### Configure TLS

Secure all endpoints with TLS using cert-manager:

See [examples/cert-manager-integration.yaml](./examples/cert-manager-integration.yaml)

### Learn More

- **SpiceDB Documentation**: <https://authzed.com/docs>
- **Chart README**: [README.md](./README.md) - comprehensive configuration reference
- **Examples Directory**: [examples/](./examples/) - production-ready configurations
- **zed CLI Guide**: <https://github.com/authzed/zed>

## Troubleshooting

### Pod Not Starting

Check pod logs:

```bash
kubectl logs -l app.kubernetes.io/name=spicedb
kubectl describe pod -l app.kubernetes.io/name=spicedb
```

### Port Forward Connection Refused

Ensure pod is in Running state:

```bash
kubectl get pods -l app.kubernetes.io/name=spicedb
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=spicedb
```

### Permission Check Returns Error

Verify token is correct:

```bash
echo $SPICEDB_TOKEN
# Should output a non-empty string

# Reconfigure zed if needed
zed context set local localhost:50051 "$SPICEDB_TOKEN" --insecure
```

### Schema Write Fails

Check SpiceDB logs for errors:

```bash
kubectl logs -l app.kubernetes.io/name=spicedb --tail=50
```

## Advanced Testing Scenarios

### Test with grpcurl

If you prefer grpcurl over zed:

```bash
# List available services
grpcurl -plaintext \
  -H "authorization: Bearer $SPICEDB_TOKEN" \
  localhost:50051 list

# Check permissions
grpcurl -plaintext \
  -H "authorization: Bearer $SPICEDB_TOKEN" \
  -d '{
    "resource": {"objectType": "document", "objectId": "readme"},
    "permission": "view",
    "subject": {"object": {"objectType": "user", "objectId": "alice"}}
  }' \
  localhost:50051 authzed.api.v1.PermissionsService/CheckPermission
```

### Load Testing

Generate load to test performance:

```bash
# Install hey load testing tool
go install github.com/rakyll/hey@latest

# Generate gRPC load (requires hey to support gRPC)
# Or use zed in a loop
for i in {1..1000}; do
  zed permission check document:readme view user:alice &
done
wait
```

### Test with Multiple Replicas

Scale up to test dispatch cluster mode:

```bash
# Scale to 3 replicas
kubectl scale deployment spicedb --replicas=3

# Verify all pods are ready
kubectl get pods -l app.kubernetes.io/name=spicedb

# Test load distribution
kubectl logs -l app.kubernetes.io/name=spicedb --tail=10 -f
```

## Additional Resources

- **Examples**: Explore [examples/](./examples/) directory for production configurations
- **Configuration Reference**: See [README.md](./README.md) for all available options
- **SpiceDB Concepts**: <https://authzed.com/docs/concepts>
- **Zanzibar Paper**: <https://research.google/pubs/pub48190/> (the inspiration for SpiceDB)
