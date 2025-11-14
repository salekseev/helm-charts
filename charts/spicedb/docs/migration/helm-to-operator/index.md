# Migration Guide: Helm Chart to SpiceDB Operator

This guide provides step-by-step instructions for migrating an existing SpiceDB
deployment from the Helm chart to the SpiceDB Operator.

## Navigation

- **[Prerequisites](./prerequisites.md)** - Pre-migration requirements and checklist
- **[Step-by-Step Migration](./step-by-step.md)** - Core migration procedure
- **[Configuration Conversion](./configuration-conversion.md)** - Helm values to
  Operator spec mapping
- **[Post-Migration Validation](./post-migration.md)** - Verification and testing
- **[Troubleshooting](../../guides/troubleshooting/index.md)** - Common issues and solutions

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

See [OPERATOR_COMPARISON.md](../OPERATOR_COMPARISON.md) for a detailed comparison.

## Migration Overview

The migration process follows these high-level steps:

1. **Install Operator**: Deploy SpiceDB Operator to cluster
2. **Convert Configuration**: Map Helm values to SpiceDBCluster CRD
3. **Create SpiceDBCluster**: Apply operator configuration (operator creates new
   deployment)
4. **Scale Down Helm**: Set Helm deployment to 0 replicas
5. **Verify Operator**: Ensure operator deployment is healthy
6. **Cleanup Helm**: Delete Helm release (keeping history for rollback)
7. **Recreate Helm-Only Resources**: Create NetworkPolicy, Ingress, ServiceMonitor
   manually

**Estimated Downtime**: 2-5 minutes (time between scaling Helm down and operator
up)

**Data Loss Risk**: None (both use same database, no schema changes)

## Decision Criteria

### Migrate to Operator if you

- Want automatic version updates with release channels
- Prefer Kubernetes-native CRD management
- Need automated self-healing and reconciliation
- Want structured status reporting via CRD
- Have simple deployment requirements

### Stay with Helm if you

- Require NetworkPolicy management
- Need Ingress resource creation
- Use Helm-specific GitOps workflows
- Require fine-grained resource customization
- Have complex pod/service annotations

## Quick Start Checklist

Before you begin, ensure:

- [ ] Read [Prerequisites](./prerequisites.md) and have all requirements met
- [ ] Tested migration in staging environment
- [ ] Created database backup
- [ ] Documented current Helm configuration
- [ ] Planned maintenance window (5-10 minutes downtime)
- [ ] Reviewed [Configuration Conversion](./configuration-conversion.md) for
  your specific setup

## Important Notes

**CRITICAL**: Never perform this migration in production without testing in
staging first.

**Data Safety**: The migration doesn't modify your database. Both Helm and
Operator deployments use the same PostgreSQL/CockroachDB database.

**Reversibility**: The migration is reversible. See
[MIGRATION_OPERATOR_TO_HELM.md](../MIGRATION_OPERATOR_TO_HELM.md) for rollback
procedures.

## Support

- **Operator Issues**: <https://github.com/authzed/spicedb-operator/issues>
- **Helm Chart Issues**: <https://github.com/salekseev/helm-charts/issues>
- **SpiceDB Discord**: <https://authzed.com/discord>
- **Migration Help**: Open issue with [migration] tag

## Additional Resources

- [SpiceDB Operator Documentation](https://github.com/authzed/spicedb-operator/tree/main/docs)
- [OPERATOR_COMPARISON.md](../OPERATOR_COMPARISON.md) - Feature comparison
- [MIGRATION_OPERATOR_TO_HELM.md](../MIGRATION_OPERATOR_TO_HELM.md) - Reverse
  migration
- [Helm Chart Documentation](../../README.md)
- [SpiceDB Documentation](https://authzed.com/docs)

## Next Steps

Start with [Prerequisites](./prerequisites.md) to prepare for migration.
