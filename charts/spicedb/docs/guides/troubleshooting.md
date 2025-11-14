# SpiceDB Troubleshooting Guide

This guide provides solutions to common issues encountered when deploying and operating SpiceDB.

## Table of Contents

- [Migration Failures](#migration-failures)
- [TLS Errors](#tls-errors)
- [Connection Issues](#connection-issues)
- [Performance Issues](#performance-issues)
- [Pod Scheduling Problems](#pod-scheduling-problems)
- [High Availability Issues](#high-availability-issues)
- [Diagnostic Commands](#diagnostic-commands)

## Migration Failures

### Symptoms

- Helm installation/upgrade hangs
- Migration job fails with errors
- SpiceDB pods never start
- Error: "migrations failed"

### Diagnosis

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

### Common Causes and Solutions

#### 1. Database Connection Errors

**Symptoms:**

```
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

#### 2. Permission Issues

**Symptoms:**

```
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

#### 3. Schema Conflicts

**Symptoms:**

```
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

#### 4. Migration Job Timeout

**Symptoms:**

```
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

#### 5. Migration Job Stuck

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

#### 6. Migration Cleanup Job Failures

**Symptoms:**

```
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

## TLS Errors

### Certificate Validation Failures

**Symptoms:**

```
x509: certificate signed by unknown authority
transport: authentication handshake failed
certificate has expired
certificate is not valid for requested name
```

**Diagnosis:**

```bash
# Check if TLS secrets exist
kubectl get secret spicedb-grpc-tls spicedb-http-tls spicedb-dispatch-tls

# Verify certificate contents
kubectl get secret spicedb-grpc-tls -o yaml

# Check certificate validity
kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -text -noout

# Check certificate expiration
kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -dates

# Verify certificate chain
kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl verify -CAfile ca.crt /dev/stdin
```

**Solutions:**

- **Certificate not found**: Ensure TLS secrets are created before deployment:

  ```bash
  # Verify secret exists
  kubectl get secret spicedb-grpc-tls

  # If using cert-manager, check certificate status
  kubectl get certificate spicedb-grpc-tls
  kubectl describe certificate spicedb-grpc-tls

  # Wait for certificate to be ready
  kubectl wait --for=condition=Ready certificate spicedb-grpc-tls --timeout=300s
  ```

- **Certificate signed by unknown authority**: Clients need the CA certificate:

  ```bash
  # Extract CA certificate
  kubectl get secret spicedb-ca-key-pair -o jsonpath='{.data.ca\.crt}' | \
    base64 -d > ca.crt

  # Distribute ca.crt to all clients
  # Clients should use this CA when connecting
  ```

- **Certificate expired**: Renew certificate or enable cert-manager auto-renewal:

  ```bash
  # Check certificate expiration
  kubectl get certificate -o custom-columns=\
  NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter

  # Force renewal with cert-manager
  kubectl delete secret spicedb-grpc-tls
  # cert-manager will automatically recreate it

  # Or manually create new certificate
  ```

- **Certificate hostname mismatch**: Ensure DNS names in certificate match connection hostname:

  ```bash
  # Check DNS names in certificate
  kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.tls\.crt}' | \
    base64 -d | openssl x509 -text -noout | grep -A 2 "Subject Alternative Name"

  # Should include the hostname you're using to connect
  ```

### mTLS Configuration Issues

**Symptoms:**

```
dispatch: connection refused
dispatch: certificate verification failed
remote error: tls: bad certificate
```

**Diagnosis:**

```bash
# Check if all pods have dispatch certificates
kubectl exec -it spicedb-0 -- ls -la /etc/spicedb/tls/dispatch/

# Verify dispatch secret includes all required files
kubectl get secret spicedb-dispatch-tls -o yaml

# Check for ca.crt, tls.crt, tls.key
kubectl get secret spicedb-dispatch-tls -o jsonpath='{.data.ca\.crt}'
kubectl get secret spicedb-dispatch-tls -o jsonpath='{.data.tls\.crt}'
kubectl get secret spicedb-dispatch-tls -o jsonpath='{.data.tls\.key}'

# View dispatch TLS configuration in environment
kubectl exec spicedb-0 -- env | grep DISPATCH.*TLS
```

**Solutions:**

- **Missing CA certificate**: Ensure dispatch secret includes `ca.crt`:

  ```bash
  # Recreate secret with CA certificate
  kubectl create secret generic spicedb-dispatch-tls \
    --from-file=tls.crt=dispatch.crt \
    --from-file=tls.key=dispatch.key \
    --from-file=ca.crt=ca.crt \
    --dry-run=client -o yaml | kubectl apply -f -
  ```

- **Different CAs**: All pods must use certificates from the same CA:

  ```bash
  # Verify all pods use same CA
  for pod in $(kubectl get pods -l app.kubernetes.io/name=spicedb -o name); do
    echo "Checking $pod"
    kubectl exec $pod -- cat /etc/spicedb/tls/dispatch/ca.crt | openssl x509 -noout -subject
  done
  # All should show same subject
  ```

- **Certificate permissions**: Ensure files have correct permissions:

  ```bash
  kubectl exec spicedb-0 -- ls -la /etc/spicedb/tls/dispatch/
  # Files should be readable by the spicedb user (UID 1000)
  ```

### CockroachDB SSL Errors

**Symptoms:**

```
pq: SSL is not enabled on the server
x509: certificate is not valid for requested name
connection requires authentication
```

**Diagnosis:**

```bash
# Check SSL mode configuration
helm get values spicedb | grep -A 10 datastore

# Verify SSL certificate paths
kubectl exec spicedb-0 -- env | grep SSL

# Check datastore TLS files exist
kubectl exec spicedb-0 -- ls -la /etc/spicedb/tls/datastore/

# Test CockroachDB connection
kubectl run -it --rm debug --image=cockroachdb/cockroach:latest --restart=Never -- \
  sql --url "postgresql://spicedb:password@cockroachdb:26257/spicedb?sslmode=verify-full&sslcert=/certs/client.spicedb.crt&sslkey=/certs/client.spicedb.key&sslrootcert=/certs/ca.crt"
```

**Solutions:**

- **SSL not enabled error**: Set correct SSL mode:

  ```bash
  helm upgrade spicedb charts/spicedb \
    --set config.datastore.sslMode=verify-full \
    --set config.datastore.sslRootCert=/etc/spicedb/tls/datastore/ca.crt \
    --set config.datastore.sslCert=/etc/spicedb/tls/datastore/tls.crt \
    --set config.datastore.sslKey=/etc/spicedb/tls/datastore/tls.key \
    --reuse-values
  ```

- **Client certificate CN mismatch**: CockroachDB requires CN in format `client.<username>`:

  ```bash
  # Check certificate CN
  kubectl get secret spicedb-datastore-tls -o jsonpath='{.data.tls\.crt}' | \
    base64 -d | openssl x509 -noout -subject

  # Should show: subject=CN = client.spicedb
  ```

- **CA certificate mismatch**: Ensure you have CockroachDB's CA certificate:

  ```bash
  # Get CockroachDB CA certificate
  kubectl get secret cockroachdb-ca -n database -o jsonpath='{.data.ca\.crt}' | \
    base64 -d > cockroachdb-ca.crt

  # Create/update SpiceDB secret
  kubectl create secret generic spicedb-datastore-tls \
    --from-file=ca.crt=cockroachdb-ca.crt \
    --from-file=tls.crt=client.spicedb.crt \
    --from-file=tls.key=client.spicedb.key \
    --dry-run=client -o yaml | kubectl apply -f -
  ```

## Connection Issues

### Service Discovery Problems

**Symptoms:**

```
connection refused
no such host
dial tcp: lookup spicedb: no such host
```

**Diagnosis:**

```bash
# Check if service exists
kubectl get svc spicedb

# Check service endpoints
kubectl get endpoints spicedb

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup spicedb.default.svc.cluster.local

# Test connectivity
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  nc -zv spicedb 50051
```

**Solutions:**

- **Service doesn't exist**: Verify Helm deployment created service:

  ```bash
  helm list
  kubectl get svc

  # If missing, reinstall chart
  helm upgrade --install spicedb charts/spicedb
  ```

- **No endpoints**: Check if pods are running:

  ```bash
  kubectl get pods -l app.kubernetes.io/name=spicedb

  # If not running, check pod events
  kubectl describe pods -l app.kubernetes.io/name=spicedb
  ```

- **DNS issues**: Verify CoreDNS is working:

  ```bash
  kubectl get pods -n kube-system -l k8s-app=kube-dns
  kubectl logs -n kube-system -l k8s-app=kube-dns
  ```

### Network Policy Blocking

**Symptoms:**

```
connection timeout
no route to host
connection refused (from specific namespaces)
```

**Diagnosis:**

```bash
# Check if NetworkPolicy is enabled
kubectl get networkpolicy

# Describe NetworkPolicy
kubectl describe networkpolicy spicedb

# Test from different namespaces
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  nc -zv spicedb.default 50051

kubectl run -it --rm debug --image=nicolaka/netshoot -n other-namespace --restart=Never -- \
  nc -zv spicedb.default 50051
```

**Solutions:**

- **NetworkPolicy blocking traffic**: Update NetworkPolicy to allow required traffic:

  ```bash
  # Check actual namespace labels
  kubectl get namespace ingress-nginx --show-labels

  # Update NetworkPolicy to match
  kubectl label namespace ingress-nginx name=ingress-nginx
  ```

- **Disable NetworkPolicy temporarily for testing**:

  ```bash
  helm upgrade spicedb charts/spicedb \
    --set networkPolicy.enabled=false \
    --reuse-values
  ```

- **Test from allowed namespace**:

  ```bash
  # Get allowed namespace from NetworkPolicy
  kubectl get networkpolicy spicedb -o yaml

  # Test from that namespace
  kubectl run -it --rm debug -n <allowed-namespace> \
    --image=nicolaka/netshoot --restart=Never -- \
    nc -zv spicedb.default 50051
  ```

### Port Forwarding Issues

**Symptoms:**

```
error: timed out waiting for port-forward
unable to listen on port
error forwarding port: listen tcp: address already in use
```

**Solutions:**

```bash
# Check if port is already in use
lsof -i :50051
netstat -an | grep 50051

# Kill process using the port
kill -9 <PID>

# Use different local port
kubectl port-forward svc/spicedb 50052:50051

# Use --address to bind to all interfaces (for remote access)
kubectl port-forward --address 0.0.0.0 svc/spicedb 50051:50051

# Check pod is running before port-forward
kubectl get pods -l app.kubernetes.io/name=spicedb
```

## Performance Issues

### Resource Exhaustion (OOMKilled)

**Symptoms:**

```
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

### CPU Throttling

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

### Database Connection Pool Exhaustion

**Symptoms:**

```
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

### Slow Dispatch Performance

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

## Pod Scheduling Problems

### Pods Stuck in Pending

**Symptoms:**

```
Status: Pending
0/3 nodes are available
```

**Diagnosis:**

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=spicedb

# Describe pod for details
kubectl describe pods -l app.kubernetes.io/name=spicedb

# Common reasons shown in events:
# - Insufficient CPU/memory
# - No nodes matching nodeSelector
# - Taints not tolerated
# - Anti-affinity constraints
```

**Solutions:**

- **Insufficient resources**:

  ```bash
  # Check node resources
  kubectl describe nodes

  # Reduce resource requests
  helm upgrade spicedb charts/spicedb \
    --set resources.requests.cpu=500m \
    --set resources.requests.memory=512Mi \
    --reuse-values
  ```

- **Anti-affinity constraints too strict**:

  ```bash
  # Change from required to preferred anti-affinity
  helm upgrade spicedb charts/spicedb \
    --set 'affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].weight=100' \
    --reuse-values

  # Or disable anti-affinity temporarily
  helm upgrade spicedb charts/spicedb \
    --set affinity=null \
    --reuse-values
  ```

- **NodeSelector/Taints mismatch**:

  ```bash
  # Check node labels
  kubectl get nodes --show-labels

  # Remove nodeSelector
  helm upgrade spicedb charts/spicedb \
    --set nodeSelector=null \
    --reuse-values

  # Or add tolerations
  helm upgrade spicedb charts/spicedb \
    --set 'tolerations[0].key=dedicated' \
    --set 'tolerations[0].operator=Equal' \
    --set 'tolerations[0].value=spicedb' \
    --set 'tolerations[0].effect=NoSchedule' \
    --reuse-values
  ```

### Pods Not Distributed Across Zones

**Symptoms:**

- All pods running in single availability zone
- No geographic redundancy

**Diagnosis:**

```bash
# Check pod distribution across zones
kubectl get pods -l app.kubernetes.io/name=spicedb \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone

# Check topology spread constraints
helm get values spicedb | grep -A 10 topologySpreadConstraints
```

**Solutions:**

```bash
# Add topology spread constraints
helm upgrade spicedb charts/spicedb \
  --set 'topologySpreadConstraints[0].maxSkew=1' \
  --set 'topologySpreadConstraints[0].topologyKey=topology.kubernetes.io/zone' \
  --set 'topologySpreadConstraints[0].whenUnsatisfiable=ScheduleAnyway' \
  --reuse-values

# Use DoNotSchedule for hard requirement
# --set 'topologySpreadConstraints[0].whenUnsatisfiable=DoNotSchedule'
```

## High Availability Issues

### HPA Not Scaling

**Symptoms:**

- HPA shows "unknown" for metrics
- Pods not scaling despite high CPU/memory
- `kubectl get hpa` shows `<unknown>` for TARGETS

**Diagnosis:**

```bash
# Check HPA status
kubectl get hpa spicedb
kubectl describe hpa spicedb

# Check if metrics-server is running
kubectl get apiservice v1beta1.metrics.k8s.io

# Check if metrics are available
kubectl top pods -l app.kubernetes.io/name=spicedb

# Check metrics-server logs
kubectl logs -n kube-system -l k8s-app=metrics-server
```

**Solutions:**

- **Install metrics-server if missing**:

  ```bash
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

  # For clusters with self-signed certs, add --kubelet-insecure-tls
  ```

- **Verify resource requests are set** (HPA requires them):

  ```bash
  helm get values spicedb | grep -A 5 resources

  # Ensure requests are specified
  helm upgrade spicedb charts/spicedb \
    --set resources.requests.cpu=1000m \
    --set resources.requests.memory=1Gi \
    --reuse-values
  ```

- **Check HPA configuration**:

  ```bash
  # View HPA details
  kubectl get hpa spicedb -o yaml

  # Verify targetCPUUtilizationPercentage is reasonable
  helm upgrade spicedb charts/spicedb \
    --set autoscaling.targetCPUUtilizationPercentage=80 \
    --reuse-values
  ```

### PDB Blocking Drains

**Symptoms:**

```
Cannot evict pod: pod disruption budget "spicedb" violation
error when evicting pod: "spicedb-xxx"
```

**Diagnosis:**

```bash
# Check PDB status
kubectl get pdb spicedb
kubectl describe pdb spicedb

# Check current availability
kubectl get pdb spicedb -o yaml
```

**Solutions:**

- **Temporarily increase replicas**:

  ```bash
  # Increase replicas to allow more disruptions
  helm upgrade spicedb charts/spicedb \
    --set replicaCount=5 \
    --reuse-values

  # Wait for new pods to be ready
  kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=spicedb

  # Now drain should work
  kubectl drain <node-name> --ignore-daemonsets
  ```

- **Adjust PDB settings**:

  ```bash
  # Increase maxUnavailable
  helm upgrade spicedb charts/spicedb \
    --set podDisruptionBudget.maxUnavailable=2 \
    --reuse-values
  ```

- **Temporarily disable PDB for emergency maintenance**:

  ```bash
  # Delete PDB (will be recreated on next helm upgrade)
  kubectl delete pdb spicedb

  # Drain node
  kubectl drain <node-name> --ignore-daemonsets
  ```

## Diagnostic Commands

### General Health Check

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

### Configuration Verification

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

### Logging

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

### Database Connectivity

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

### Network Debugging

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

### Metrics and Performance

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

## Getting Help

If you're still experiencing issues after trying these troubleshooting steps:

1. **Check existing issues**: Search [SpiceDB GitHub issues](https://github.com/authzed/spicedb/issues)
2. **Gather diagnostics**: Collect the output from the diagnostic commands above
3. **Check logs**: Include relevant log excerpts with your issue report
4. **SpiceDB version**: Note the exact SpiceDB version you're using
5. **Environment details**: Include Kubernetes version, cloud provider, etc.
6. **Configuration**: Share relevant parts of your Helm values (redact sensitive data)

Report issues at: <https://github.com/authzed/spicedb/issues>

For questions and discussions: <https://github.com/authzed/spicedb/discussions>
