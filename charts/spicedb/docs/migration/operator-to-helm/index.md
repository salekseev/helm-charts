# Migration Guide: SpiceDB Operator to Helm Chart

This guide provides step-by-step instructions for migrating an existing SpiceDB deployment from the SpiceDB Operator to the Helm chart.

## Overview

The migration process involves converting your SpiceDBCluster configuration to Helm values, scaling down the operator-managed deployment, and deploying with Helm. Both deployments use the same database, ensuring no data loss.

**Estimated Downtime**: 2-5 minutes (time between operator scale-down and Helm ready)

**Data Loss Risk**: None (both use same database, no schema changes)

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

See [OPERATOR_COMPARISON.md](../OPERATOR_COMPARISON.md) for a detailed comparison.

## Migration Phases

This migration guide is organized into focused sections:

1. **[Prerequisites](./prerequisites.md)** - Pre-migration requirements and checklist
2. **[Step-by-Step Procedure](./step-by-step.md)** - Core migration steps (numbered)
3. **[Configuration Conversion](./configuration-conversion.md)** - Operator spec → Helm values mapping
4. **[Post-Migration](./post-migration.md)** - Enhancements and verification
5. **[Troubleshooting](../../guides/troubleshooting/index.md)** - Migration-specific issues

## Quick Reference

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

## Migration Process Overview

The migration follows these high-level steps:

1. **Prepare Helm Configuration**: Convert SpiceDBCluster spec to values.yaml
2. **Create Required Secrets**: Ensure secrets are in Helm-compatible format
3. **Scale Operator to 0**: Set SpiceDBCluster replicas to 0
4. **Install Helm Chart**: Deploy with Helm using converted configuration
5. **Verify Helm Deployment**: Ensure Helm deployment is healthy
6. **Delete SpiceDBCluster**: Remove operator-managed resources
7. **Create Additional Resources**: Add NetworkPolicy, Ingress, ServiceMonitor
8. **Uninstall Operator** (optional): Remove operator from cluster

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

## Additional Resources

- [Helm Chart Documentation](../../README.md)
- [OPERATOR_COMPARISON.md](../OPERATOR_COMPARISON.md) - Feature comparison
- [MIGRATION_HELM_TO_OPERATOR.md](../MIGRATION_HELM_TO_OPERATOR.md) - Reverse migration
- [PRODUCTION_GUIDE.md](../PRODUCTION_GUIDE.md) - Production deployment guide
- [SpiceDB Operator Docs](https://github.com/authzed/spicedb-operator/tree/main/docs)

## Support

- **Helm Chart Issues**: <https://github.com/salekseev/helm-charts/issues>
- **SpiceDB Discord**: <https://authzed.com/discord>
- **Migration Help**: Open issue with [migration] tag

## Changelog

- **2024-11-11**: Initial version
