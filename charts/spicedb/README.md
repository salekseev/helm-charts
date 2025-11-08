# SpiceDB Helm Chart

[![Helm Chart CI](https://github.com/salekseev/helm-charts/actions/workflows/ci.yaml/badge.svg)](https://github.com/salekseev/helm-charts/actions/workflows/ci.yaml)

A Helm chart for deploying [SpiceDB](https://github.com/authzed/spicedb) - an open source, Zanzibar-inspired permissions database.

## Status

This chart is currently under active development. See the project roadmap in `.taskmaster/tasks/` for planned features.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.14.0+

## Installation

```bash
# Add the helm repository (once published)
# helm repo add spicedb https://example.com/charts

# Install the chart
helm install my-spicedb charts/spicedb
```

## Quick Start (Memory Mode)

For development and testing, you can deploy SpiceDB with in-memory datastore:

```bash
helm install spicedb charts/spicedb \
  --set config.datastoreEngine=memory
```

## Configuration

See [values.yaml](values.yaml) for all configuration options.

### Key Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of SpiceDB replicas | `1` |
| `image.repository` | SpiceDB image repository | `authzed/spicedb` |
| `image.tag` | SpiceDB image tag | `""` (uses appVersion) |
| `config.datastoreEngine` | Datastore engine: memory, postgres, cockroachdb | `memory` |
| `config.logLevel` | Log level: debug, info, warn, error | `info` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.headless` | Enable headless service for StatefulSet support | `false` |

## Database Migrations

SpiceDB requires database migrations to initialize and update schema. This chart includes automated migration support via Helm hooks.

### Overview

Database migrations are schema changes that SpiceDB applies to its datastore. Migrations:

- Run automatically before SpiceDB starts (pre-install, pre-upgrade hooks)
- Ensure the database schema matches the SpiceDB version being deployed
- Support zero-downtime upgrades through phased migrations
- Can be targeted to specific versions for controlled rollouts

**Default Behavior:** Migrations run automatically on every `helm install` and `helm upgrade`. The migration job must complete successfully before SpiceDB pods start.

### Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `migrations.enabled` | Enable automatic database migrations | `true` |
| `migrations.logLevel` | Log level for migrations (debug, info, warn, error) | `info` |
| `migrations.targetMigration` | Target specific migration version (e.g., "add-caveats") | `""` (latest) |
| `migrations.targetPhase` | Target specific phase (write, read, complete) | `""` (all phases) |
| `migrations.resources` | Resource limits/requests for migration job | `{}` |
| `migrations.cleanup.enabled` | Auto-cleanup completed migration jobs | `false` |

### Common Operations

#### Standard Installation

Migrations run automatically with default settings:

```bash
helm install spicedb charts/spicedb \
  --set config.datastoreEngine=postgres \
  --set config.datastore.hostname=postgres.default.svc.cluster.local \
  --set config.datastore.password=mypassword
```

#### Viewing Migration Logs

Check migration job logs to see progress or diagnose issues:

```bash
# View logs from the most recent migration job
kubectl logs -l app.kubernetes.io/component=migration

# Follow logs in real-time
kubectl logs -l app.kubernetes.io/component=migration -f

# View logs with debug output (set logLevel=debug first)
helm upgrade spicedb charts/spicedb --set migrations.logLevel=debug --reuse-values
kubectl logs -l app.kubernetes.io/component=migration -f
```

#### Checking Migration Job Status

Monitor migration job status:

```bash
# List all migration jobs
kubectl get jobs -l app.kubernetes.io/component=migration

# Get detailed job status
kubectl describe job -l app.kubernetes.io/component=migration

# Check if migration completed successfully
kubectl get jobs -l app.kubernetes.io/component=migration \
  --field-selector status.successful=1
```

#### Disabling Automatic Migrations

For manual migration control:

```bash
helm install spicedb charts/spicedb \
  --set migrations.enabled=false \
  --set config.datastoreEngine=postgres \
  --set config.datastore.hostname=postgres.default.svc.cluster.local \
  --set config.datastore.password=mypassword
```

Then run migrations manually using `kubectl exec` or a separate job.

## Headless Service for StatefulSet Deployments

The chart supports creating a headless service (clusterIP: None) for StatefulSet deployments. Headless services provide stable network identities for individual pods, enabling direct pod-to-pod communication required by StatefulSets.

### What is a Headless Service?

A headless service in Kubernetes is a service without a cluster IP address. Instead of load balancing traffic to pods, DNS queries for a headless service return the IP addresses of all associated pods. This allows clients to connect directly to specific pods by hostname.

**Key characteristics:**
- `clusterIP: None` - No virtual IP address for load balancing
- DNS returns individual pod IPs instead of a single service IP
- Each pod gets a stable DNS hostname: `<pod-name>.<service-name>.<namespace>.svc.cluster.local`
- Required for StatefulSet deployments with stable network identities

### When to Use Headless Services

Enable headless services when:

- **StatefulSet Deployments**: Planning to migrate from Deployment to StatefulSet for stable pod identities
- **Direct Pod Communication**: Applications need to communicate with specific pods (e.g., distributed databases, consensus systems)
- **Dispatch Clustering**: SpiceDB's internal dispatch mechanism benefits from stable pod addressing in multi-replica setups
- **Service Discovery**: Custom service discovery mechanisms that need to discover all pod IPs

### Configuration

Enable headless service by setting `service.headless` to `true`:

```bash
helm install spicedb charts/spicedb \
  --set service.headless=true \
  --set replicaCount=3 \
  --set config.datastoreEngine=postgres \
  --set config.datastore.hostname=postgres.default.svc.cluster.local
```

Or via values.yaml:

```yaml
service:
  type: ClusterIP
  headless: true  # Creates headless service
  grpcPort: 50051
  httpPort: 8443
  metricsPort: 9090
  dispatchPort: 50053  # Still exposed for dispatch clustering

replicaCount: 3
```

### Service Behavior

**Standard Service (headless: false - default):**
```bash
# DNS lookup returns single cluster IP
nslookup spicedb.default.svc.cluster.local
# Returns: 10.96.0.10 (virtual IP, load balanced)
```

**Headless Service (headless: true):**
```bash
# DNS lookup returns individual pod IPs
nslookup spicedb.default.svc.cluster.local
# Returns:
#   10.244.0.5 (spicedb-7d8f9c-abc12)
#   10.244.1.6 (spicedb-7d8f9c-def34)
#   10.244.2.7 (spicedb-7d8f9c-ghi56)
```

### Port Configuration

All service ports remain available with headless services, including the dispatch port (50053) required for internal cluster communication:

- **gRPC API**: 50051 - Client permission checks
- **HTTP Dashboard**: 8443 - Web UI and metrics
- **Metrics**: 9090 - Prometheus metrics
- **Dispatch**: 50053 - Inter-pod communication (critical for multi-replica deployments)

### StatefulSet Migration

The headless service configuration prepares the infrastructure for future StatefulSet deployments. While the current chart uses Deployments, enabling headless services allows for easier migration to StatefulSets when needed.

**Current State:** Deployment with optional headless service
**Future Enhancement:** StatefulSet support (planned)

When StatefulSet support is added, pods will have stable identities like:
- `spicedb-0.spicedb.default.svc.cluster.local`
- `spicedb-1.spicedb.default.svc.cluster.local`
- `spicedb-2.spicedb.default.svc.cluster.local`

### Backward Compatibility

The `service.headless` setting is:
- **Default: false** - Maintains existing behavior with standard ClusterIP service
- **Fully backward compatible** - Existing deployments are unaffected
- **Optional** - Only enable when needed for specific use cases

### Examples

#### Standard Multi-Replica Deployment (Default)

```bash
helm install spicedb charts/spicedb \
  --set replicaCount=3 \
  --set config.datastoreEngine=postgres
# Creates ClusterIP service with load balancing
```

#### Multi-Replica with Headless Service

```bash
helm install spicedb charts/spicedb \
  --set service.headless=true \
  --set replicaCount=3 \
  --set config.datastoreEngine=postgres
# Creates headless service with individual pod DNS entries
```

#### Verifying Headless Service Configuration

```bash
# Check service configuration
kubectl get service spicedb -o yaml | grep clusterIP
# With headless: true, should show "clusterIP: None"

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup spicedb.default.svc.cluster.local
# Should return multiple pod IPs for headless service

# Verify all ports are exposed
kubectl get service spicedb -o yaml | grep -A 5 ports:
```

### Troubleshooting

**Issue: Service shows "None" for CLUSTER-IP**

This is expected behavior for headless services:
```bash
kubectl get service spicedb
# NAME      TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)
# spicedb   ClusterIP   None         <none>        50051/TCP,...
```

**Issue: Cannot connect to service IP**

Headless services don't have a cluster IP for load balancing. Connect directly to individual pods or use pod DNS names:
```bash
# Get pod IPs
kubectl get pods -l app.kubernetes.io/name=spicedb -o wide

# Connect to specific pod
kubectl exec -it <pod-name> -- grpcurl -plaintext localhost:50051 list
```

**Issue: Need load balancing with headless service**

Headless services don't provide load balancing. Options:
1. Disable headless mode: `--set service.headless=false`
2. Implement client-side load balancing
3. Use a separate non-headless service for load-balanced access

#### Running Migrations Manually

If you disabled automatic migrations or need to run migrations outside Helm:

```bash
# Create a one-time migration job
kubectl run spicedb-migration-manual \
  --image=authzed/spicedb:v1.29.0 \
  --restart=Never \
  --env="SPICEDB_DATASTORE_ENGINE=postgres" \
  --env="SPICEDB_DATASTORE_CONN_URI=postgresql://user:pass@host/db" \
  -- spicedb migrate head

# View the logs
kubectl logs spicedb-migration-manual -f

# Clean up when done
kubectl delete pod spicedb-migration-manual
```

### Phased Migration Workflow

For zero-downtime migrations, SpiceDB supports three phases:

1. **write** - Schema changes that allow old code to continue working
2. **read** - New code can read new schema, old code deprecated
3. **complete** - Migration fully complete, old code support removed

This allows you to upgrade SpiceDB incrementally without downtime.

#### Step-by-Step Phased Migration

**Step 1: Deploy write phase**

```bash
helm upgrade spicedb charts/spicedb \
  --set migrations.targetPhase=write \
  --set image.tag=v1.30.0 \
  --reuse-values
```

Wait for migration to complete. Verify old SpiceDB pods still work.

**Step 2: Upgrade SpiceDB to new version**

```bash
# Update to new SpiceDB version
helm upgrade spicedb charts/spicedb \
  --set image.tag=v1.30.0 \
  --set migrations.targetPhase=read \
  --reuse-values
```

New pods can now read the updated schema. Wait for all pods to be healthy.

**Step 3: Complete the migration**

```bash
helm upgrade spicedb charts/spicedb \
  --set migrations.targetPhase=complete \
  --reuse-values
```

Migration is now fully complete. Old code support is removed.

**Step 4: Clear targetPhase for future upgrades**

```bash
helm upgrade spicedb charts/spicedb \
  --set migrations.targetPhase="" \
  --reuse-values
```

#### When to Use Phased Migrations

Use phased migrations when:

- Running SpiceDB in production with strict uptime requirements
- Upgrading between major versions with significant schema changes
- Testing complex migrations in staging before production
- You need to roll back quickly if issues arise

For most upgrades, the default (all phases at once) is sufficient.

### Troubleshooting

#### Migration Job Failed

**Symptoms:** Helm upgrade hangs or fails with migration errors.

**Diagnosis:**

```bash
# Check job status
kubectl get jobs -l app.kubernetes.io/component=migration

# View detailed error messages
kubectl logs -l app.kubernetes.io/component=migration

# Describe the job for event history
kubectl describe job -l app.kubernetes.io/component=migration
```

**Common causes:**

- Database connection issues (check credentials, network connectivity)
- Incompatible SpiceDB version (downgrade not supported)
- Database lock conflicts (another migration running)
- Insufficient database permissions

**Resolution:**

```bash
# Fix the underlying issue, then retry with helm upgrade
helm upgrade spicedb charts/spicedb --reuse-values

# Or manually delete the failed job and retry
kubectl delete job -l app.kubernetes.io/component=migration
helm upgrade spicedb charts/spicedb --reuse-values
```

#### Migration Timeout

**Symptoms:** Migration job exceeds activeDeadlineSeconds (default: 600s/10min).

**Diagnosis:**

```bash
kubectl describe job -l app.kubernetes.io/component=migration
# Look for "DeadlineExceeded" in events
```

**Resolution:**

Large databases may need more time. The timeout is hardcoded in the template but you can manually create a job with a longer timeout:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: spicedb-migration-extended
spec:
  activeDeadlineSeconds: 3600  # 1 hour
  backoffLimit: 3
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: migration
        image: authzed/spicedb:v1.29.0
        command: ["spicedb", "migrate", "head"]
        env:
        - name: SPICEDB_DATASTORE_ENGINE
          value: postgres
        - name: SPICEDB_DATASTORE_CONN_URI
          valueFrom:
            secretKeyRef:
              name: spicedb
              key: datastore-uri
```

Apply this job manually, wait for completion, then proceed with Helm upgrade.

#### Migration Job Stuck

**Symptoms:** Migration job shows as running but makes no progress.

**Diagnosis:**

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/component=migration

# View logs
kubectl logs -l app.kubernetes.io/component=migration -f

# Check for database locks (if using PostgreSQL)
# Connect to database and run:
# SELECT * FROM pg_locks WHERE NOT granted;
```

**Resolution:**

```bash
# Delete the stuck job (Helm will recreate it)
kubectl delete job -l app.kubernetes.io/component=migration

# Retry the upgrade
helm upgrade spicedb charts/spicedb --reuse-values

# If still stuck, verify database connectivity
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql "postgresql://user:pass@host/db" -c "SELECT version();"
```

#### Connection Issues

**Symptoms:** Migration fails with "connection refused" or "authentication failed".

**Diagnosis:**

```bash
# Check the secret exists and has correct format
kubectl get secret spicedb -o yaml

# Verify datastore configuration
helm get values spicedb
```

**Resolution:**

```bash
# Verify database is accessible from cluster
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql "postgresql://user:pass@host:port/db" -c "SELECT 1;"

# Update datastore credentials
helm upgrade spicedb charts/spicedb \
  --set config.datastore.hostname=correct-host \
  --set config.datastore.password=correct-password \
  --reuse-values

# Or use an existing secret
helm upgrade spicedb charts/spicedb \
  --set config.existingSecret=my-spicedb-secret \
  --reuse-values
```

#### Manual Rollback

If a migration causes issues, roll back using Helm:

```bash
# List releases to find previous revision
helm history spicedb

# Rollback to previous revision
helm rollback spicedb

# Rollback to specific revision
helm rollback spicedb 3
```

**Warning:** SpiceDB does not support schema downgrades. Rolling back will restore the previous chart version, but database schema changes are permanent. You may need to restore from a database backup if schema changes cause issues.

#### Dry-Run Testing

Test migrations before applying to production:

```bash
# Render templates without installing
helm upgrade spicedb charts/spicedb \
  --dry-run \
  --debug \
  --set migrations.logLevel=debug

# Install to test namespace first
helm install spicedb-test charts/spicedb \
  --namespace spicedb-test \
  --create-namespace \
  --set config.datastore.hostname=test-db-host

# Verify migration succeeded
kubectl get jobs -n spicedb-test -l app.kubernetes.io/component=migration
kubectl logs -n spicedb-test -l app.kubernetes.io/component=migration
```

### Examples

#### Basic Migration with Debug Logging

```bash
helm install spicedb charts/spicedb \
  --set config.datastoreEngine=postgres \
  --set config.datastore.hostname=postgres.default.svc.cluster.local \
  --set config.datastore.username=spicedb \
  --set config.datastore.password=securepassword \
  --set config.datastore.database=spicedb \
  --set migrations.logLevel=debug
```

#### Phased Migration Example

```bash
# Phase 1: Write
helm upgrade spicedb charts/spicedb \
  --set image.tag=v1.30.0 \
  --set migrations.targetPhase=write \
  --reuse-values

# Wait and verify
kubectl wait --for=condition=complete job -l app.kubernetes.io/component=migration --timeout=600s

# Phase 2: Read
helm upgrade spicedb charts/spicedb \
  --set migrations.targetPhase=read \
  --reuse-values

kubectl wait --for=condition=complete job -l app.kubernetes.io/component=migration --timeout=600s

# Phase 3: Complete
helm upgrade spicedb charts/spicedb \
  --set migrations.targetPhase=complete \
  --reuse-values

# Clear for future upgrades
helm upgrade spicedb charts/spicedb \
  --set migrations.targetPhase="" \
  --reuse-values
```

#### Custom Resource Limits

For large databases that need more resources during migration:

```bash
helm upgrade spicedb charts/spicedb \
  --set migrations.resources.limits.cpu=2000m \
  --set migrations.resources.limits.memory=2Gi \
  --set migrations.resources.requests.cpu=1000m \
  --set migrations.resources.requests.memory=1Gi \
  --reuse-values
```

#### Disabling Cleanup

Keep migration jobs for debugging:

```bash
helm install spicedb charts/spicedb \
  --set migrations.cleanup.enabled=false \
  --set config.datastoreEngine=postgres \
  --set config.datastore.hostname=postgres.default.svc.cluster.local

# View all migration jobs (they won't be auto-deleted)
kubectl get jobs -l app.kubernetes.io/component=migration

# Manually clean up when done
kubectl delete jobs -l app.kubernetes.io/component=migration
```

#### Using Existing Secret

For production environments with external secret management:

```bash
# Create secret separately (e.g., via sealed-secrets, external-secrets)
kubectl create secret generic spicedb-datastore \
  --from-literal=datastore-uri='postgresql://user:pass@host:5432/spicedb?sslmode=verify-full'

# Install chart using existing secret
helm install spicedb charts/spicedb \
  --set config.datastoreEngine=postgres \
  --set config.existingSecret=spicedb-datastore
```

## TLS Configuration

SpiceDB supports TLS encryption for all network endpoints: gRPC API, HTTP dashboard, internal dispatch communication, and datastore connections. TLS is essential for production deployments to protect sensitive authorization data in transit.

### TLS Overview

This chart provides comprehensive TLS support for four distinct endpoints:

| Endpoint | Purpose | TLS Type | When to Enable |
|----------|---------|----------|----------------|
| **gRPC** | Primary client API | Server TLS | Production deployments, public exposure |
| **HTTP** | Dashboard, metrics | Server TLS | When accessing dashboard over untrusted networks |
| **Dispatch** | Inter-pod communication | Mutual TLS (mTLS) | Multi-replica deployments (highly recommended) |
| **Datastore** | Database connection | Client TLS/mTLS | CockroachDB (required), PostgreSQL with verify-ca/verify-full |

**When to use TLS:**
- **gRPC**: Always enable for production deployments and when exposing SpiceDB outside the cluster
- **HTTP**: Enable when the dashboard is accessed over untrusted networks or from outside the cluster
- **Dispatch**: Strongly recommended for multi-replica deployments to prevent unauthorized pods from joining the cluster
- **Datastore**: Required for CockroachDB; recommended for PostgreSQL in production

### Quick Start: Manual Certificate Creation

To manually create TLS certificates for testing or development:

```bash
# Create gRPC server certificate
kubectl create secret tls spicedb-grpc-tls \
  --cert=grpc-server.crt \
  --key=grpc-server.key

# Create HTTP server certificate
kubectl create secret tls spicedb-http-tls \
  --cert=http-server.crt \
  --key=http-server.key

# Create dispatch mTLS certificate (includes CA)
kubectl create secret generic spicedb-dispatch-tls \
  --from-file=tls.crt=dispatch.crt \
  --from-file=tls.key=dispatch.key \
  --from-file=ca.crt=dispatch-ca.crt

# Create datastore client certificate for CockroachDB
kubectl create secret generic spicedb-datastore-tls \
  --from-file=tls.crt=client.spicedb.crt \
  --from-file=tls.key=client.spicedb.key \
  --from-file=ca.crt=cockroachdb-ca.crt

# Install SpiceDB with TLS enabled
helm install spicedb charts/spicedb \
  --set tls.enabled=true \
  --set tls.grpc.secretName=spicedb-grpc-tls \
  --set tls.http.secretName=spicedb-http-tls \
  --set tls.dispatch.secretName=spicedb-dispatch-tls \
  --set tls.datastore.secretName=spicedb-datastore-tls \
  --set config.datastoreEngine=cockroachdb \
  --set config.datastore.hostname=cockroachdb.default.svc.cluster.local \
  --set config.datastore.sslMode=verify-full \
  --set config.datastore.sslRootCert=/etc/spicedb/tls/datastore/ca.crt
```

### cert-manager Integration

For production deployments, use [cert-manager](https://cert-manager.io/) to automate certificate lifecycle management, including creation, renewal, and rotation.

#### Prerequisites

Install cert-manager in your cluster:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Verify installation
kubectl wait --for=condition=Available --timeout=300s \
  deployment/cert-manager -n cert-manager
```

#### Complete cert-manager Setup

See [examples/cert-manager-integration.yaml](examples/cert-manager-integration.yaml) for a comprehensive example that includes:

- ClusterIssuer configuration (Let's Encrypt or private CA)
- Certificate resources for all four endpoints (gRPC, HTTP, dispatch, datastore)
- Proper certificate usages (serverAuth, clientAuth for mTLS)
- DNS names and Subject Alternative Names (SANs)
- Certificate renewal settings

**Quick deployment with cert-manager:**

```bash
# Create certificates using cert-manager
kubectl apply -f examples/cert-manager-integration.yaml

# Wait for certificates to be ready
kubectl wait --for=condition=Ready certificate \
  spicedb-grpc-tls \
  spicedb-http-tls \
  spicedb-dispatch-tls \
  spicedb-datastore-tls \
  --timeout=300s

# Verify secrets were created
kubectl get secret spicedb-grpc-tls spicedb-http-tls \
  spicedb-dispatch-tls spicedb-datastore-tls

# Install SpiceDB with TLS
helm install spicedb charts/spicedb \
  -f examples/production-cockroachdb-tls.yaml
```

#### Certificate Renewal with cert-manager

cert-manager automatically handles certificate renewal:

1. **Automatic Renewal**: Certificates are renewed based on the `renewBefore` setting (typically 30 days before expiration)
2. **Zero-Downtime**: Kubernetes automatically updates the mounted secrets in pods
3. **Monitoring**: Check renewal status with `kubectl get certificate`

```bash
# Check certificate expiration dates
kubectl get certificate -o custom-columns=\
NAME:.metadata.name,\
READY:.status.conditions[0].status,\
EXPIRY:.status.notAfter

# View certificate renewal history
kubectl get certificaterequest

# Force certificate renewal (for testing)
kubectl delete secret spicedb-grpc-tls
# cert-manager will automatically recreate it

# Monitor cert-manager logs
kubectl logs -n cert-manager deploy/cert-manager -f
```

### Configuration Examples

#### Example 1: gRPC TLS Only (Minimal)

Enable TLS only for the client-facing gRPC API:

```yaml
tls:
  enabled: true
  grpc:
    secretName: spicedb-grpc-tls

config:
  datastoreEngine: memory
```

#### Example 2: Full TLS with cert-manager

Complete production setup with all endpoints secured:

```yaml
tls:
  enabled: true
  grpc:
    secretName: spicedb-grpc-tls
  http:
    secretName: spicedb-http-tls
  dispatch:
    secretName: spicedb-dispatch-tls
  datastore:
    secretName: spicedb-datastore-tls

config:
  datastoreEngine: cockroachdb
  datastore:
    hostname: cockroachdb.default.svc.cluster.local
    sslMode: verify-full
    sslRootCert: /etc/spicedb/tls/datastore/ca.crt
    sslCert: /etc/spicedb/tls/datastore/tls.crt
    sslKey: /etc/spicedb/tls/datastore/tls.key

replicaCount: 3
```

See [examples/production-cockroachdb-tls.yaml](examples/production-cockroachdb-tls.yaml) for a complete production-ready configuration.

### Troubleshooting TLS

#### Common Issues

**Issue: Certificate not found**

```bash
# Symptoms
Error: secret "spicedb-grpc-tls" not found

# Diagnosis
kubectl get secret spicedb-grpc-tls
kubectl get certificate spicedb-grpc-tls
kubectl describe certificate spicedb-grpc-tls

# Solution
# Ensure certificate was created
kubectl apply -f examples/cert-manager-integration.yaml
kubectl wait --for=condition=Ready certificate spicedb-grpc-tls
```

**Issue: Certificate validation failed**

```bash
# Symptoms
transport: authentication handshake failed: x509: certificate signed by unknown authority

# Diagnosis
# Check if CA certificate is present in the secret
kubectl get secret spicedb-grpc-tls -o yaml
# Verify certificate chain
kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -text -noout

# Solution
# Ensure clients have the CA certificate
kubectl get secret spicedb-ca-key-pair -o jsonpath='{.data.ca\.crt}' | \
  base64 -d > ca.crt
# Distribute ca.crt to clients
```

**Issue: Dispatch mTLS connection failures**

```bash
# Symptoms
dispatch: connection refused or certificate verification failed

# Diagnosis
# Check if all pods have the dispatch certificate
kubectl exec -it spicedb-0 -- ls -la /etc/spicedb/tls/dispatch/
# Verify CA certificate is present
kubectl get secret spicedb-dispatch-tls -o jsonpath='{.data.ca\.crt}' | base64 -d

# Solution
# Ensure dispatch secret includes ca.crt, tls.crt, and tls.key
kubectl get secret spicedb-dispatch-tls -o yaml
# Verify all pods use certificates from the same CA
```

**Issue: CockroachDB connection fails with SSL error**

```bash
# Symptoms
datastore: pq: SSL is not enabled on the server

# Diagnosis
kubectl logs -l app.kubernetes.io/name=spicedb | grep -i ssl
helm get values spicedb | grep -A 10 datastore

# Solution
# Verify sslMode is set correctly
helm upgrade spicedb charts/spicedb \
  --set config.datastore.sslMode=verify-full \
  --set config.datastore.sslRootCert=/etc/spicedb/tls/datastore/ca.crt \
  --reuse-values
```

#### Verification Commands

```bash
# Check TLS configuration in running pods
kubectl exec spicedb-0 -- env | grep -E 'SPICEDB.*TLS|SPICEDB.*SSL'

# Test gRPC TLS endpoint
grpcurl -insecure spicedb.default.svc.cluster.local:50051 list

# Test gRPC TLS with client certificate
grpcurl \
  -cacert ca.crt \
  -cert client.crt \
  -key client.key \
  spicedb.example.com:50051 list

# Test HTTP TLS endpoint
curl -k https://spicedb.default.svc.cluster.local:8443/

# Check certificate expiration
kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -dates

# Verify certificate chain
kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl verify -CAfile ca.crt /dev/stdin
```

#### Debug Logging

Enable debug logging to troubleshoot TLS issues:

```bash
helm upgrade spicedb charts/spicedb \
  --set config.logLevel=debug \
  --reuse-values

# View TLS-related logs
kubectl logs -l app.kubernetes.io/name=spicedb | grep -i tls
```

### Security Best Practices

1. **Use TLS for all endpoints in production**
   - Prevents man-in-the-middle attacks
   - Protects sensitive authorization data

2. **Enable dispatch mTLS for multi-replica deployments**
   - Prevents unauthorized pods from joining the cluster
   - Ensures internal communication is authenticated

3. **Use verify-full SSL mode for datastores**
   - Verifies both certificate validity and hostname
   - Prevents connection to rogue database servers

4. **Rotate certificates regularly**
   - cert-manager handles this automatically
   - Set renewBefore to at least 30 days for 90-day certificates

5. **Monitor certificate expiration**
   - Set up alerts for upcoming expirations
   - Use cert-manager's built-in monitoring

6. **Use private CA for internal infrastructure**
   - More control over certificate lifecycle
   - No external dependencies or rate limits

7. **Separate certificates per endpoint**
   - Limits blast radius if a certificate is compromised
   - Allows independent certificate rotation

8. **Backup CA certificates and keys**
   - Store securely outside the cluster
   - Required for disaster recovery

## Dispatch Cluster Mode

SpiceDB supports dispatch cluster mode for distributed permission checking across multiple instances. When enabled, SpiceDB instances communicate with each other to distribute permission check workloads, improving performance for complex authorization queries.

### Overview

Dispatch cluster mode enables horizontal scaling of permission checks by allowing SpiceDB instances to delegate sub-problems to other instances in the cluster. This is particularly beneficial for:

- **Complex permission checks** with deep relationship traversal
- **High-throughput deployments** requiring load distribution
- **Large permission graphs** that benefit from distributed query execution

### When to Enable Dispatch Mode

Enable dispatch cluster mode when:

- Running **multiple replicas** (replicaCount > 1) for high availability
- Permission checks involve **deep relationship traversal** (e.g., hierarchical organizations)
- You need to **distribute query load** across multiple instances
- Planning for **horizontal scalability** of authorization workloads

**Note:** Dispatch mode requires at least 2 replicas to be effective. With a single replica, dispatch mode has no benefit.

### Configuration

```yaml
dispatch:
  enabled: true
  # Optional: Custom CA certificate for upstream verification
  upstreamCASecretName: ""
  # Optional: Cluster name for identification in logs/metrics
  clusterName: "production-main"

replicaCount: 3  # Multiple replicas required for dispatch mode

# Recommended: Enable mTLS for secure inter-pod communication
tls:
  enabled: true
  dispatch:
    secretName: spicedb-dispatch-tls
```

### Basic Dispatch Cluster Setup

```bash
helm install spicedb charts/spicedb \
  --set dispatch.enabled=true \
  --set replicaCount=3 \
  --set config.datastoreEngine=postgres \
  --set config.datastore.hostname=postgres.default.svc.cluster.local
```

This creates a 3-replica SpiceDB deployment with dispatch clustering enabled.

### Dispatch with mTLS (Recommended for Production)

For production deployments, enable mTLS to encrypt and authenticate inter-pod dispatch communication:

```bash
# Create dispatch mTLS certificates (see TLS Configuration section)
kubectl apply -f examples/cert-manager-integration.yaml

# Install with dispatch and mTLS
helm install spicedb charts/spicedb \
  --set dispatch.enabled=true \
  --set replicaCount=3 \
  --set tls.enabled=true \
  --set tls.dispatch.secretName=spicedb-dispatch-tls \
  --set config.datastoreEngine=postgres
```

### Custom Upstream CA Certificate

If your dispatch cluster uses certificates signed by a custom CA (not the same CA as tls.dispatch), provide the upstream CA certificate:

```bash
# Create secret with upstream CA certificate
kubectl create secret generic dispatch-upstream-ca \
  --from-file=ca.crt=upstream-ca.crt

# Install with custom upstream CA
helm install spicedb charts/spicedb \
  --set dispatch.enabled=true \
  --set dispatch.upstreamCASecretName=dispatch-upstream-ca \
  --set tls.enabled=true \
  --set tls.dispatch.secretName=spicedb-dispatch-tls \
  --set replicaCount=3
```

**Use case:** When connecting to external SpiceDB clusters or when using different CAs for different environments.

### How Dispatch Works

**Service Discovery:**
- SpiceDB uses Kubernetes DNS for service discovery
- Format: `{release-name}-spicedb.{namespace}.svc.cluster.local:50053`
- Each pod discovers other pods via the service endpoint
- Dispatch port: 50053 (automatically exposed by the chart)

**Load Distribution:**
- Permission checks are broken into sub-problems
- Sub-problems are dispatched to available instances
- Results are aggregated and returned to the client
- Load balancing is automatic across all healthy pods

**Communication Security:**
- **Without mTLS:** Plain-text gRPC communication on port 50053 (suitable for trusted networks)
- **With mTLS:** Encrypted and authenticated communication (recommended for production)

### Scaling Considerations

**Performance Impact:**
- ✅ **Improved:** Complex permission checks with deep relationship traversal
- ✅ **Improved:** High query throughput distributed across instances
- ⚠️ **Increased:** Network traffic between pods (inter-pod communication overhead)
- ⚠️ **Increased:** Latency for simple checks (due to dispatch coordination overhead)

**Recommendations:**
- Start with 3 replicas for small-to-medium workloads
- Scale to 5-10 replicas for high-throughput production deployments
- Monitor dispatch metrics (see Observability section) to tune replica count
- Use mTLS in production to secure inter-pod communication

### Network Performance Impact

Dispatch cluster mode increases network traffic between pods:

```
Single pod (dispatch disabled):
  Client → SpiceDB Pod → Datastore

Multi-pod dispatch cluster:
  Client → SpiceDB Pod A → SpiceDB Pod B → Datastore
                        ↘ SpiceDB Pod C → Datastore
```

**Mitigation strategies:**
- Deploy SpiceDB pods in the same availability zone (reduce cross-AZ latency)
- Use high-bandwidth network infrastructure (10Gbps+ recommended)
- Enable mTLS with efficient cipher suites
- Monitor dispatch latency metrics and adjust replica count

### mTLS Requirements for Production

**Why mTLS for Dispatch:**
- Prevents unauthorized pods from joining the cluster
- Encrypts sensitive authorization data in transit
- Authenticates each pod in the cluster (mutual authentication)

**Setting up dispatch mTLS:**

See the [TLS Configuration](#tls-configuration) section for complete setup instructions. Key points:

1. Create dispatch mTLS certificates via cert-manager or manual generation
2. Secret must contain: `tls.crt`, `tls.key`, `ca.crt`
3. Set `tls.enabled=true` and `tls.dispatch.secretName`
4. All pods use the same certificates signed by the same CA

**Distinction between tls.dispatch and dispatch.upstreamCASecretName:**
- `tls.dispatch`: Certificates used BY this instance to secure its own dispatch endpoint
- `dispatch.upstreamCASecretName`: CA certificate used to verify OTHER instances (optional, for custom CAs)

### Configuration Examples

#### Minimal Dispatch Setup (Development)

```yaml
dispatch:
  enabled: true

replicaCount: 3

config:
  datastoreEngine: memory
```

#### Production Dispatch with mTLS

```yaml
dispatch:
  enabled: true
  clusterName: "production-main"

replicaCount: 5

tls:
  enabled: true
  grpc:
    secretName: spicedb-grpc-tls
  dispatch:
    secretName: spicedb-dispatch-tls

config:
  datastoreEngine: postgres
  datastore:
    hostname: postgres.default.svc.cluster.local
```

#### Cross-Cluster Dispatch with Custom CA

```yaml
dispatch:
  enabled: true
  upstreamCASecretName: external-cluster-ca
  clusterName: "staging-test"

replicaCount: 3

tls:
  enabled: true
  dispatch:
    secretName: spicedb-dispatch-tls
```

### Verification

**Check dispatch connectivity:**

```bash
# Verify service DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup spicedb.default.svc.cluster.local

# Check dispatch port is exposed
kubectl get service spicedb -o yaml | grep -A 2 'name: dispatch'

# View dispatch logs
kubectl logs -l app.kubernetes.io/name=spicedb | grep -i dispatch

# Check if dispatch is enabled (look for SPICEDB_DISPATCH_CLUSTER_ENABLED)
kubectl exec deployment/spicedb -- env | grep DISPATCH
```

**Monitor dispatch metrics:**

See [Observability and Monitoring](#observability-and-monitoring) section for dispatch-specific metrics:
- `spicedb_dispatch_requests_total` - Total dispatch requests
- `spicedb_dispatch_duration_seconds` - Dispatch request latency

### Troubleshooting

**Issue: Dispatch connections failing**

```bash
# Symptoms
Error: dispatch: connection refused

# Diagnosis
# Check if dispatch port is exposed
kubectl get service spicedb -o yaml | grep -A 2 'port: 50053'

# Check pod-to-pod connectivity
kubectl exec deployment/spicedb -- wget -qO- http://spicedb:50053
```

**Issue: mTLS authentication failures**

```bash
# Symptoms
dispatch: certificate verification failed

# Diagnosis
# Check dispatch TLS configuration
kubectl exec deployment/spicedb -- env | grep DISPATCH.*TLS

# Verify certificates mounted correctly
kubectl exec deployment/spicedb -- ls -la /etc/spicedb/tls/dispatch/

# Check certificate validity
kubectl get secret spicedb-dispatch-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -text -noout
```

**Issue: High dispatch latency**

```bash
# Check metrics for slow dispatches
kubectl port-forward svc/spicedb 9090:9090
# Visit http://localhost:9090/metrics and look for spicedb_dispatch_duration_seconds

# Reduce replicas if dispatch overhead > benefit
helm upgrade spicedb charts/spicedb --set replicaCount=3 --reuse-values
```

**Issue: Pods not discovering each other**

```bash
# Verify service exists and has endpoints
kubectl get service spicedb
kubectl get endpoints spicedb

# Check DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup spicedb.default.svc.cluster.local

# Verify DISPATCH_UPSTREAM_ADDR is correct
kubectl exec deployment/spicedb -- env | grep DISPATCH_UPSTREAM_ADDR
# Should show: {release-name}-spicedb.{namespace}.svc.cluster.local:50053
```

## Ingress and Network Exposure

SpiceDB can be exposed outside the Kubernetes cluster using Ingress controllers. This section covers when to use Ingress, supported controllers, configuration patterns, and integration with NetworkPolicy for defense-in-depth security.

### When to Use Ingress

Use Ingress to expose SpiceDB when:

- **External Access Required**: Clients outside the Kubernetes cluster need to access SpiceDB
- **Centralized TLS Termination**: You want to manage TLS certificates at the ingress layer
- **Domain-Based Routing**: Multiple services share the same IP address, differentiated by hostname
- **Load Balancing**: Distribute traffic across multiple SpiceDB replicas (in addition to Service-level load balancing)
- **Advanced Traffic Management**: Rate limiting, authentication, header manipulation
- **Cost Optimization**: Reduce the number of cloud load balancers (one ingress controller serves many services)

**Do NOT use Ingress when:**
- Only internal cluster communication is needed (use ClusterIP Service instead)
- You need Layer 4 (TCP/UDP) load balancing without HTTP awareness (use LoadBalancer Service or NodePort)
- Maximum performance is critical and ingress overhead is unacceptable (use LoadBalancer Service)

### Supported Ingress Controllers

This chart has been tested with three major ingress controllers:

| Controller | Best For | gRPC Support | Pros | Cons |
|------------|----------|--------------|------|------|
| **NGINX** | General use, widest compatibility | Excellent (with annotations) | Most popular, extensive documentation, battle-tested | Requires reload on config changes |
| **Contour** | VMware/Tanzu environments, advanced routing | Native HTTP/2 support | Dynamic config, HTTPProxy CRD, low latency | Smaller community, more complex |
| **Traefik** | Cloud-native environments, dynamic config | Good (native support) | Easy configuration, automatic discovery | Less mature than NGINX |

### Quick Start Examples

#### NGINX Ingress (Most Common)

```bash
# Basic NGINX ingress with TLS
helm install spicedb charts/spicedb \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.hosts[0].host=spicedb.example.com \
  --set ingress.hosts[0].paths[0].path=/ \
  --set ingress.hosts[0].paths[0].pathType=Prefix \
  --set ingress.hosts[0].paths[0].servicePort=grpc \
  --set ingress.annotations."nginx\.ingress\.kubernetes\.io/backend-protocol"=GRPC \
  --set ingress.tls[0].secretName=spicedb-tls \
  --set ingress.tls[0].hosts[0]=spicedb.example.com
```

For production deployments, use the comprehensive example:

```bash
helm install spicedb charts/spicedb -f examples/production-ingress-nginx.yaml
```

See [examples/production-ingress-nginx.yaml](examples/production-ingress-nginx.yaml) for a complete production configuration with:
- Rate limiting
- Proxy timeout configuration for gRPC streams
- SSL redirect and HSTS headers
- cert-manager integration
- NetworkPolicy examples

#### Contour Ingress (VMware/Tanzu)

```bash
helm install spicedb charts/spicedb -f examples/production-ingress-contour.yaml
```

See [examples/production-ingress-contour.yaml](examples/production-ingress-contour.yaml) for Contour-specific features:
- H2C (HTTP/2 Cleartext) protocol configuration
- Timeout and retry policies
- HTTPProxy CRD examples
- Advanced health checks and rate limiting

#### Traefik Ingress

```bash
helm install spicedb charts/spicedb -f examples/ingress-traefik-grpc.yaml
```

See [examples/ingress-traefik-grpc.yaml](examples/ingress-traefik-grpc.yaml) for Traefik configuration.

### TLS Termination Options

There are two primary TLS termination strategies when using Ingress:

#### Option 1: TLS Termination at Ingress (Recommended)

The ingress controller terminates TLS, and communicates with SpiceDB over unencrypted HTTP/gRPC within the cluster.

**Advantages:**
- Centralized certificate management at ingress layer
- Easier certificate rotation (no SpiceDB restart needed)
- Ingress can inspect traffic for WAF, rate limiting, etc.
- Lower CPU usage on SpiceDB (no encryption overhead)

**Disadvantages:**
- Traffic is unencrypted between ingress and SpiceDB pods
- Requires trust in cluster network security

**Configuration:**

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  hosts:
    - host: spicedb.example.com
      paths:
        - path: /
          pathType: Prefix
          servicePort: grpc
  tls:
    - secretName: spicedb-tls
      hosts:
        - spicedb.example.com

# SpiceDB does NOT have TLS enabled
tls:
  enabled: false
```

**Use when:** Standard enterprise deployments, trusted cluster networks, centralized cert management required.

#### Option 2: TLS Passthrough (End-to-End Encryption)

The ingress controller forwards encrypted traffic without decryption, and SpiceDB terminates TLS.

**Advantages:**
- End-to-end encryption (traffic encrypted throughout)
- Ingress controller cannot inspect traffic (better for compliance/privacy)
- No TLS certificates stored at ingress layer
- Meets strict regulatory requirements (PCI DSS, HIPAA)

**Disadvantages:**
- More complex certificate management (certs at both layers)
- Ingress cannot perform HTTP-level features (rate limiting, header injection)
- Higher CPU usage on SpiceDB (encryption overhead)
- Requires special ingress controller configuration

**Configuration:**

```yaml
# SpiceDB TLS configuration
tls:
  enabled: true
  grpc:
    secretName: spicedb-grpc-tls

# Ingress passthrough configuration
ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "GRPCS"
  hosts:
    - host: spicedb.example.com
      paths:
        - path: /
          pathType: Prefix
          servicePort: grpc
  tls:
    - hosts:
        - spicedb.example.com
      # Note: No secretName - ingress doesn't need the cert
```

**Prerequisites:**
- NGINX Ingress Controller must be deployed with `--enable-ssl-passthrough` flag
- SpiceDB TLS certificates must be configured

**Use when:** Compliance requirements mandate end-to-end encryption, ingress cannot be trusted with decryption, or regulatory requirements.

See [examples/ingress-tls-passthrough.yaml](examples/ingress-tls-passthrough.yaml) for complete example.

### Configuration Patterns

#### Multi-Host Configuration

Expose different SpiceDB endpoints on separate hostnames for better access control and monitoring:

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
  hosts:
    # Client API on dedicated hostname
    - host: api.spicedb.example.com
      paths:
        - path: /
          pathType: Prefix
          servicePort: grpc

    # Dashboard on separate hostname (easier to restrict access)
    - host: dashboard.spicedb.example.com
      paths:
        - path: /
          pathType: Prefix
          servicePort: http

    # Metrics endpoint (restrict to monitoring namespace)
    - host: metrics.spicedb.example.com
      paths:
        - path: /metrics
          pathType: Exact
          servicePort: metrics

  tls:
    - secretName: api-tls
      hosts: [api.spicedb.example.com]
    - secretName: dashboard-tls
      hosts: [dashboard.spicedb.example.com]
    - secretName: metrics-tls
      hosts: [metrics.spicedb.example.com]
```

**Benefits:**
- Different firewall rules per endpoint
- Separate TLS certificates (reduced blast radius)
- Easier to restrict metrics endpoint to monitoring systems
- Clearer monitoring and logging (per-hostname metrics)

See [examples/ingress-multi-host-tls.yaml](examples/ingress-multi-host-tls.yaml).

#### Single-Host Path-Based Routing

All services accessible via different paths on one domain (simpler for development):

```yaml
ingress:
  enabled: true
  hosts:
    - host: spicedb.example.com
      paths:
        - path: /
          pathType: Prefix
          servicePort: grpc
        - path: /dashboard
          pathType: Prefix
          servicePort: http
        - path: /metrics
          pathType: Exact
          servicePort: metrics
  tls:
    - secretName: spicedb-tls
      hosts: [spicedb.example.com]
```

**Benefits:**
- Single DNS entry
- Single TLS certificate
- Simpler for development/testing

**Trade-offs:**
- Less granular access control
- All services share same hostname in logs/metrics

See [examples/ingress-single-host-multi-path.yaml](examples/ingress-single-host-multi-path.yaml).

### Controller-Specific Setup

#### NGINX Ingress Controller

**Installation:**

```bash
# Using Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace

# For TLS passthrough support (optional)
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.extraArgs.enable-ssl-passthrough=true
```

**Required Annotations for gRPC:**

```yaml
annotations:
  nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
  nginx.ingress.kubernetes.io/ssl-redirect: "true"
```

**Production Recommendations:**

```yaml
annotations:
  # gRPC protocol
  nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
  nginx.ingress.kubernetes.io/grpc-backend: "true"

  # Timeouts for long-lived streams
  nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
  nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
  nginx.ingress.kubernetes.io/proxy-connect-timeout: "60"

  # Rate limiting
  nginx.ingress.kubernetes.io/limit-rps: "100"

  # SSL redirect and HSTS
  nginx.ingress.kubernetes.io/ssl-redirect: "true"
  nginx.ingress.kubernetes.io/hsts: "true"
  nginx.ingress.kubernetes.io/hsts-max-age: "31536000"
```

#### Contour Ingress Controller

**Installation:**

```bash
kubectl apply -f https://projectcontour.io/quickstart/contour.yaml
```

**Required Annotations for gRPC:**

```yaml
annotations:
  projectcontour.io/upstream-protocol.h2c: "grpc"
  projectcontour.io/request-timeout: "infinity"
  projectcontour.io/response-timeout: "infinity"
```

**Production Recommendations:**

```yaml
annotations:
  # H2C protocol for gRPC
  projectcontour.io/upstream-protocol.h2c: "grpc"

  # Timeouts for streaming
  projectcontour.io/request-timeout: "infinity"
  projectcontour.io/response-timeout: "infinity"
  projectcontour.io/idle-timeout: "infinity"

  # Retry policy
  projectcontour.io/num-retries: "3"
  projectcontour.io/retry-on: "5xx,gateway-error"
  projectcontour.io/per-try-timeout: "10s"
```

**Advanced Features with HTTPProxy CRD:**

Contour provides HTTPProxy CRD for advanced features not available in standard Ingress. See [examples/production-ingress-contour.yaml](examples/production-ingress-contour.yaml) for HTTPProxy examples including:
- Native rate limiting
- Health checks
- Load balancing strategies
- Header manipulation

#### Traefik Ingress Controller

**Installation:**

```bash
helm repo add traefik https://traefik.github.io/charts
helm install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace
```

**Required Annotations:**

```yaml
annotations:
  traefik.ingress.kubernetes.io/router.entrypoints: websecure
  traefik.ingress.kubernetes.io/router.tls: "true"
  traefik.ingress.kubernetes.io/service.serversscheme: h2c
```

### NetworkPolicy Integration

NetworkPolicy provides network-level access control, complementing Ingress-level security. Enable NetworkPolicy for defense-in-depth security in production environments.

#### What NetworkPolicy Provides

**Security Benefits:**
- **Namespace Isolation**: Restrict which namespaces can communicate with SpiceDB
- **Pod-Level Access Control**: Only specific pods (e.g., ingress controller, Prometheus) can reach SpiceDB
- **Egress Control**: Limit SpiceDB's outbound connections to only required services (database, DNS)
- **Defense in Depth**: Network-level controls complement application-level authentication

**Limitations:**
- NetworkPolicy is enforced at Layer 3/4 (IP/port), not Layer 7 (HTTP/gRPC)
- Cannot inspect gRPC method calls or HTTP paths
- Requires CNI plugin support (Calico, Cilium, Weave Net)
- More complex to troubleshoot than application-level security

**When to Use:**
- Production environments with security compliance requirements
- Multi-tenant clusters where namespace isolation is critical
- Defense-in-depth security architecture
- Environments with untrusted workloads

#### Basic NetworkPolicy Example

Allow traffic only from ingress controller and Prometheus:

```yaml
networkPolicy:
  enabled: true
  policyTypes:
    - Ingress
    - Egress

  ingress:
    # Allow from NGINX Ingress Controller
    - from:
      - namespaceSelector:
          matchLabels:
            name: ingress-nginx
        podSelector:
          matchLabels:
            app.kubernetes.io/name: ingress-nginx
      ports:
      - protocol: TCP
        port: 50051  # gRPC
      - protocol: TCP
        port: 8443   # HTTP

    # Allow from Prometheus
    - from:
      - namespaceSelector:
          matchLabels:
            name: monitoring
      ports:
      - protocol: TCP
        port: 9090   # Metrics

    # Allow inter-pod dispatch (multi-replica)
    - from:
      - podSelector:
          matchLabels:
            app.kubernetes.io/name: spicedb
      ports:
      - protocol: TCP
        port: 50053  # Dispatch

  egress:
    # Allow DNS resolution
    - to:
      - namespaceSelector:
          matchLabels:
            name: kube-system
      ports:
      - protocol: UDP
        port: 53

    # Allow PostgreSQL connection
    - to:
      - namespaceSelector:
          matchLabels:
            name: database
      ports:
      - protocol: TCP
        port: 5432
```

**Important:** NetworkPolicy syntax depends on your CNI plugin. The above example works with most plugins but verify with your specific CNI documentation.

See production examples for complete NetworkPolicy configurations:
- [examples/production-ingress-nginx.yaml](examples/production-ingress-nginx.yaml)
- [examples/production-ingress-contour.yaml](examples/production-ingress-contour.yaml)

#### Contour-Specific NetworkPolicy

For Contour, allow traffic from Envoy pods (not Contour controller):

```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
      - namespaceSelector:
          matchLabels:
            name: projectcontour
        podSelector:
          matchLabels:
            app: envoy  # Envoy, not Contour controller
```

### cert-manager Integration

Use [cert-manager](https://cert-manager.io/) for automated TLS certificate provisioning and renewal.

**Installation:**

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

**Create ClusterIssuer:**

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

**Ingress Configuration:**

```yaml
ingress:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  tls:
    - secretName: spicedb-tls  # cert-manager creates this
      hosts:
        - spicedb.example.com
```

cert-manager automatically:
1. Detects the annotation
2. Creates a Certificate resource
3. Completes ACME challenge
4. Stores certificate in the specified secret
5. Renews certificates before expiration

See [examples/cert-manager-integration.yaml](examples/cert-manager-integration.yaml) for complete setup.

### Troubleshooting

#### gRPC Calls Failing Through Ingress

**Symptoms:**
- HTTP/REST calls work but gRPC calls fail
- Error: `unimplemented` or `unknown service`

**Diagnosis:**

```bash
# Check backend protocol annotation
kubectl get ingress spicedb -o yaml | grep backend-protocol

# Test direct connection (bypassing ingress)
kubectl port-forward svc/spicedb 50051:50051
grpcurl -plaintext localhost:50051 list
```

**Solution:**

Ensure backend protocol annotation is set:

```yaml
# For NGINX
nginx.ingress.kubernetes.io/backend-protocol: "GRPC"

# For Contour
projectcontour.io/upstream-protocol.h2c: "grpc"

# For Traefik
traefik.ingress.kubernetes.io/service.serversscheme: "h2c"
```

#### TLS Certificate Not Provisioned

**Symptoms:**
- Ingress shows no TLS
- Certificate not found errors

**Diagnosis:**

```bash
# Check certificate status
kubectl get certificate
kubectl describe certificate spicedb-tls

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager

# Verify ClusterIssuer
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod
```

**Common Issues:**
- DNS not propagated (wait or use DNS01 challenge)
- ClusterIssuer misconfigured
- ACME challenge failing (check ingress allows `/.well-known/acme-challenge/`)
- Rate limit hit (use staging issuer for testing)

#### 502 Bad Gateway

**Symptoms:**
- Ingress returns 502 error
- Upstream connection failures

**Diagnosis:**

```bash
# Check backend pods are running
kubectl get pods -l app.kubernetes.io/name=spicedb

# Check service endpoints
kubectl get endpoints spicedb

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# For Contour, check Envoy logs
kubectl logs -n projectcontour -l app=envoy
```

**Common Causes:**
- No healthy backend pods
- Service selector mismatch
- Wrong service port configured
- Backend pods not ready (readiness probe failing)

#### Timeout Errors on gRPC Streams

**Symptoms:**
- Long-lived gRPC streams disconnect after 60 seconds
- Timeout errors during streaming calls

**Solution:**

Increase proxy timeouts for gRPC:

```yaml
# NGINX
annotations:
  nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
  nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"

# Contour
annotations:
  projectcontour.io/request-timeout: "infinity"
  projectcontour.io/response-timeout: "infinity"
```

#### NetworkPolicy Blocking Traffic

**Symptoms:**
- Direct pod access works, but ingress returns connection errors
- Prometheus cannot scrape metrics

**Diagnosis:**

```bash
# Test from ingress namespace
kubectl run -it --rm -n ingress-nginx debug --image=busybox -- \
  wget -qO- http://spicedb.default.svc.cluster.local:50051

# Check NetworkPolicy
kubectl get networkpolicy
kubectl describe networkpolicy spicedb
```

**Solution:**

Verify namespace labels match NetworkPolicy selectors:

```bash
# Check actual namespace labels
kubectl get namespace ingress-nginx --show-labels

# Update NetworkPolicy to match
kubectl label namespace ingress-nginx name=ingress-nginx
```

#### Rate Limiting Too Aggressive

**Symptoms:**
- Legitimate traffic receives 429 (Too Many Requests)
- Clients experience intermittent failures

**Solution:**

Adjust rate limit annotations:

```yaml
# NGINX - increase limits
nginx.ingress.kubernetes.io/limit-rps: "200"  # Increased from 100
nginx.ingress.kubernetes.io/limit-burst-multiplier: "10"  # Allow bigger bursts
```

### Examples Reference

| Example File | Use Case | Controller | Features |
|-------------|----------|------------|----------|
| [production-ingress-nginx.yaml](examples/production-ingress-nginx.yaml) | Production NGINX setup | NGINX | Rate limiting, timeouts, NetworkPolicy, cert-manager |
| [production-ingress-contour.yaml](examples/production-ingress-contour.yaml) | Production Contour setup | Contour | HTTPProxy, retry policies, advanced routing |
| [ingress-examples.yaml](examples/ingress-examples.yaml) | Multi-controller examples | All | Quick reference for all controllers |
| [ingress-multi-host-tls.yaml](examples/ingress-multi-host-tls.yaml) | Multi-host routing | NGINX | Separate hosts per service |
| [ingress-single-host-multi-path.yaml](examples/ingress-single-host-multi-path.yaml) | Path-based routing | NGINX | Single hostname, multiple paths |
| [ingress-tls-passthrough.yaml](examples/ingress-tls-passthrough.yaml) | End-to-end encryption | NGINX | TLS passthrough, no ingress termination |
| [ingress-contour-grpc.yaml](examples/ingress-contour-grpc.yaml) | Contour gRPC | Contour | Basic Contour configuration |
| [ingress-traefik-grpc.yaml](examples/ingress-traefik-grpc.yaml) | Traefik gRPC | Traefik | Basic Traefik configuration |

For more details on each example, see [examples/README.md](examples/README.md).

## Observability and Monitoring

SpiceDB provides comprehensive observability features including Prometheus metrics, structured logging, and health endpoints. This chart includes built-in support for Prometheus Operator integration and configurable logging.

### Metrics

SpiceDB exposes Prometheus-compatible metrics on port 9090 at the `/metrics` endpoint. The metrics port is always exposed via the Service, making it available for scraping by any Prometheus instance.

#### Key Metrics to Monitor

| Metric | Type | Description | Alerting Threshold |
|--------|------|-------------|-------------------|
| `spicedb_check_duration_seconds` | Histogram | Permission check latency | p99 > 100ms |
| `spicedb_datastore_queries_total` | Counter | Total datastore queries executed | Rate increasing unexpectedly |
| `spicedb_dispatch_requests_total` | Counter | Inter-pod dispatch requests (multi-replica) | High error rate |
| `spicedb_grpc_server_handled_total` | Counter | gRPC requests by method and status | Error rate > 1% |
| `spicedb_grpc_server_handling_seconds` | Histogram | gRPC request duration | p99 > 500ms |
| `spicedb_relationships_estimate` | Gauge | Estimated relationship count | Unexpected drops |

#### Prometheus Integration (Manual)

For basic Prometheus scraping without Prometheus Operator:

```yaml
# prometheus-config.yaml
scrape_configs:
  - job_name: 'spicedb'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
```

Deploy SpiceDB with monitoring enabled:

```bash
helm install spicedb charts/spicedb \
  --set monitoring.enabled=true
```

This adds the following pod annotations for Prometheus auto-discovery:
- `prometheus.io/scrape: 'true'`
- `prometheus.io/port: '9090'`
- `prometheus.io/path: '/metrics'`

#### Prometheus Operator Integration (ServiceMonitor)

For environments using [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator), this chart supports automatic ServiceMonitor creation.

**Prerequisites:**
- Prometheus Operator installed in your cluster
- `monitoring.coreos.com/v1` CRD available

**Installation:**

```bash
helm install spicedb charts/spicedb \
  --set monitoring.enabled=true \
  --set monitoring.serviceMonitor.enabled=true \
  --set 'monitoring.serviceMonitor.additionalLabels.release=prometheus'
```

**Configuration Options:**

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s           # Scrape interval
    scrapeTimeout: 10s      # Scrape timeout (must be < interval)
    path: /metrics          # Metrics endpoint path

    # Labels for Prometheus to discover this ServiceMonitor
    additionalLabels:
      release: prometheus   # For prometheus-operator
      # OR
      prometheus: kube-prometheus  # For kube-prometheus-stack

    # Organizational metadata labels
    labels:
      team: platform
      component: authorization
```

**Prometheus Configuration:**

Ensure your Prometheus instance is configured to discover ServiceMonitors with matching labels:

```yaml
# For prometheus-operator
prometheus:
  prometheusSpec:
    serviceMonitorSelector:
      matchLabels:
        release: prometheus

# For kube-prometheus-stack
prometheus:
  prometheusSpec:
    serviceMonitorSelector:
      matchLabels:
        prometheus: kube-prometheus
```

**Verification:**

```bash
# Check ServiceMonitor was created
kubectl get servicemonitor

# Verify Prometheus discovered the target
kubectl port-forward svc/prometheus-operated 9090:9090
# Visit http://localhost:9090/targets and look for spicedb

# Test metrics endpoint directly
kubectl port-forward svc/spicedb 9090:9090
curl http://localhost:9090/metrics
```

### Logging

SpiceDB supports structured JSON logging and configurable log levels for operational visibility.

#### Log Configuration

```yaml
logging:
  # Log level: debug, info, warn, error
  level: info

  # Log format: json (structured), console (human-readable)
  format: json
```

**Log Levels:**
- `debug`: Verbose logging for troubleshooting (use in development/testing)
- `info`: Standard operational logging (recommended for production)
- `warn`: Only warnings and errors
- `error`: Only errors

**Log Formats:**
- `json`: Structured JSON logging (recommended for production, log aggregation)
- `console`: Human-readable console output (useful for development)

#### Production Logging Setup

For production deployments, use structured JSON logging with log aggregation:

```bash
helm install spicedb charts/spicedb \
  --set logging.level=info \
  --set logging.format=json \
  --set config.datastoreEngine=postgres \
  --set config.datastore.hostname=postgres.default.svc.cluster.local
```

Logs are emitted to stdout/stderr and can be collected by standard Kubernetes logging infrastructure:
- Fluentd/Fluent Bit
- Promtail (for Grafana Loki)
- Filebeat (for Elasticsearch)
- CloudWatch (for EKS)
- Stackdriver (for GKE)

#### Development Logging

For local development or debugging, use console format with debug level:

```bash
helm install spicedb-dev charts/spicedb \
  --set logging.level=debug \
  --set logging.format=console \
  --set config.datastoreEngine=memory
```

#### Viewing Logs

```bash
# View real-time logs
kubectl logs -f deployment/spicedb

# View logs from all replicas
kubectl logs -f -l app.kubernetes.io/name=spicedb

# Search for specific log patterns
kubectl logs -l app.kubernetes.io/name=spicedb | jq 'select(.level=="error")'

# View migration job logs
kubectl logs -l app.kubernetes.io/component=migration
```

### Grafana Dashboards

While this chart doesn't include pre-built Grafana dashboards, you can create custom dashboards using the exposed metrics.

#### Example Dashboard Panels

**Permission Check Latency:**
```promql
histogram_quantile(0.99,
  rate(spicedb_check_duration_seconds_bucket[5m])
)
```

**Request Rate:**
```promql
sum(rate(spicedb_grpc_server_handled_total[5m])) by (grpc_method)
```

**Error Rate:**
```promql
sum(rate(spicedb_grpc_server_handled_total{grpc_code!="OK"}[5m]))
/
sum(rate(spicedb_grpc_server_handled_total[5m]))
```

**Datastore Query Rate:**
```promql
rate(spicedb_datastore_queries_total[5m])
```

**Relationship Count:**
```promql
spicedb_relationships_estimate
```

#### Community Dashboards

Check the [SpiceDB community](https://github.com/authzed/spicedb/discussions) for shared Grafana dashboard JSON files. You can also export and share your own dashboards.

### Custom Pod Labels and Annotations

The chart supports adding custom labels and annotations to pods for organizational purposes or third-party integrations:

```yaml
podLabels:
  environment: production
  team: platform
  cost-center: engineering

podAnnotations:
  custom.io/annotation: value
  monitoring.example.com/enabled: "true"
```

These are merged with the default Prometheus annotations (when `monitoring.enabled=true`) and chart-managed labels.

### Health Endpoints

SpiceDB exposes health check endpoints on the HTTP port (default 8443):

- `/healthz` - Basic health check
- `/readyz` - Readiness check

These are automatically configured as Kubernetes liveness and readiness probes.

```bash
# Check health status
kubectl port-forward svc/spicedb 8443:8443
curl http://localhost:8443/healthz
```

### Alerting Examples

Example Prometheus alerting rules:

```yaml
groups:
  - name: spicedb
    rules:
      - alert: SpiceDBHighLatency
        expr: |
          histogram_quantile(0.99,
            rate(spicedb_check_duration_seconds_bucket[5m])
          ) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "SpiceDB permission checks are slow"
          description: "p99 latency is {{ $value }}s (threshold: 0.1s)"

      - alert: SpiceDBHighErrorRate
        expr: |
          sum(rate(spicedb_grpc_server_handled_total{grpc_code!="OK"}[5m]))
          /
          sum(rate(spicedb_grpc_server_handled_total[5m])) > 0.01
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "SpiceDB has high error rate"
          description: "Error rate is {{ $value | humanizePercentage }}"

      - alert: SpiceDBDown
        expr: up{job="spicedb"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "SpiceDB is down"
          description: "SpiceDB instance {{ $labels.instance }} is down"
```

### Troubleshooting Observability

#### Metrics Not Appearing in Prometheus

**Diagnosis:**
```bash
# Check if metrics port is exposed
kubectl get svc spicedb -o yaml | grep -A 5 'port: 9090'

# Test metrics endpoint
kubectl port-forward svc/spicedb 9090:9090
curl http://localhost:9090/metrics

# Check ServiceMonitor (if using Prometheus Operator)
kubectl get servicemonitor
kubectl describe servicemonitor spicedb
```

**Solution:**
```bash
# Verify monitoring is enabled
helm get values spicedb | grep -A 10 monitoring

# Enable monitoring if not set
helm upgrade spicedb charts/spicedb \
  --set monitoring.enabled=true \
  --reuse-values

# For Prometheus Operator, enable ServiceMonitor
helm upgrade spicedb charts/spicedb \
  --set monitoring.serviceMonitor.enabled=true \
  --set 'monitoring.serviceMonitor.additionalLabels.release=prometheus' \
  --reuse-values
```

#### ServiceMonitor Not Created

**Diagnosis:**
```bash
# Check if Prometheus Operator CRD is installed
kubectl get crd servicemonitors.monitoring.coreos.com

# Verify ServiceMonitor configuration
helm template spicedb charts/spicedb \
  --set monitoring.serviceMonitor.enabled=true \
  --api-versions monitoring.coreos.com/v1 | grep -A 20 'kind: ServiceMonitor'
```

**Solution:**
```bash
# Install Prometheus Operator if missing
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml

# Or install kube-prometheus-stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack
```

#### Logs Not Structured

**Diagnosis:**
```bash
# Check log format configuration
kubectl logs -l app.kubernetes.io/name=spicedb --tail=5

# Verify logging configuration
helm get values spicedb | grep -A 5 logging
```

**Solution:**
```bash
# Set structured JSON logging
helm upgrade spicedb charts/spicedb \
  --set logging.format=json \
  --reuse-values
```

## Development

This chart follows Test-Driven Development (TDD) practices. See [CONTRIBUTING.md](../../CONTRIBUTING.md) for the development workflow.

### Running Tests

```bash
# Lint the chart
helm lint . --strict

# Run unit tests
helm unittest .

# Validate security policies
helm template . | conftest test -p policies/ -
```

## License

Apache 2.0 - See [LICENSE](../../LICENSE) for details.
