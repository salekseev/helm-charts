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
