# Migration Failures

[← Back to Troubleshooting Index](index.md)

This guide covers issues related to database schema migrations during SpiceDB installation and upgrades.

## Symptoms

- Helm installation/upgrade hangs
- Migration job fails with errors
- SpiceDB pods never start
- Error: "migrations failed"

## Initial Diagnosis

```bash
# Check migration job status
kubectl get jobs -l app.kubernetes.io/component=migration

# View migration job details
kubectl describe job -l app.kubernetes.io/component=migration

# Check migration logs
kubectl logs -l app.kubernetes.io/component=migration

# View recent events
kubectl get events --sort-by='.lastTimestamp' | grep migration
```

## Common Causes and Solutions

### 1. Database Connection Errors

**Symptoms:**

```text
connection refused
authentication failed
could not connect to database
```

**Diagnosis:**

```bash
# Test database connectivity from a debug pod
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql "postgresql://spicedb:password@postgres-host:5432/spicedb"

# For CockroachDB
kubectl run -it --rm debug --image=cockroachdb/cockroach:latest --restart=Never -- \
  sql --url "postgresql://spicedb:password@cockroachdb:26257/spicedb"
```

**Solutions:**

- Verify database hostname and port are correct in values
- Check database credentials:

  ```bash
  # Verify secret exists and has correct format
  kubectl get secret spicedb -o yaml
  kubectl get secret spicedb -o jsonpath='{.data.datastore-uri}' | base64 -d
  ```

- Ensure database allows connections from Kubernetes pods:
  - Check security groups/firewall rules
  - Verify database network policies
  - Test from pod in same network namespace
- For SSL errors, verify `sslMode` matches database configuration:
  - PostgreSQL: `disable`, `require`, `verify-ca`, `verify-full`
  - CockroachDB: requires `verify-full` in production

### 2. Permission Issues

**Symptoms:**

```text
permission denied for database
must be owner of database
permission denied to create table
```

**Diagnosis:**

```bash
# Connect to database and check permissions
psql -h postgres-host -U spicedb -d spicedb -c "\dp"

# For CockroachDB
cockroach sql --url="..." --execute="SHOW GRANTS ON DATABASE spicedb;"
```

**Solutions:**

- Grant required permissions to SpiceDB user:

  ```sql
  -- PostgreSQL
  GRANT ALL PRIVILEGES ON DATABASE spicedb TO spicedb;
  GRANT ALL PRIVILEGES ON SCHEMA public TO spicedb;

  -- CockroachDB
  GRANT ALL ON DATABASE spicedb TO spicedb;
  ```

- Ensure user has CREATE permission on the database
- For managed databases, check IAM roles and policies

### 3. Schema Conflicts

**Symptoms:**

```text
table already exists
duplicate key value
schema version mismatch
```

**Diagnosis:**

```bash
# Check existing schema
psql -h postgres-host -U spicedb -d spicedb -c "\dt"

# Check SpiceDB migration history
psql -h postgres-host -U spicedb -d spicedb \
  -c "SELECT * FROM alembic_version;"
```

**Solutions:**

- **For clean slate**: Drop and recreate database:

  ```sql
  DROP DATABASE spicedb;
  CREATE DATABASE spicedb;
  GRANT ALL PRIVILEGES ON DATABASE spicedb TO spicedb;
  ```

- **For existing database**: Check if migrations are partially applied:

  ```bash
  # Delete failed migration job and retry
  kubectl delete job -l app.kubernetes.io/component=migration
  helm upgrade spicedb charts/spicedb --reuse-values
  ```

- **Version conflicts**: Ensure SpiceDB version is compatible with existing schema:
  - Cannot downgrade SpiceDB versions
  - Restore from database backup if downgrade needed

### 4. Migration Job Timeout

**Symptoms:**

```text
Job has reached the specified deadline
activeDeadlineSeconds exceeded
```

**Diagnosis:**

```bash
kubectl describe job -l app.kubernetes.io/component=migration
# Look for "DeadlineExceeded" in events

# Check migration progress in logs
kubectl logs -l app.kubernetes.io/component=migration -f
```

**Solutions:**

- Large databases may need more time. The default timeout is 600 seconds (10 minutes).
- Manually create migration job with longer timeout:

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
          image: authzed/spicedb:v1.39.0
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

  ```bash
  kubectl apply -f extended-migration-job.yaml
  kubectl wait --for=condition=complete job/spicedb-migration-extended --timeout=3600s
  ```

### 5. Migration Job Stuck

**Symptoms:**

- Migration job shows as "Running" but makes no progress
- Logs show no activity for extended period

**Diagnosis:**

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/component=migration

# View detailed logs
kubectl logs -l app.kubernetes.io/component=migration -f

# Check for database locks (PostgreSQL)
psql -h postgres-host -U postgres -d spicedb -c \
  "SELECT * FROM pg_locks WHERE NOT granted;"

# Check long-running queries
psql -h postgres-host -U postgres -d spicedb -c \
  "SELECT pid, now() - query_start AS duration, query
   FROM pg_stat_activity
   WHERE state = 'active' AND now() - query_start > interval '1 minute';"
```

**Solutions:**

- Delete stuck job and retry:

  ```bash
  kubectl delete job -l app.kubernetes.io/component=migration
  helm upgrade spicedb charts/spicedb --reuse-values
  ```

- Check for database locks and terminate blocking queries:

  ```sql
  -- PostgreSQL: Terminate blocking query
  SELECT pg_terminate_backend(pid) FROM pg_stat_activity
  WHERE pid = <blocking_pid>;
  ```

- Verify database has sufficient resources (CPU, memory, IOPS)
- Check network connectivity between migration pod and database

### 6. Migration Cleanup Job Failures

**Symptoms:**

```text
Error from server (Forbidden): jobs.batch "spicedb-migration-cleanup" is forbidden
User "system:serviceaccount:default:spicedb" cannot delete resource "jobs"
```

**Diagnosis:**

```bash
# Check if cleanup is enabled
helm get values spicedb | grep -A 3 cleanup

# Check RBAC permissions
kubectl auth can-i delete jobs --as=system:serviceaccount:default:spicedb

# Check cleanup job logs
kubectl logs -l app.kubernetes.io/component=migration-cleanup
```

**Solutions:**

- Disable cleanup if RBAC permissions cannot be granted:

  ```bash
  helm upgrade spicedb charts/spicedb \
    --set migrations.cleanup.enabled=false \
    --reuse-values
  ```

- Grant necessary RBAC permissions (if RBAC is enabled):

  ```yaml
  # This is automatically created by the chart when rbac.create=true
  # If using custom RBAC, ensure these rules are included:
  apiVersion: rbac.authorization.k8s.io/v1
  kind: Role
  metadata:
    name: spicedb
  rules:
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["get", "list", "delete"]
  ```

- Manually clean up old migration jobs:

  ```bash
  kubectl delete jobs -l app.kubernetes.io/component=migration
  ```

## See Also

- [Connection Issues](connection-issues.md) - For database connectivity problems
- [Diagnostic Commands](diagnostic-commands.md) - For additional debugging tools
