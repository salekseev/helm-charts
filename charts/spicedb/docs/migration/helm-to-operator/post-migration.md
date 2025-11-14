# Post-Migration Validation

This document provides comprehensive validation procedures after completing the
migration from Helm to SpiceDB Operator.

## Navigation

- [Overview](./index.md)
- [Prerequisites](./prerequisites.md)
- [Step-by-Step Migration](./step-by-step.md)
- [Configuration Conversion](./configuration-conversion.md)
- **Post-Migration Validation** (this page)
- [Troubleshooting](../../guides/troubleshooting/index.md)

## Validation Overview

After completing the migration, perform these validation checks to ensure the
operator deployment is functioning correctly.

## 1. Check Pod Status

```bash
# All pods should be Running
kubectl get pods -l app.kubernetes.io/name=spicedb

# Expected output:
# NAME        READY   STATUS    RESTARTS   AGE
# spicedb-0   1/1     Running   0          5m
# spicedb-1   1/1     Running   0          5m
# spicedb-2   1/1     Running   0          5m

# Check for restarts (should be 0 or low)
kubectl get pods -l app.kubernetes.io/name=spicedb -o jsonpath='{.items[*].status.containerStatuses[*].restartCount}'
```

**Success Criteria:**

- All pods in `Running` status
- `READY` shows `1/1` for all pods
- `RESTARTS` is 0 or minimal

## 2. Check SpiceDBCluster Status

```bash
# Check overall status
kubectl get spicedbcluster spicedb

# Expected output:
# NAME      READY   STATUS    AGE
# spicedb   True    Running   5m

# Check detailed status
kubectl get spicedbcluster spicedb -o jsonpath='{.status}' | jq

# Expected conditions:
# {
#   "conditions": [
#     {
#       "type": "Ready",
#       "status": "True",
#       "reason": "AllReplicasReady"
#     },
#     {
#       "type": "Migrated",
#       "status": "True",
#       "reason": "MigrationComplete"
#     }
#   ],
#   "availableReplicas": 3,
#   "version": "v1.35.0"
# }
```

**Success Criteria:**

- `READY` is `True`
- `STATUS` is `Running`
- All conditions show `status: "True"`
- `availableReplicas` matches expected replica count

## 3. Test gRPC Connectivity

```bash
# Port-forward to test connectivity
kubectl port-forward pod/spicedb-0 50051:50051 &

# Get preshared key
export SPICEDB_TOKEN=$(kubectl get secret spicedb-operator-config -o jsonpath='{.data.preshared-key}' | base64 -d)

# Test with zed CLI (if installed)
zed context set migrated localhost:50051 "$SPICEDB_TOKEN" --insecure

# Read schema (should succeed)
zed schema read

# Test permission check (if you have existing schema)
zed permission check document:1 view user:alice

# Test with grpcurl
grpcurl -plaintext -d '{"service":"authzed.api.v1.SchemaService"}' \
  localhost:50051 grpc.health.v1.Health/Check

# Expected output:
# {
#   "status": "SERVING"
# }
```

**Success Criteria:**

- gRPC health check returns `SERVING`
- Schema read succeeds
- Permission checks work as expected

## 4. Test HTTP Connectivity

```bash
# Port-forward HTTP port
kubectl port-forward pod/spicedb-0 8443:8443 &

# Check health endpoint
curl -k https://localhost:8443/healthz

# Expected output:
# {"status":"ok"}

# Check metrics endpoint
curl -k https://localhost:8443/metrics | grep spicedb

# Should see metrics like:
# spicedb_dispatch_requests_total
# spicedb_grpc_requests_total
```

**Success Criteria:**

- Health endpoint returns `{"status":"ok"}`
- Metrics endpoint returns Prometheus-formatted metrics
- No connection errors

## 5. Verify Database Connectivity

```bash
# Check logs for database connection
kubectl logs -l app.kubernetes.io/name=spicedb --tail=100 | grep -i database

# Should see successful connection messages
# Look for lines like:
# "successfully connected to datastore"
# "datastore health check succeeded"

# Verify no connection errors
kubectl logs -l app.kubernetes.io/name=spicedb --tail=100 | grep -i error

# Check migrations ran successfully
kubectl logs -l app.kubernetes.io/name=spicedb --tail=100 | grep -i migration

# Expected:
# "migrations completed successfully"
# "datastore is at expected version"
```

**Success Criteria:**

- Successful database connection messages
- No error messages about connections
- Migrations completed successfully

## 6. Monitor Logs

```bash
# Check for errors in last 10 minutes
kubectl logs -l app.kubernetes.io/name=spicedb --since=10m | grep -i error

# Should return empty or only benign errors

# Monitor realtime logs
kubectl logs -l app.kubernetes.io/name=spicedb -f

# Look for:
# - Successful startup messages
# - No connection errors
# - No authentication errors
# - No migration errors
```

