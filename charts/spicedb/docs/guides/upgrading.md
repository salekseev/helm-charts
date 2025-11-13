# SpiceDB Upgrade Guide

This guide provides procedures for upgrading SpiceDB deployments to new versions.

## Table of Contents

- [Version Compatibility](#version-compatibility)
- [Pre-Upgrade Checklist](#pre-upgrade-checklist)
- [Upgrade Procedures](#upgrade-procedures)
- [Common Upgrade Scenarios](#common-upgrade-scenarios)
- [Rollback Procedures](#rollback-procedures)
- [Migration Considerations](#migration-considerations)

## Version Compatibility

### Kubernetes Version Compatibility

| Chart Version | Minimum Kubernetes Version | Tested Kubernetes Versions | Notes |
|---------------|---------------------------|---------------------------|-------|
| 2.0.x+        | 1.27+                     | 1.27, 1.28, 1.29, 1.30    | gRPC probes require 1.23+ |

### SpiceDB Version Compatibility

The chart `appVersion` specifies the default SpiceDB version. You can override this with `image.tag`.

**Important Notes:**
- Always check the [SpiceDB changelog](https://github.com/authzed/spicedb/releases) for breaking changes
- Test upgrades in a non-production environment first
- Database schema upgrades are forward-only (no downgrades)

### Operator Compatibility

The chart supports operator compatibility mode for migration:
- Use `operatorCompatibility.enabled: true` for seamless operator transition
- See [Operator to Helm Migration Guide](../migration/operator-to-helm.md)
- See [Helm to Operator Migration Guide](../migration/helm-to-operator.md)

### SpiceDB Version Breaking Changes

Refer to [SpiceDB Release Notes](https://github.com/authzed/spicedb/releases) for SpiceDB version-specific breaking changes.

**Common SpiceDB breaking changes:**
- API changes in gRPC schemas
- Configuration parameter renames
- Deprecated flags removed
- New required configuration parameters

## Pre-Upgrade Checklist

Before performing any upgrade, complete the following checklist:

### 1. Backup Database

**PostgreSQL:**
```bash
# Create backup
pg_dump -h postgres-host -U spicedb -d spicedb -F c -f spicedb-backup-$(date +%Y%m%d-%H%M%S).dump

# Verify backup
pg_restore -l spicedb-backup-*.dump | head -20
```

**CockroachDB:**
```bash
# Create backup to S3/GCS
cockroach sql --url="postgresql://root@cockroachdb:26257?sslmode=verify-full" \
  --execute="BACKUP DATABASE spicedb TO 's3://backups/spicedb-$(date +%Y%m%d-%H%M%S)?AWS_ACCESS_KEY_ID=xxx&AWS_SECRET_ACCESS_KEY=xxx';"

# Verify backup
cockroach sql --url="..." \
  --execute="SHOW BACKUPS IN 's3://backups?AWS_ACCESS_KEY_ID=xxx&AWS_SECRET_ACCESS_KEY=xxx';"
```

### 2. Review Release Notes

```bash
# Check SpiceDB release notes
# Visit: https://github.com/authzed/spicedb/releases

# Check chart changes
helm show readme charts/spicedb

# View chart changelog
git log --oneline charts/spicedb/Chart.yaml
```

### 3. Test in Staging

```bash
# Deploy to staging namespace
helm upgrade spicedb-staging charts/spicedb \
  --namespace=spicedb-staging \
  --values=staging-values.yaml \
  --wait

# Run smoke tests
kubectl run -it --rm test --image=grpcurl --restart=Never -- \
  grpcurl -plaintext spicedb.spicedb-staging:50051 list

# Run integration tests
# <your integration test suite>
```

### 4. Review Current Configuration

```bash
# Export current values
helm get values spicedb > current-values.yaml

# Export current manifest
helm get manifest spicedb > current-manifest.yaml

# Note current revision
helm history spicedb
```

### 5. Check Resource Availability

```bash
# Check node resources
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check PVC space (if using StatefulSet in future)
kubectl get pvc

# Check for PodDisruptionBudget
kubectl get pdb spicedb
```

### 6. Notify Stakeholders

- **Announce maintenance window**: Communicate planned downtime (if any)
- **Coordinate with dependent services**: Notify teams that depend on SpiceDB
- **Prepare rollback plan**: Document rollback procedure and timing

### 7. Verify Monitoring and Alerting

```bash
# Check monitoring is working
kubectl port-forward svc/spicedb 9090:9090
curl http://localhost:9090/metrics | grep -c spicedb_

# Verify alerting is configured
# Check Prometheus/AlertManager configuration
```

## Upgrade Procedures

### Standard Helm Upgrade

The standard upgrade procedure for most version updates:

```bash
# Update Helm repository (if using remote chart)
helm repo update

# Perform upgrade
helm upgrade spicedb charts/spicedb \
  --namespace=spicedb \
  --values=production-values.yaml \
  --wait \
  --timeout=10m

# Watch rollout
kubectl rollout status deployment/spicedb -n spicedb

# Verify new pods are running
kubectl get pods -n spicedb -l app.kubernetes.io/name=spicedb
```

### Upgrading SpiceDB Version Only

To upgrade only the SpiceDB application version without changing the chart:

```bash
# Upgrade to specific SpiceDB version
helm upgrade spicedb charts/spicedb \
  --set image.tag=v1.40.0 \
  --reuse-values \
  --wait

# Or specify in values file
cat <<EOF > upgrade-values.yaml
image:
  tag: v1.40.0
EOF

helm upgrade spicedb charts/spicedb \
  --values=production-values.yaml \
  --values=upgrade-values.yaml \
  --wait
```

### Upgrading Chart Version

To upgrade the Helm chart to a new version:

```bash
# View available chart versions
helm search repo spicedb --versions

# Upgrade to specific chart version
helm upgrade spicedb charts/spicedb \
  --version=0.2.0 \
  --values=production-values.yaml \
  --wait

# Review differences before upgrading
helm diff upgrade spicedb charts/spicedb \
  --version=0.2.0 \
  --values=production-values.yaml
```

### Zero-Downtime Upgrade Strategy

For production environments requiring zero downtime:

```bash
# Ensure rolling update strategy is configured
cat <<EOF > zero-downtime-values.yaml
replicaCount: 3

updateStrategy:
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1

podDisruptionBudget:
  enabled: true
  maxUnavailable: 1
EOF

# Perform upgrade
helm upgrade spicedb charts/spicedb \
  --values=production-values.yaml \
  --values=zero-downtime-values.yaml \
  --wait

# Monitor during upgrade
kubectl get pods -n spicedb -l app.kubernetes.io/name=spicedb --watch
```

**Zero-downtime upgrade process:**
1. Migrations run automatically (pre-upgrade hook)
2. New pod created with updated version (maxSurge: 1)
3. New pod becomes ready (passes readiness probe)
4. Old pod terminated (maxUnavailable: 0 ensures no unavailability)
5. Process repeats for remaining pods

## Common Upgrade Scenarios

### Scenario 1: Minor Version Upgrade (Patch Release)

**Example: v1.39.0 → v1.39.1**

Minor version upgrades typically include bug fixes and minor improvements with no schema changes.

```bash
# Pre-upgrade checks
helm get values spicedb > backup-values.yaml
helm history spicedb

# Perform upgrade
helm upgrade spicedb charts/spicedb \
  --set image.tag=v1.39.1 \
  --reuse-values \
  --wait

# Verify upgrade
kubectl get pods -n spicedb -l app.kubernetes.io/name=spicedb
kubectl logs -n spicedb -l app.kubernetes.io/name=spicedb --tail=50
```

**Expected downtime:** None (rolling update)

**Rollback risk:** Low

### Scenario 2: Minor Version Upgrade (Feature Release)

**Example: v1.39.0 → v1.40.0**

Feature releases may include new features, API additions, and potential schema changes.

```bash
# Review release notes for breaking changes
# Visit: https://github.com/authzed/spicedb/releases/tag/v1.40.0

# Backup database
pg_dump -h postgres-host -U spicedb -d spicedb -F c -f backup.dump

# Test in staging
helm upgrade spicedb-staging charts/spicedb \
  --namespace=spicedb-staging \
  --set image.tag=v1.40.0 \
  --reuse-values \
  --wait

# Run integration tests in staging
# <your test suite>

# If staging tests pass, upgrade production
helm upgrade spicedb charts/spicedb \
  --set image.tag=v1.40.0 \
  --reuse-values \
  --wait \
  --timeout=10m

# Monitor for errors
kubectl logs -n spicedb -l app.kubernetes.io/name=spicedb -f
```

**Expected downtime:** None (rolling update, migrations may take 1-5 minutes)

**Rollback risk:** Medium (schema changes may prevent rollback)

### Scenario 3: Major Version Upgrade

**Example: v1.x → v2.x**

Major version upgrades often include breaking changes and require careful planning.

**Important:** Always consult the [SpiceDB migration guide](https://authzed.com/docs/spicedb/getting-started/migrating) for major version upgrades.

```bash
# Step 1: Review migration guide
# Visit SpiceDB documentation for v1 → v2 migration

# Step 2: Create full database backup
pg_dump -h postgres-host -U spicedb -d spicedb -F c -f spicedb-v1-backup.dump

# Step 3: Test upgrade in isolated environment
# Create test namespace with database copy
kubectl create namespace spicedb-upgrade-test

# Deploy v1 with test data
helm install spicedb-test charts/spicedb \
  --namespace=spicedb-upgrade-test \
  --values=test-values.yaml

# Perform upgrade to v2
helm upgrade spicedb-test charts/spicedb \
  --namespace=spicedb-upgrade-test \
  --set image.tag=v2.0.0 \
  --reuse-values

# Verify functionality
# <run full test suite>

# Step 4: Schedule maintenance window
# Coordinate with stakeholders

# Step 5: Upgrade production during maintenance window
helm upgrade spicedb charts/spicedb \
  --set image.tag=v2.0.0 \
  --reuse-values \
  --wait \
  --timeout=15m

# Step 6: Verify and monitor
kubectl get pods -n spicedb -l app.kubernetes.io/name=spicedb
kubectl logs -n spicedb -l app.kubernetes.io/name=spicedb
```

**Expected downtime:** Depends on schema migration (typically 5-30 minutes)

**Rollback risk:** High (may require database restore)

### Scenario 4: Upgrading with Configuration Changes

When upgrading and modifying configuration simultaneously:

```bash
# Create new values file with changes
cat <<EOF > upgrade-values.yaml
image:
  tag: v1.40.0

replicaCount: 5  # Increased from 3

resources:
  limits:
    memory: 4Gi  # Increased from 2Gi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
EOF

# Review changes
helm diff upgrade spicedb charts/spicedb \
  --values=production-values.yaml \
  --values=upgrade-values.yaml

# Perform upgrade
helm upgrade spicedb charts/spicedb \
  --values=production-values.yaml \
  --values=upgrade-values.yaml \
  --wait
```

### Scenario 5: Enabling TLS on Existing Deployment

Enabling TLS requires careful coordination to avoid downtime.

**Important:** You cannot enable TLS without a maintenance window, as existing clients will fail to connect.

```bash
# Step 1: Generate/obtain TLS certificates
# See PRODUCTION_GUIDE.md for certificate generation

# Step 2: Create TLS secrets
kubectl create secret tls spicedb-grpc-tls --cert=grpc.crt --key=grpc.key
kubectl create secret tls spicedb-http-tls --cert=http.crt --key=http.key

# Step 3: Update client applications to use TLS
# This must be done before enabling TLS on server
# Update all client connection strings to use grpcs://

# Step 4: Enable TLS with maintenance window
cat <<EOF > enable-tls-values.yaml
tls:
  enabled: true
  grpc:
    secretName: spicedb-grpc-tls
  http:
    secretName: spicedb-http-tls
EOF

# Announce maintenance window
# Notify all dependent services

# Enable TLS
helm upgrade spicedb charts/spicedb \
  --values=production-values.yaml \
  --values=enable-tls-values.yaml \
  --wait

# Step 5: Verify TLS is working
kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
grpcurl -cacert ca.crt spicedb.example.com:50051 list
```

**Expected downtime:** 2-5 minutes (pod restart required)

**Rollback:** Easy (disable TLS and restart pods)

## Rollback Procedures

### Helm Rollback

Helm maintains a history of releases, allowing easy rollback:

```bash
# View release history
helm history spicedb -n spicedb

# Example output:
# REVISION  UPDATED                   STATUS      CHART           APP VERSION  DESCRIPTION
# 1         Mon Jan 1 10:00:00 2024   superseded  spicedb-0.1.0   v1.39.0      Install complete
# 2         Mon Jan 8 11:00:00 2024   superseded  spicedb-0.1.0   v1.40.0      Upgrade complete
# 3         Mon Jan 15 12:00:00 2024  deployed    spicedb-0.1.1   v1.40.0      Upgrade complete

# Rollback to previous revision
helm rollback spicedb -n spicedb

# Rollback to specific revision
helm rollback spicedb 2 -n spicedb

# Rollback with wait
helm rollback spicedb -n spicedb --wait --timeout=10m
```

### Manual Rollback

If Helm rollback is not possible:

```bash
# Redeploy previous version manually
helm upgrade spicedb charts/spicedb \
  --set image.tag=v1.39.0 \
  --values=backup-values.yaml \
  --wait

# Or use kubectl to update image
kubectl set image deployment/spicedb \
  spicedb=authzed/spicedb:v1.39.0 \
  -n spicedb
```

### Database Rollback

**Warning:** SpiceDB does not support schema downgrades. Rolling back application version does NOT rollback database schema.

If schema changes cause issues:

```bash
# Option 1: Restore from database backup (destructive)
# PostgreSQL
dropdb -h postgres-host -U postgres spicedb
createdb -h postgres-host -U postgres spicedb
pg_restore -h postgres-host -U spicedb -d spicedb backup.dump

# Option 2: Keep new schema, rollback application only
# This works if schema changes are backward compatible
helm rollback spicedb -n spicedb
```

### Rollback Decision Matrix

| Scenario | Helm Rollback Safe? | Database Restore Needed? | Expected Downtime |
|----------|-------------------|------------------------|------------------|
| Minor version upgrade (patch) | Yes | No | None |
| Feature upgrade (no schema changes) | Yes | No | None |
| Feature upgrade (backward-compatible schema) | Yes | No | None |
| Feature upgrade (breaking schema changes) | No | Maybe | 5-30 minutes |
| Major version upgrade | No | Likely | 30+ minutes |
| Configuration change only | Yes | No | None |

## Migration Considerations

### Automatic Migrations

By default, migrations run automatically during Helm upgrades via pre-upgrade hooks.

```bash
# Check if automatic migrations are enabled
helm get values spicedb | grep -A 5 migrations

# Verify migration job completed
kubectl get jobs -n spicedb -l app.kubernetes.io/component=migration
kubectl logs -n spicedb -l app.kubernetes.io/component=migration
```

**Automatic migration process:**
1. Helm upgrade initiated
2. Migration job created (pre-upgrade hook)
3. Migration job connects to database
4. Schema changes applied
5. Migration job completes
6. SpiceDB pods updated with new version
7. Cleanup job removes migration job (if enabled)

### Manual Migrations

For more control, disable automatic migrations and run manually:

```bash
# Disable automatic migrations
cat <<EOF > no-auto-migrate-values.yaml
migrations:
  enabled: false
EOF

helm upgrade spicedb charts/spicedb \
  --values=production-values.yaml \
  --values=no-auto-migrate-values.yaml

# Run migration manually
kubectl run spicedb-migration-manual \
  --image=authzed/spicedb:v1.40.0 \
  --restart=Never \
  --env="SPICEDB_DATASTORE_ENGINE=postgres" \
  --env="SPICEDB_DATASTORE_CONN_URI=postgresql://user:pass@host/db" \
  -- spicedb migrate head

# Monitor migration
kubectl logs spicedb-migration-manual -f

# After migration completes, upgrade SpiceDB
helm upgrade spicedb charts/spicedb \
  --set image.tag=v1.40.0 \
  --reuse-values
```

### Phased Migrations (Zero-Downtime)

For complex migrations, use SpiceDB's phased migration support:

**Phase 1: Write Phase**
```bash
# Run write phase migration
helm upgrade spicedb charts/spicedb \
  --set migrations.targetPhase=write \
  --set image.tag=v1.40.0 \
  --reuse-values

# Verify old version still works
kubectl logs -n spicedb -l app.kubernetes.io/name=spicedb | grep -i error
```

**Phase 2: Update Application**
```bash
# Update SpiceDB to new version
helm upgrade spicedb charts/spicedb \
  --set migrations.targetPhase=read \
  --set image.tag=v1.40.0 \
  --reuse-values

# Wait for all pods to be healthy
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=spicedb --timeout=300s
```

**Phase 3: Complete Migration**
```bash
# Complete the migration
helm upgrade spicedb charts/spicedb \
  --set migrations.targetPhase=complete \
  --reuse-values

# Clear targetPhase for future upgrades
helm upgrade spicedb charts/spicedb \
  --set migrations.targetPhase="" \
  --reuse-values
```

### Migration Troubleshooting

If migrations fail, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#migration-failures) for detailed troubleshooting steps.

**Quick diagnostics:**
```bash
# Check migration job status
kubectl get jobs -n spicedb -l app.kubernetes.io/component=migration

# View migration logs
kubectl logs -n spicedb -l app.kubernetes.io/component=migration

# Common issues:
# - Database connection failures
# - Permission errors
# - Schema conflicts
# - Timeout issues
```

## Post-Upgrade Verification

After any upgrade, verify the system is functioning correctly:

### 1. Check Pod Status

```bash
# All pods should be Running
kubectl get pods -n spicedb -l app.kubernetes.io/name=spicedb

# Check for restarts
kubectl get pods -n spicedb -l app.kubernetes.io/name=spicedb \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}'

# View recent events
kubectl get events -n spicedb --sort-by='.lastTimestamp' | head -20
```

### 2. Verify Migrations

```bash
# Check migration job completed
kubectl get jobs -n spicedb -l app.kubernetes.io/component=migration

# View migration logs
kubectl logs -n spicedb -l app.kubernetes.io/component=migration | tail -20

# Should see "migrations completed successfully"
```

### 3. Test Connectivity

```bash
# Port-forward to service
kubectl port-forward -n spicedb svc/spicedb 50051:50051

# Test gRPC API
grpcurl -plaintext localhost:50051 list

# Should return list of available services
```

### 4. Check Metrics

```bash
# Verify metrics endpoint
kubectl port-forward -n spicedb svc/spicedb 9090:9090
curl http://localhost:9090/metrics | grep -c spicedb_

# Check for error metrics
curl http://localhost:9090/metrics | grep spicedb_grpc_server_handled_total | grep -v "OK"
```

### 5. Monitor Logs

```bash
# Check for errors
kubectl logs -n spicedb -l app.kubernetes.io/name=spicedb | grep -i error

# Monitor logs in real-time
kubectl logs -n spicedb -l app.kubernetes.io/name=spicedb -f
```

### 6. Run Integration Tests

```bash
# Run your application-specific integration tests
# Example:
# - Create test relationships
# - Check permissions
# - Write schema
# - Watch for changes

# Verify existing data is accessible
# <your test commands>
```

## Best Practices

1. **Always test in non-production first**
   - Deploy to staging/dev environment
   - Run full integration test suite
   - Verify performance under load

2. **Backup before upgrading**
   - Database backup (mandatory)
   - Export current Helm values
   - Document current configuration

3. **Read release notes carefully**
   - Check for breaking changes
   - Review migration notes
   - Check deprecation warnings

4. **Monitor during and after upgrade**
   - Watch pod rollout
   - Check migration logs
   - Monitor error metrics

5. **Communicate with stakeholders**
   - Announce maintenance windows
   - Document upgrade procedures
   - Share rollback plan

6. **Keep dependencies updated**
   - Update Kubernetes regularly
   - Keep Helm up to date
   - Update monitoring tools

7. **Document your process**
   - Record upgrade steps taken
   - Note any issues encountered
   - Update runbooks

## Additional Resources

- [SpiceDB Releases](https://github.com/authzed/spicedb/releases)
- [SpiceDB Documentation](https://authzed.com/docs)
- [Helm Upgrade Documentation](https://helm.sh/docs/helm/helm_upgrade/)
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- [PRODUCTION_GUIDE.md](PRODUCTION_GUIDE.md)
