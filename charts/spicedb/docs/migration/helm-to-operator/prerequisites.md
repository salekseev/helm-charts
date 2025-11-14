# Migration Prerequisites

This document covers all requirements and preparations needed before starting
the migration from Helm to SpiceDB Operator.

## Navigation

- [Overview](./index.md)
- **Prerequisites** (this page)
- [Step-by-Step Migration](./step-by-step.md)
- [Configuration Conversion](./configuration-conversion.md)
- [Post-Migration Validation](./post-migration.md)
- [Troubleshooting](../../guides/troubleshooting/index.md)

## Required Prerequisites

### 1. Kubernetes Cluster

- **Version**: 1.19 or higher
- **Access**: Admin access to cluster
- **kubectl**: Configured and authenticated

Verify:

```bash
kubectl version --short
kubectl auth can-i '*' '*' --all-namespaces
```

### 2. Helm Installation

- **Version**: 3.12 or higher
- **Current Release**: Working SpiceDB deployment via this Helm chart

Verify:

```bash
helm version
helm list -A | grep spicedb
```

### 3. Database Backup

**CRITICAL**: Create a recent backup of your SpiceDB datastore before proceeding.

### 4. Tools

- `kubectl` - Kubernetes CLI
- `helm` - Helm 3 CLI
- `jq` - JSON processor (recommended)
- `yq` - YAML processor (optional, for conversion script)

## Recommended Prerequisites

### 1. Staging Environment

**CRITICAL**: Test the migration in a non-production environment first.

Steps for staging validation:

1. Deploy identical Helm configuration in staging
2. Follow this guide completely in staging
3. Validate application functionality
4. Measure actual downtime
5. Document any issues encountered

### 2. Maintenance Window

Plan for brief downtime during migration:

- **Expected downtime**: 2-5 minutes
- **Total migration time**: 10-15 minutes
- **Planning time**: 1-2 hours

Schedule during low-traffic period and communicate to stakeholders.

### 3. Monitoring Setup

Have monitoring/alerting in place to verify migration success:

- Application metrics collection
- Health check monitoring
- Log aggregation
- Alert configuration

## Compatibility Check

### Operator Version

- **Recommended**: Latest stable release
- **Minimum**: Check operator documentation for minimum supported version

### SpiceDB Version

- **Operator Support**: v1.13.0 and higher
- **Recommended**: Latest stable version

Check your current version:

```bash
kubectl get pods -l app.kubernetes.io/name=spicedb -o jsonpath='{.items[0].spec.containers[0].image}'
```

### Datastore Support

| Datastore | Helm Chart | Operator | Notes |
|-----------|-----------|----------|-------|
| PostgreSQL | Yes | Yes | Fully supported |
| CockroachDB | Yes | Yes | Fully supported |
| MySQL | No | Yes | New in Operator |
| Spanner | No | Yes | New in Operator |
| Memory | Yes | Yes | Development only |

## Pre-Migration Checklist

### 1. Document Current Configuration

Export your current Helm configuration:

```bash
# Export current values
helm get values spicedb -o yaml > helm-values-backup.yaml

# Export full release information
helm get all spicedb > helm-release-backup.yaml

# Document current release version
helm list -n <namespace>
```

### 2. Backup Database

Create a backup of your datastore **before** proceeding.

#### PostgreSQL Backup

```bash
# Using pg_dump
kubectl exec -n database postgresql-0 -- \
  pg_dump -U spicedb spicedb -F custom -f /tmp/spicedb-backup.dump

# Copy backup locally
kubectl cp database/postgresql-0:/tmp/spicedb-backup.dump ./spicedb-backup.dump

# Verify backup
ls -lh spicedb-backup.dump
```

#### CockroachDB Backup

```bash
# Create backup using CockroachDB BACKUP command
kubectl exec -n database cockroachdb-0 -- \
  cockroach sql --insecure -e \
  "BACKUP DATABASE spicedb TO 'nodelocal://1/spicedb-backup';"

# Verify backup
kubectl exec -n database cockroachdb-0 -- \
  cockroach sql --insecure -e \
  "SHOW BACKUPS IN 'nodelocal://1';"
```

### 3. Document Current State

Record current deployment information for reference and rollback:

```bash
# Get current pod status
kubectl get pods -l app.kubernetes.io/name=spicedb -o wide > pods-backup.txt

# Get current service configuration
kubectl get svc spicedb -o yaml > service-backup.yaml

# Get current secrets
kubectl get secret spicedb -o yaml > secret-backup.yaml

# Get current ConfigMaps (if any)
kubectl get configmap -l app.kubernetes.io/name=spicedb -o yaml > configmap-backup.yaml

# Document resource usage
kubectl top pods -l app.kubernetes.io/name=spicedb > resource-usage.txt
```

### 4. Review Helm-Specific Features

Identify features you're using that are **exclusive to Helm**. These will need
to be recreated manually after migration:

#### NetworkPolicy

If you have `networkPolicy.enabled: true` in your values:

```bash
# Check current NetworkPolicy
kubectl get networkpolicy -l app.kubernetes.io/name=spicedb -o yaml > networkpolicy-backup.yaml
```

**Action Required**: You'll need to create NetworkPolicy manually after
migration.

#### Ingress

If you have `ingress.enabled: true` in your values:

```bash
# Check current Ingress
kubectl get ingress -l app.kubernetes.io/name=spicedb -o yaml > ingress-backup.yaml
```

**Action Required**: You'll need to create Ingress manually after migration.

#### ServiceMonitor

If you have `monitoring.serviceMonitor.enabled: true` in your values:

```bash
# Check current ServiceMonitor
kubectl get servicemonitor -l app.kubernetes.io/name=spicedb -o yaml > servicemonitor-backup.yaml
```

**Action Required**: You'll need to create ServiceMonitor manually after
migration.

### 5. Verify Current Deployment Health

Ensure your current Helm deployment is healthy before migrating:

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=spicedb

# All pods should be Running
# Expected output:
# NAME                       READY   STATUS    RESTARTS   AGE
# spicedb-xxxxxxxxx-xxxxx    1/1     Running   0          10d

# Check logs for errors
kubectl logs -l app.kubernetes.io/name=spicedb --tail=100 | grep -i error

# Test connectivity
kubectl port-forward pod/$(kubectl get pod -l app.kubernetes.io/name=spicedb -o jsonpath='{.items[0].metadata.name}') 50051:50051 &
grpcurl -plaintext -d '{"service":"authzed.api.v1.SchemaService"}' \
  localhost:50051 grpc.health.v1.Health/Check
```

## Pre-Migration Validation

Before proceeding to migration, verify:

- [ ] Database backup created and verified
- [ ] Current configuration documented and backed up
- [ ] All Helm-specific features identified
- [ ] Current deployment is healthy
- [ ] Staging environment tested (if available)
- [ ] Maintenance window scheduled
- [ ] Stakeholders notified
- [ ] Rollback procedure reviewed

## Next Steps

Once all prerequisites are met, proceed to
[Step-by-Step Migration](./step-by-step.md).