**Success Criteria:**

- No critical errors in logs
- Successful startup messages present
- No repeated error patterns

## 7. Verify NetworkPolicy (if created)

```bash
# Check NetworkPolicy exists
kubectl get networkpolicy spicedb

# Test connectivity from allowed namespace (e.g., ingress)
kubectl run -n ingress-nginx test-pod --rm -it --image=curlimages/curl -- \
  curl -v http://spicedb.default.svc.cluster.local:50051

# Should succeed

# Test connectivity from denied namespace (should fail)
kubectl run -n other test-pod --rm -it --image=curlimages/curl -- \
  curl -v --max-time 5 http://spicedb.default.svc.cluster.local:50051

# Should timeout or be refused
```

**Success Criteria:**

- Allowed namespaces can connect
- Denied namespaces cannot connect
- NetworkPolicy rules work as expected

## 8. Verify Ingress (if created)

```bash
# Check Ingress exists
kubectl get ingress spicedb

# Get Ingress URL
export INGRESS_URL=$(kubectl get ingress spicedb -o jsonpath='{.spec.rules[0].host}')

# Check Ingress status
kubectl get ingress spicedb -o jsonpath='{.status.loadBalancer.ingress}'

# Test external access (requires DNS and cert setup)
grpcurl -d '{"service":"authzed.api.v1.SchemaService"}' \
  $INGRESS_URL:443 grpc.health.v1.Health/Check

# Should return: {"status": "SERVING"}
```

**Success Criteria:**

- Ingress has valid IP/hostname
- External access works
- TLS certificate is valid
- Health checks succeed through Ingress

## 9. Verify Metrics Collection

```bash
# Check ServiceMonitor exists (if created)
kubectl get servicemonitor spicedb

# Query Prometheus for SpiceDB metrics (if Prometheus installed)
curl -s 'http://prometheus:9090/api/v1/query?query=up{job="spicedb"}' | jq

# Expected output should show targets up:
# {
#   "status": "success",
#   "data": {
#     "result": [
#       {
#         "metric": {
#           "job": "spicedb"
#         },
#         "value": [timestamp, "1"]
#       }
#     ]
#   }
# }

# Check Prometheus targets page
kubectl port-forward -n monitoring svc/prometheus-k8s 9090:9090 &
# Open browser to http://localhost:9090/targets
# Look for SpiceDB targets showing as UP
```

**Success Criteria:**

- ServiceMonitor exists and configured correctly
- Prometheus scraping metrics successfully
- All SpiceDB targets showing as `UP`
- Metrics visible in Prometheus UI

## 10. Performance Baseline

Compare performance before and after migration:

```bash
# Measure latency with zed
time zed permission check document:1 view user:alice

# Expected: Similar latency to pre-migration
# Typical: < 100ms for local checks

# Check resource usage
kubectl top pods -l app.kubernetes.io/name=spicedb

# Expected: Similar CPU/memory to pre-migration
```

**Success Criteria:**

- Latency comparable to pre-migration
- CPU usage within expected range
- Memory usage within expected range
- No performance degradation

## Validation Checklist

Use this checklist to track validation progress:

- [ ] All pods in Running status with minimal restarts
- [ ] SpiceDBCluster status shows Ready=True
- [ ] gRPC connectivity working
- [ ] HTTP health checks passing
- [ ] Database connectivity verified
- [ ] No errors in logs
- [ ] NetworkPolicy working (if applicable)
- [ ] Ingress working (if applicable)
- [ ] Metrics collection working (if applicable)
- [ ] Performance comparable to pre-migration

## FAQ

### What if some validation checks fail?

Review the [Troubleshooting](../../guides/troubleshooting/index.md) guide for specific issues.
Common problems and solutions are documented there.

### How long should I monitor after migration?

Monitor for at least 24-48 hours after migration to ensure stability during
normal traffic patterns.

### Can I rollback if issues are found later?

Yes, but it becomes more difficult after time passes. See the Rollback Procedure
in [Step-by-Step Migration](./step-by-step.md).

### What metrics should I monitor ongoing?

Key metrics to monitor:

- Pod restarts
- gRPC request latency
- Database connection pool usage
- Error rates
- Resource utilization (CPU/memory)

## Next Steps

After successful validation:

1. Monitor the deployment for 24-48 hours
2. Update runbooks and documentation
3. Train team on operator management
4. Review [Troubleshooting](../../guides/troubleshooting/index.md) for future reference
5. Consider enabling additional operator features like auto-updates

## Additional Resources

- [SpiceDB Operator Documentation](https://github.com/authzed/spicedb-operator/tree/main/docs)
- [Troubleshooting Guide](../../guides/troubleshooting/index.md)
- [Configuration Reference](./configuration-conversion.md)
