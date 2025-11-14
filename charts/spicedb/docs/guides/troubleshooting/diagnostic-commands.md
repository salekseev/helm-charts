# Diagnostic Commands

[← Back to Troubleshooting Index](index.md)

This guide provides useful commands for troubleshooting and debugging SpiceDB deployments.

## General Health Check

```bash
# Overall cluster status
kubectl get all -l app.kubernetes.io/name=spicedb

# Pod status and distribution
kubectl get pods -l app.kubernetes.io/name=spicedb -o wide

# Service endpoints
kubectl get svc spicedb
kubectl get endpoints spicedb

# Recent events
kubectl get events --sort-by='.lastTimestamp' | head -20

# Resource usage
kubectl top pods -l app.kubernetes.io/name=spicedb
kubectl top nodes
```

## Configuration Verification

```bash
# View current Helm values
helm get values spicedb

# View all resources created by Helm
helm get manifest spicedb

# Compare with original values
helm get values spicedb --revision 1

# View full deployment configuration
kubectl get deployment spicedb -o yaml
```

## Logging

```bash
# View recent logs
kubectl logs -l app.kubernetes.io/name=spicedb --tail=100

# Follow logs in real-time
kubectl logs -l app.kubernetes.io/name=spicedb -f

# View logs from specific pod
kubectl logs spicedb-0

# View previous container logs (if pod restarted)
kubectl logs spicedb-0 --previous

# Search for errors
kubectl logs -l app.kubernetes.io/name=spicedb | grep -i error

# View migration logs
kubectl logs -l app.kubernetes.io/component=migration

# View logs with timestamps
kubectl logs -l app.kubernetes.io/name=spicedb --timestamps
```

## Database Connectivity

```bash
# Test PostgreSQL connection
kubectl run -it --rm psql-test --image=postgres:15 --restart=Never -- \
  psql "postgresql://spicedb:password@postgres-host:5432/spicedb" -c "SELECT version();"

# Test CockroachDB connection
kubectl run -it --rm crdb-test --image=cockroachdb/cockroach:latest --restart=Never -- \
  sql --url "postgresql://spicedb:password@cockroachdb:26257/spicedb" -e "SELECT version();"

# Check database permissions
psql -h postgres-host -U spicedb -d spicedb -c "\dp"

# View active connections
psql -h postgres-host -U postgres -d spicedb -c \
  "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"
```

## Network Debugging

```bash
# DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup spicedb.default.svc.cluster.local

# Port connectivity
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  nc -zv spicedb 50051

# HTTP endpoint test
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v http://spicedb:8443/healthz

# DNS debugging
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  dig spicedb.default.svc.cluster.local

# Trace route
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  traceroute spicedb.default.svc.cluster.local
```

## Metrics and Performance

```bash
# View Prometheus metrics
kubectl port-forward svc/spicedb 9090:9090
curl http://localhost:9090/metrics

# Filter specific metrics
curl http://localhost:9090/metrics | grep spicedb_check_duration_seconds

# Check gRPC request metrics
curl http://localhost:9090/metrics | grep spicedb_grpc_server_handled_total

# View dispatch metrics
curl http://localhost:9090/metrics | grep spicedb_dispatch_
```

## See Also

- [Migration Failures](migration-failures.md) - For database migration debugging
- [TLS Errors](tls-errors.md) - For certificate verification commands
- [Connection Issues](connection-issues.md) - For network troubleshooting
- [Performance Issues](performance-issues.md) - For resource monitoring
