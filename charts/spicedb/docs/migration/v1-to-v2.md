# SpiceDB Helm Chart: v1.x to v2.0 Migration Guide

## Overview

This guide provides step-by-step instructions for upgrading the SpiceDB Helm chart from v1.x to v2.0+.

**Good news:** v2.0 maintains **100% backward compatibility** with v1.x configurations. Despite the major version bump, there are **no breaking changes**. You can upgrade immediately using your existing values.yaml without modifications.

**What's new in v2.0:**
- Operator compatibility mode for seamless SpiceDB Operator migration
- Four production-ready configuration presets
- Strategic merge patch system for advanced customization
- Enhanced health probes with gRPC protocol support
- Migration status tracking and validation
- Improved resource defaults (opt-in via presets)
- Comprehensive documentation reorganization

## Table of Contents

- [Breaking Changes](#breaking-changes)
- [Changed Defaults](#changed-defaults)
- [New Features](#new-features)
- [Backward Compatibility](#backward-compatibility)
- [Upgrade Prerequisites](#upgrade-prerequisites)
- [Step-by-Step Upgrade Procedure](#step-by-step-upgrade-procedure)
- [Post-Upgrade Enhancements](#post-upgrade-enhancements)
- [Values.yaml Conversion Examples](#valuesyaml-conversion-examples)
- [Common Issues and Solutions](#common-issues-and-solutions)
- [Rollback Procedure](#rollback-procedure)
- [Testing Checklist](#testing-checklist)

## Breaking Changes

**None.** v2.0 maintains full backward compatibility with v1.x.

All breaking changes originally planned for v2.0.0 (increased replica count, enabled dispatch by default, enabled PodDisruptionBudget) were **reverted** based on community feedback to ensure smooth upgrades without resource impact.

## Changed Defaults

While v2.0 maintains backward compatibility, some **internal defaults have improved**. Your existing configurations will continue to work unchanged, but you can opt into better defaults via presets.

### Resource Defaults (Unchanged in Upgrade)

Your v1.x resource configurations remain active. New defaults are available via `values-presets/`:

| Resource | v1.x Default | v2.0 Default (via presets) | Impact |
|----------|--------------|---------------------------|--------|
| CPU Requests | 100m | 500m (production presets) | No change on upgrade |
| Memory Requests | 256Mi | 1Gi (production presets) | No change on upgrade |
| CPU Limits | 1000m | 2000m (production presets) | No change on upgrade |
| Memory Limits | 1Gi | 4Gi (production presets) | No change on upgrade |

**To adopt new resource defaults**, use presets: `helm upgrade spicedb . -f values-presets/production-postgres.yaml`

### Health Probe Defaults (Enhanced in v2.0)

Health probe improvements apply automatically on upgrade:

| Probe | v1.x | v2.0 | Benefit |
|-------|------|------|---------|
| Startup Probe | 10 failures × 10s = 100s | 30 failures × 5s = 150s | Longer startup window |
| Liveness Protocol | HTTP only | gRPC (K8s 1.23+) or HTTP | Native gRPC health checks |
| Readiness Protocol | HTTP | gRPC (K8s 1.23+) or HTTP | More accurate readiness |

**No action required** - these improvements activate automatically.

### Deployment Strategy (Unchanged)

| Setting | v1.x | v2.0 | Notes |
|---------|------|------|-------|
| `replicaCount` | 1 | 1 | Unchanged for compatibility |
| `dispatch.enabled` | false | false | Unchanged for compatibility |
| `podDisruptionBudget.enabled` | false | false | Unchanged for compatibility |
| `maxUnavailable` | 0 | 0 | Zero-downtime upgrades |
| `maxSurge` | 1 | 1 | One extra pod during updates |

**To adopt production-ready defaults** (3 replicas, dispatch enabled), use presets.

## New Features

### 1. Operator Compatibility Mode

Enable seamless migration from SpiceDB Operator:

```yaml
operatorCompatibility:
  enabled: true
```

Adds operator-compatible annotations and labels. See [Operator to Helm Migration Guide](operator-to-helm.md).

### 2. Production-Ready Presets

Four pre-configured deployment profiles:

- **`development.yaml`** - Local development (memory datastore, 1 replica, minimal resources)
- **`production-postgres.yaml`** - PostgreSQL production (3 replicas, HA, PDB, autoscaling)
- **`production-cockroachdb.yaml`** - CockroachDB production (3 replicas, HA, zone distribution)
- **`production-ha.yaml`** - High-availability (5 replicas, multi-zone, topology spread)

Usage:
```bash
helm upgrade spicedb . -f values-presets/production-postgres.yaml
```

See [Preset Configuration Guide](../configuration/presets.md).

### 3. Strategic Merge Patch System

Customize Kubernetes resources without modifying templates:

```yaml
deployment:
  patches:
    - spec:
        template:
          metadata:
            annotations:
              custom.io/annotation: "value"

service:
  patches:
    - spec:
        sessionAffinity: ClientIP

ingress:
  patches:
    - metadata:
        annotations:
          nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
```

See `examples/patches-examples.yaml`.

### 4. Enhanced Health Checks

```yaml
probes:
  liveness:
    enabled: true
    protocol: grpc  # New: native gRPC health checks (K8s 1.23+)
    initialDelaySeconds: 30
    periodSeconds: 10
    failureThreshold: 3

  startup:
    enabled: true
    failureThreshold: 30  # Improved: 150s startup window
    periodSeconds: 5
```

### 5. Migration Status Tracking

v2.0 tracks migration history in a ConfigMap:

```bash
kubectl get configmap spicedb-migration-status -o yaml
```

Includes:
- Migration completion timestamps
- SpiceDB versions migrated
- Schema version history
- Rollback decision support

### 6. Auto-Secret Generation

Development convenience (not recommended for production):

```yaml
config:
  autogenerateSecret: true  # Generates secure random preshared keys
```

Production deployments should use:
```yaml
config:
  existingSecret: spicedb-secrets  # Reference existing secret
```

### 7. Cloud Workload Identity

ServiceAccount annotations for cloud IAM:

```yaml
serviceAccount:
  create: true
  annotations:
    # AWS EKS Pod Identity
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/spicedb

    # GCP Workload Identity
    iam.gke.io/gcp-service-account: spicedb@project.iam.gserviceaccount.com

    # Azure Workload Identity
    azure.workload.identity/client-id: "12345678-1234-1234-1234-123456789012"
```

See `examples/cloud-workload-identity.yaml`.

## Backward Compatibility

### What Still Works

All v1.x configurations continue to work unchanged:

✅ Existing `values.yaml` files work without modification
✅ All v1.x templates remain compatible
✅ Resource requests/limits unchanged unless you opt into presets
✅ Replica count remains 1 unless explicitly changed
✅ Dispatch cluster remains disabled unless explicitly enabled
✅ PodDisruptionBudget remains disabled unless explicitly enabled
✅ Secret configuration unchanged
✅ TLS configuration unchanged
✅ Migration hooks backward compatible
✅ Ingress and NetworkPolicy configurations unchanged

### What's Deprecated (Still Functional)

Nothing is deprecated in v2.0. All v1.x features remain supported.

## Upgrade Prerequisites

### 1. System Requirements

| Component | Minimum Version | Recommended Version | Notes |
|-----------|----------------|---------------------|-------|
| Kubernetes | 1.27.0 | 1.28+ | Chart sets `kubeVersion: ">=1.27.0-0"` |
| Helm | 3.8.0 | 3.13+ | Tested with Helm 3.13+ |
| kubectl | 1.27.0 | Match cluster version | For gRPC probes |

**Check versions:**
```bash
kubectl version --short
helm version --short
```

### 2. Backup Current Configuration

```bash
# Export current Helm values
helm get values spicedb -n spicedb > backup-values-v1.yaml

# Export current manifest
helm get manifest spicedb -n spicedb > backup-manifest-v1.yaml

# Note current revision
helm history spicedb -n spicedb
```

### 3. Backup Database

**PostgreSQL:**
```bash
# Create backup
pg_dump -h <postgres-host> -U spicedb -d spicedb -F c \
  -f spicedb-backup-$(date +%Y%m%d-%H%M%S).dump

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

### 4. Review Release Notes

- [v2.0.0 CHANGELOG](../CHANGELOG.md)
- [SpiceDB Release Notes](https://github.com/authzed/spicedb/releases/tag/v1.46.2)

### 5. Test in Staging

**Always test upgrades in a non-production environment first.**

```bash
# Deploy to staging namespace
helm upgrade spicedb-staging charts/spicedb \
  --namespace=spicedb-staging \
  --values=backup-values-v1.yaml \
  --wait \
  --timeout=10m

# Run smoke tests
kubectl run test -it --rm --restart=Never --image=fullstorydev/grpcurl -- \
  -plaintext spicedb.spicedb-staging:50051 list
```

## Step-by-Step Upgrade Procedure

### Option 1: Simple Upgrade (Keep Current Configuration)

Use this if you're happy with your current v1.x configuration:

```bash
# Step 1: Verify current state
helm list -n spicedb
kubectl get pods -n spicedb -l app.kubernetes.io/name=spicedb

# Step 2: Perform upgrade
helm upgrade spicedb charts/spicedb \
  --namespace=spicedb \
  --reuse-values \
  --wait \
  --timeout=10m

# Step 3: Verify upgrade
kubectl rollout status deployment/spicedb -n spicedb
kubectl get pods -n spicedb -l app.kubernetes.io/name=spicedb
```

**Expected behavior:**
- Rolling update (one pod at a time)
- No downtime (maxUnavailable: 0)
- Migration job runs (if using persistent datastore)
- All pods restart with new chart version

**Upgrade time:** 2-5 minutes (depending on migration duration)

### Option 2: Upgrade with Production Presets

Use this to adopt production-ready defaults:

```bash
# Step 1: Merge your v1.x values with preset
cat backup-values-v1.yaml values-presets/production-postgres.yaml > merged-values.yaml

# Edit merged-values.yaml to resolve any conflicts
# Preset values typically override for better defaults

# Step 2: Review changes with helm diff (optional but recommended)
helm diff upgrade spicedb charts/spicedb \
  --namespace=spicedb \
  --values=merged-values.yaml

# Step 3: Perform upgrade
helm upgrade spicedb charts/spicedb \
  --namespace=spicedb \
  --values=merged-values.yaml \
  --wait \
  --timeout=10m

# Step 4: Verify upgrade
kubectl rollout status deployment/spicedb -n spicedb
kubectl get pods -n spicedb -l app.kubernetes.io/name=spicedb
```

**Expected changes when using `production-postgres.yaml`:**
- Replica count: 1 → 3 (gradual scale-up)
- Resource requests/limits increased
- PodDisruptionBudget created (maxUnavailable: 1)
- HorizontalPodAutoscaler enabled (min: 3, max: 10)
- Pod anti-affinity rules for zone distribution

**Upgrade time:** 5-10 minutes (includes scale-up and pod distribution)

### Option 3: Upgrade with Helm Diff Plugin

For maximum visibility:

```bash
# Install helm-diff plugin (if not installed)
helm plugin install https://github.com/databus23/helm-diff

# Preview changes
helm diff upgrade spicedb charts/spicedb \
  --namespace=spicedb \
  --reuse-values \
  --show-secrets

# Review output, then proceed with upgrade
helm upgrade spicedb charts/spicedb \
  --namespace=spicedb \
  --reuse-values \
  --wait \
  --timeout=10m
```

## Post-Upgrade Enhancements

After upgrading to v2.0, consider these optional improvements:

### 1. Adopt Production Presets

If you upgraded with `--reuse-values`, you can gradually adopt production defaults:

```bash
# Scale to 3 replicas for HA
helm upgrade spicedb charts/spicedb \
  --namespace=spicedb \
  --reuse-values \
  --set replicaCount=3

# Enable PodDisruptionBudget
helm upgrade spicedb charts/spicedb \
  --namespace=spicedb \
  --reuse-values \
  --set podDisruptionBudget.enabled=true \
  --set podDisruptionBudget.maxUnavailable=1

# Enable HorizontalPodAutoscaler
helm upgrade spicedb charts/spicedb \
  --namespace=spicedb \
  --reuse-values \
  --set autoscaling.enabled=true \
  --set autoscaling.minReplicas=3 \
  --set autoscaling.maxReplicas=10
```

Or use a preset:
```bash
helm upgrade spicedb charts/spicedb \
  --namespace=spicedb \
  --values=values-presets/production-postgres.yaml \
  --wait
```

### 2. Enable gRPC Health Probes

If running Kubernetes 1.23+:

```yaml
probes:
  liveness:
    protocol: grpc  # More accurate than HTTP
  readiness:
    protocol: grpc
```

### 3. Add Strategic Patches

Customize resources without forking templates:

```yaml
deployment:
  patches:
    - spec:
        template:
          spec:
            priorityClassName: system-cluster-critical
```

### 4. Enable Migration Status Tracking

Already enabled by default in v2.0. View status:

```bash
kubectl get configmap spicedb-migration-status -n spicedb -o yaml
```

### 5. Configure Cloud Workload Identity

If running on cloud providers:

```yaml
serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/spicedb  # AWS
    # OR
    iam.gke.io/gcp-service-account: spicedb@project.iam.gserviceaccount.com  # GCP
    # OR
    azure.workload.identity/client-id: "uuid"  # Azure
```

See `examples/cloud-workload-identity.yaml`.

## Values.yaml Conversion Examples

### Example 1: Minimal v1.x Configuration

**v1.x values.yaml:**
```yaml
replicaCount: 1

config:
  datastoreEngine: postgres
  existingSecret: spicedb-secrets

service:
  type: ClusterIP
  grpcPort: 50051
```

**v2.0 equivalent (unchanged):**
```yaml
# No changes needed! v1.x config works as-is
replicaCount: 1

config:
  datastoreEngine: postgres
  existingSecret: spicedb-secrets

service:
  type: ClusterIP
  grpcPort: 50051
```

### Example 2: Production PostgreSQL

**v1.x values.yaml:**
```yaml
replicaCount: 3

image:
  tag: v1.40.0

config:
  datastoreEngine: postgres
  existingSecret: spicedb-postgres-secrets

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
```

**v2.0 with preset:**
```yaml
# Option 1: Use preset directly
# helm upgrade spicedb . -f values-presets/production-postgres.yaml

# Option 2: Override preset values
# helm upgrade spicedb . -f values-presets/production-postgres.yaml -f custom.yaml

# custom.yaml:
image:
  tag: v1.40.0  # Override preset version

config:
  existingSecret: spicedb-postgres-secrets  # Your secret name

autoscaling:
  maxReplicas: 10  # Override preset max
```

**Benefits of using preset:**
- Pre-configured PodDisruptionBudget
- Pre-configured pod anti-affinity
- Pre-configured topology spread constraints
- Pre-configured health probes
- Tested production defaults

### Example 3: High-Availability CockroachDB

**v1.x values.yaml:**
```yaml
replicaCount: 5

config:
  datastoreEngine: cockroachdb
  datastoreURI: "postgres://root@cockroachdb:26257/spicedb?sslmode=verify-full"
  existingSecret: spicedb-crdb-secrets

affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - spicedb
          topologyKey: kubernetes.io/hostname
```

**v2.0 with preset:**
```yaml
# Use production-ha preset
# helm upgrade spicedb . -f values-presets/production-ha.yaml -f custom.yaml

# custom.yaml:
config:
  datastoreEngine: cockroachdb
  datastoreURI: "postgres://root@cockroachdb:26257/spicedb?sslmode=verify-full"
  existingSecret: spicedb-crdb-secrets

replicaCount: 5  # Preset uses 5 by default
```

**Preset provides:**
- Multi-zone topology spread constraints
- Strict pod anti-affinity
- PodDisruptionBudget (maxUnavailable: 1)
- Autoscaling (min: 3, max: 15)
- Production resource limits

### Example 4: Development with Memory Datastore

**v1.x values.yaml:**
```yaml
replicaCount: 1

config:
  datastoreEngine: memory

resources:
  requests:
    cpu: 100m
    memory: 256Mi
```

**v2.0 with preset:**
```yaml
# Use development preset
# helm upgrade spicedb . -f values-presets/development.yaml

# No custom overrides needed - preset perfect for development
```

**Preset provides:**
- Memory datastore
- 1 replica
- Minimal resources (100m CPU, 256Mi RAM)
- Disabled migrations (not needed for memory)
- Fast startup

## Common Issues and Solutions

### Issue 1: Helm Upgrade Fails with "no matches for kind"

**Symptoms:**
```
Error: UPGRADE FAILED: unable to build kubernetes objects from current release manifest:
resource mapping not found for name: "spicedb"
```

**Cause:** Kubernetes API version incompatibility (old cluster < 1.27)

**Solution:**
```bash
# Check Kubernetes version
kubectl version --short

# Upgrade Kubernetes to 1.27+ or use v1.x chart
# v2.0 requires Kubernetes 1.27+ (kubeVersion: ">=1.27.0-0")
```

### Issue 2: Pods Not Starting After Upgrade

**Symptoms:**
```
kubectl get pods
NAME                       READY   STATUS             RESTARTS   AGE
spicedb-5d8f7c9b4f-abc123  0/1     CrashLoopBackOff   5          3m
```

**Cause 1:** Resource constraints (if using preset with higher requests)

**Solution:**
```bash
# Check pod events
kubectl describe pod spicedb-5d8f7c9b4f-abc123

# Check node resources
kubectl describe nodes | grep -A 5 "Allocated resources"

# Scale down if needed
helm upgrade spicedb charts/spicedb --reuse-values --set replicaCount=1
```

**Cause 2:** Migration failure

**Solution:**
```bash
# Check migration job logs
kubectl logs -l app.kubernetes.io/component=migration

# Check migration status
kubectl get configmap spicedb-migration-status -o yaml

# If migration failed, check database connectivity
kubectl exec -it spicedb-5d8f7c9b4f-abc123 -- \
  sh -c 'echo $SPICEDB_DATASTORE_CONN_URI'
```

### Issue 3: gRPC Health Probe Failures on Older Kubernetes

**Symptoms:**
```
Liveness probe failed: HTTP probe failed
```

**Cause:** Kubernetes < 1.23 doesn't support gRPC probes

**Solution:**
```yaml
# Use HTTP probes instead
probes:
  liveness:
    protocol: http  # Fallback to HTTP
  readiness:
    protocol: http
```

### Issue 4: PodDisruptionBudget Blocks Node Draining

**Symptoms:**
```
Cannot evict pod ... PodDisruptionBudget "spicedb" is blocking
```

**Cause:** PDB with only 1 replica or all replicas on same node

**Solution:**
```bash
# Option 1: Increase replicas (recommended)
helm upgrade spicedb charts/spicedb --reuse-values --set replicaCount=3

# Option 2: Temporarily disable PDB
kubectl delete pdb spicedb

# Option 3: Adjust PDB
helm upgrade spicedb charts/spicedb --reuse-values \
  --set podDisruptionBudget.maxUnavailable=2
```

### Issue 5: Secret Not Found After Upgrade

**Symptoms:**
```
Error: secret "spicedb-secrets" not found
```

**Cause:** Using preset with `autogenerateSecret: true` but `existingSecret` configured

**Solution:**
```yaml
# Choose one approach:

# Option 1: Use autogenerated secrets
config:
  autogenerateSecret: true
  existingSecret: ""  # Remove existingSecret

# Option 2: Use existing secrets
config:
  autogenerateSecret: false
  existingSecret: spicedb-secrets
```

## Rollback Procedure

If issues occur during upgrade, rollback is straightforward since v2.0 has no breaking changes.

### Option 1: Helm Rollback

```bash
# View release history
helm history spicedb -n spicedb

# Example output:
# REVISION  UPDATED                   STATUS      CHART           APP VERSION  DESCRIPTION
# 1         Mon Jan 1 10:00:00 2024   superseded  spicedb-1.1.2   v1.46.0      Install complete
# 2         Mon Jan 8 11:00:00 2024   deployed    spicedb-2.0.0   v1.46.2      Upgrade complete

# Rollback to previous revision (1)
helm rollback spicedb -n spicedb

# Or rollback to specific revision
helm rollback spicedb 1 -n spicedb --wait
```

### Option 2: Redeploy v1.x Values

```bash
# Reinstall with v1.x values
helm upgrade spicedb charts/spicedb \
  --version=1.1.2 \
  --values=backup-values-v1.yaml \
  --wait
```

### Database Rollback (If Needed)

**⚠️ Warning:** SpiceDB does not support schema downgrades. Only restore from backup if necessary.

```bash
# PostgreSQL restore (DESTRUCTIVE - drops existing data)
dropdb -h postgres-host -U postgres spicedb
createdb -h postgres-host -U postgres spicedb
pg_restore -h postgres-host -U spicedb -d spicedb spicedb-backup-*.dump

# After database restore, reinstall chart
helm rollback spicedb -n spicedb
```

### Rollback Decision Matrix

| Scenario | Helm Rollback Safe? | Database Restore Needed? | Notes |
|----------|-------------------|------------------------|-------|
| Pod failures after upgrade | Yes | No | Rollback chart, database unchanged |
| Resource exhaustion (preset) | Yes | No | Rollback or adjust resources |
| Migration job failed | Yes | Maybe | Check migration logs first |
| gRPC probe issues (old K8s) | Yes | No | Switch to HTTP probes |
| Functional issues | Yes | No | v2.0 has no schema changes |

## Testing Checklist

After upgrading to v2.0, verify the following:

### 1. Pod Status

```bash
# All pods should be Running
kubectl get pods -n spicedb -l app.kubernetes.io/name=spicedb

# Expected output:
# NAME                       READY   STATUS    RESTARTS   AGE
# spicedb-5d8f7c9b4f-abc123  1/1     Running   0          2m
# spicedb-5d8f7c9b4f-def456  1/1     Running   0          1m
# spicedb-5d8f7c9b4f-ghi789  1/1     Running   0          30s

# Check for restarts (should be 0)
kubectl get pods -n spicedb -l app.kubernetes.io/name=spicedb \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}'
```

### 2. Migration Status

```bash
# Check migration job completed
kubectl get jobs -n spicedb -l app.kubernetes.io/component=migration

# View migration status ConfigMap (v2.0 feature)
kubectl get configmap spicedb-migration-status -n spicedb -o yaml

# Check migration logs
kubectl logs -n spicedb -l app.kubernetes.io/component=migration | tail -20
```

### 3. Connectivity Tests

```bash
# Port-forward to service
kubectl port-forward -n spicedb svc/spicedb 50051:50051 &

# Test gRPC API
grpcurl -plaintext localhost:50051 list

# Expected output:
# grpc.health.v1.Health
# grpc.reflection.v1alpha.ServerReflection
# authzed.api.v1.SchemaService
# authzed.api.v1.PermissionsService
# authzed.api.v1.WatchService
# authzed.api.v1.ExperimentalService

# Kill port-forward
pkill -f "port-forward.*50051"
```

### 4. Health Endpoints

```bash
# Test gRPC health (K8s 1.23+)
grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check

# Expected output:
# {
#   "status": "SERVING"
# }

# Test HTTP health (fallback)
kubectl port-forward -n spicedb svc/spicedb 8443:8443 &
curl -k https://localhost:8443/healthz

# Expected output:
# OK

pkill -f "port-forward.*8443"
```

### 5. Metrics

```bash
# Port-forward to metrics
kubectl port-forward -n spicedb svc/spicedb 9090:9090 &

# Check metrics endpoint
curl http://localhost:9090/metrics | grep -c spicedb_

# Should return > 0 (many SpiceDB metrics available)

# Check for errors
curl http://localhost:9090/metrics | grep spicedb_grpc_server_handled_total | grep -v "OK"

pkill -f "port-forward.*9090"
```

### 6. Functional Tests

```bash
# Write a test schema
grpcurl -plaintext -d @ localhost:50051 authzed.api.v1.SchemaService/WriteSchema <<EOF
{
  "schema": "definition user {}"
}
EOF

# Create a test relationship
grpcurl -plaintext -d @ localhost:50051 authzed.api.v1.PermissionsService/WriteRelationships <<EOF
{
  "updates": [
    {
      "operation": "OPERATION_TOUCH",
      "relationship": {
        "resource": {"objectType": "user", "objectId": "alice"},
        "relation": "member",
        "subject": {"object": {"objectType": "user", "objectId": "bob"}}
      }
    }
  ]
}
EOF

# Check permission
grpcurl -plaintext -d @ localhost:50051 authzed.api.v1.PermissionsService/CheckPermission <<EOF
{
  "resource": {"objectType": "user", "objectId": "alice"},
  "permission": "member",
  "subject": {"object": {"objectType": "user", "objectId": "bob"}}
}
EOF

# Expected output:
# {
#   "permissionship": "PERMISSIONSHIP_HAS_PERMISSION"
# }
```

### 7. Load Testing (Optional)

```bash
# Run your application-specific load tests
# Verify performance is acceptable with new resource defaults
# Monitor CPU/memory usage

kubectl top pods -n spicedb -l app.kubernetes.io/name=spicedb
```

## Additional Resources

- [v2.0.0 CHANGELOG](../CHANGELOG.md)
- [Operator Comparison Guide](operator-comparison.md)
- [Production Deployment Guide](../guides/production.md)
- [Troubleshooting Guide](../guides/troubleshooting.md)
- [Upgrade Guide](../guides/upgrading.md)
- [Preset Configuration Guide](../configuration/presets.md)
- [SpiceDB Documentation](https://authzed.com/docs)

## Support

If you encounter issues not covered in this guide:

1. Check [Troubleshooting Guide](../guides/troubleshooting.md)
2. Search [existing GitHub issues](https://github.com/salekseev/helm-charts/issues)
3. Create a [new issue](https://github.com/salekseev/helm-charts/issues/new) with:
   - Helm chart version (v1.x → v2.0)
   - Kubernetes version
   - Output of `helm get values spicedb`
   - Output of `kubectl describe pod <pod-name>`
   - Relevant logs from `kubectl logs`

---

**Congratulations on upgrading to v2.0!** Enjoy the new features, improved defaults, and enhanced documentation.
