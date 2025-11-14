# Performance Issues

[← Back to Troubleshooting Index](index.md)

This guide covers resource exhaustion and performance problems in SpiceDB deployments.

## Resource Exhaustion (OOMKilled)

**Symptoms:**

```text
OOMKilled
Error: failed to create containerd task: OOM Killed
pod continuously restarting
```

**Diagnosis:**

```bash
# Check pod resource usage
kubectl top pods -l app.kubernetes.io/name=spicedb

# Check resource limits
kubectl get pods -l app.kubernetes.io/name=spicedb -o yaml | grep -A 5 resources

# View pod events
kubectl describe pods -l app.kubernetes.io/name=spicedb

# Check for OOMKilled in events
kubectl get events --field-selector reason=OOMKilled
```

**Solutions:**

- **Increase memory limits**:

  ```bash
  helm upgrade spicedb charts/spicedb \
    --set resources.limits.memory=4Gi \
    --set resources.requests.memory=2Gi \
    --reuse-values
  ```

- **Check for memory leaks**:

  ```bash
  # Monitor memory usage over time
  kubectl top pods -l app.kubernetes.io/name=spicedb --watch

  # Check application logs for errors
  kubectl logs -l app.kubernetes.io/name=spicedb --tail=100
  ```

- **Optimize database queries**: Check slow query logs and add indexes

## CPU Throttling

**Symptoms:**

- High latency
- Slow response times
- CPU usage at 100% of limit

**Diagnosis:**

```bash
# Check CPU usage
kubectl top pods -l app.kubernetes.io/name=spicedb

# Check throttling metrics (requires Prometheus)
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Query: rate(container_cpu_cfs_throttled_seconds_total{pod=~"spicedb.*"}[5m])

# View CPU limits
kubectl get pods -l app.kubernetes.io/name=spicedb -o yaml | grep -A 3 "cpu:"
```

**Solutions:**

```bash
# Increase CPU limits
helm upgrade spicedb charts/spicedb \
  --set resources.limits.cpu=4000m \
  --set resources.requests.cpu=2000m \
  --reuse-values

# Or adjust HPA to scale earlier
helm upgrade spicedb charts/spicedb \
  --set autoscaling.targetCPUUtilizationPercentage=70 \
  --reuse-values
```

## Database Connection Pool Exhaustion

**Symptoms:**

```text
too many clients
connection pool exhausted
could not connect to database: max connections reached
```

**Diagnosis:**

```bash
# Check active connections (PostgreSQL)
psql -h postgres-host -U postgres -d spicedb -c \
  "SELECT count(*) FROM pg_stat_activity WHERE datname = 'spicedb';"

# Check max connections
psql -h postgres-host -U postgres -c "SHOW max_connections;"

# View connection pool configuration
kubectl logs -l app.kubernetes.io/name=spicedb | grep -i "connection pool"
```

**Solutions:**

- **Increase database max_connections**:

  ```sql
  -- PostgreSQL
  ALTER SYSTEM SET max_connections = 200;
  -- Restart required

  -- Or for managed databases, update parameter group
  ```

- **Reduce number of SpiceDB replicas temporarily**:

  ```bash
  helm upgrade spicedb charts/spicedb \
    --set replicaCount=3 \
    --reuse-values
  ```

- **Optimize connection usage**: Ensure connections are being released properly

## Slow Dispatch Performance

**Symptoms:**

- High latency for permission checks
- Slow dispatch metrics
- Timeouts on complex queries

**Diagnosis:**

```bash
# Check dispatch metrics
kubectl port-forward svc/spicedb 9090:9090
curl http://localhost:9090/metrics | grep spicedb_dispatch_duration_seconds

# View dispatch logs
kubectl logs -l app.kubernetes.io/name=spicedb | grep -i dispatch

# Check if dispatch is enabled
kubectl exec deployment/spicedb -- env | grep DISPATCH
```

**Solutions:**

```bash
# Reduce replica count if dispatch overhead > benefit
helm upgrade spicedb charts/spicedb \
  --set replicaCount=3 \
  --reuse-values

# Enable dispatch mTLS to ensure only valid pods communicate
helm upgrade spicedb charts/spicedb \
  --set tls.enabled=true \
  --set tls.dispatch.secretName=spicedb-dispatch-tls \
  --reuse-values

# Monitor dispatch latency and adjust scaling
kubectl get hpa spicedb --watch
```

## See Also

- [Pod Scheduling Problems](pod-scheduling.md) - For HPA and resource constraint issues
- [Diagnostic Commands](diagnostic-commands.md) - For performance monitoring tools
