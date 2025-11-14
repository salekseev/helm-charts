# Prerequisites and Pre-Migration Checklist

**Navigation**: [Overview](./index.md) | **Prerequisites** | [Migration Steps](./step-by-step.md) | [Configuration](./configuration-conversion.md) | [Post-Migration](./post-migration.md) | [Troubleshooting](../../guides/troubleshooting/index.md)

This guide covers the prerequisites and pre-migration checklist before starting your migration from SpiceDB Operator to Helm.

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

## Next Steps

Once you've completed the pre-migration checklist:

1. **[Review Configuration Conversion](./configuration-conversion.md)** - Understand how to convert your SpiceDBCluster spec to Helm values
2. **[Start Migration](./step-by-step.md)** - Follow the step-by-step migration procedure

**Navigation**: [Overview](./index.md) | **Prerequisites** | [Migration Steps](./step-by-step.md) | [Configuration](./configuration-conversion.md) | [Post-Migration](./post-migration.md) | [Troubleshooting](../../guides/troubleshooting/index.md)
