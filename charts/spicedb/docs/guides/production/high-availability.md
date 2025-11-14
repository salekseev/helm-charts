# High Availability Configuration

This guide covers high availability features and configuration for production SpiceDB deployments.

**Navigation:** [← CockroachDB Deployment](cockroachdb-deployment.md) | [Index](index.md)

## Table of Contents

- [Overview](#overview)
- [Multiple Replicas](#multiple-replicas)
- [Dispatch Cluster](#dispatch-cluster)
- [Pod Disruption Budget](#pod-disruption-budget)
- [Horizontal Pod Autoscaler](#horizontal-pod-autoscaler)
- [Anti-Affinity Rules](#anti-affinity-rules)
- [Topology Spread Constraints](#topology-spread-constraints)
- [Complete HA Example](#complete-ha-example)
- [Post-Deployment Verification](#post-deployment-verification)

## Overview

SpiceDB achieves high availability through a combination of:

- **Multiple replicas**: Running multiple SpiceDB pods for redundancy
- **External datastore**: Consistency guaranteed by PostgreSQL or CockroachDB
- **Dispatch cluster**: Distributed request processing across pods
- **Pod disruption budgets**: Protection during voluntary disruptions
- **Autoscaling**: Dynamic scaling based on load
- **Anti-affinity**: Spreading pods across nodes and zones

**Important**: SpiceDB achieves consistency through the external datastore (PostgreSQL, CockroachDB, etc.), not through internal consensus between pods. This simplifies the deployment model.

## Multiple Replicas

### Understanding Replica Count

Unlike traditional consensus-based systems, SpiceDB does not require odd numbers of replicas or quorum. The datastore handles consistency.

**Recommendation by scale:**

```yaml
# Small-medium production (default)
replicaCount: 2  # Basic HA, handles single pod failure

# Medium-large production
replicaCount: 3  # Better load distribution

# Large-scale production
replicaCount: 5  # High load distribution + rolling updates
```

**Why 2 replicas are sufficient**:

- No quorum requirement (datastore handles consistency)
- One replica can handle full load during updates
- Lower resource usage than 3+ replicas
- The chart defaults to `replicaCount: 2` for basic HA

**When to use more replicas**:

- **3+ replicas**: High traffic loads, better distribution
- **5+ replicas**: Very high traffic, multiple availability zones
- **10+ replicas**: Extreme scale, global deployments

### Configure Replica Count

```yaml
# values.yaml
replicaCount: 3
```

**During rolling updates**:

With `replicaCount: 3` and `maxUnavailable: 1`:

- Kubernetes terminates 1 old pod
- Starts 1 new pod
- Waits for new pod to be ready
- Repeats until all pods updated
- Minimum 2 pods available at all times

## Dispatch Cluster

The dispatch cluster enables distributed request processing across multiple SpiceDB pods for improved performance and scalability.

### How Dispatch Works

**Service Discovery:**

The chart uses Kubernetes native service discovery (`kubernetes://`) for dispatch cluster communication:

```yaml
dispatch:
  enabled: true  # Enabled by default with 2+ replicas
```

**Architecture**:

1. SpiceDB pods register with the Service on port 50053 (dispatch port)
2. Kubernetes resolver watches Endpoints resource to discover pod IPs
3. gRPC load balances requests using consistent hash ring
4. Pods distribute sub-requests across the cluster

**Benefits**:

- **Parallel processing**: Split complex permission checks across pods
- **Load distribution**: Balance load across all available pods
- **Fault tolerance**: Automatic failover if pods become unavailable
- **Scalability**: Linear scaling with replica count

### Automatic Configuration

The chart automatically configures dispatch when running 2+ replicas:

- **Service Discovery**: `kubernetes:///spicedb.namespace:dispatch`
- **RBAC Permissions**: ServiceAccount with `get`, `list`, `watch` on endpoints
- **Port Configuration**: Uses port name `dispatch` (50053)

**No manual configuration required** - dispatch works out of the box.

### RBAC Requirements

The chart includes required RBAC permissions for kubernetes:// service discovery:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: spicedb
  namespace: spicedb
rules:
- apiGroups: [""]
  resources: ["endpoints"]
  verbs: ["get", "list", "watch"]  # watch required for real-time updates
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: spicedb
  namespace: spicedb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: spicedb
subjects:
- kind: ServiceAccount
  name: spicedb
  namespace: spicedb
```

### TLS Configuration (Optional)

For secure dispatch communication, enable mTLS:

```yaml
tls:
  enabled: true
  dispatch:
    secretName: spicedb-dispatch-tls  # mTLS certificate
```

**Requirements for dispatch mTLS certificate**:

- Must support both `clientAuth` and `serverAuth`
- Should include wildcard DNS: `*.spicedb.namespace.svc.cluster.local`
- CA certificate must be included in secret
- All pods must share the same CA

See [TLS Certificates](tls-certificates.md) for creating dispatch certificates.

### Verify Dispatch Cluster

```bash
# Check endpoints are discovered
kubectl get endpoints spicedb -n spicedb

# Should show all pod IPs

# Verify dispatch port is listening on all pods
kubectl exec -n spicedb spicedb-0 -- netstat -tlnp | grep 50053

# Should show listener on port 50053

# Check logs for dispatch cluster formation
kubectl logs -n spicedb -l app.kubernetes.io/name=spicedb | grep -i dispatch

# Should see logs about dispatch cluster configuration
```

### References

- [Consistent Hash Load Balancing for gRPC](https://authzed.com/blog/consistent-hash-load-balancing-grpc)
- [SpiceDB Operator Dispatch Configuration](https://github.com/authzed/spicedb-operator/blob/main/pkg/config/config_test.go)

## Pod Disruption Budget

Pod Disruption Budgets (PDB) ensure availability during voluntary disruptions (node drains, updates, etc.).

### Configure PDB

```yaml
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1  # Allow 1 pod to be down during updates

  # Or use minAvailable for stricter guarantees:
  # minAvailable: 2  # Require at least 2 pods available
```

**Choosing between maxUnavailable and minAvailable**:

**maxUnavailable** (recommended):

- More flexible with scaling
- Works well with HPA
- Example: `maxUnavailable: 1` allows 1 pod down regardless of replica count

**minAvailable**:

- Strict availability guarantee
- Fixed minimum regardless of replica count
- Example: `minAvailable: 2` ensures at least 2 pods always running

### Verify PDB

```bash
# Check PDB status
kubectl get pdb -n spicedb

# Should show:
# NAME      MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
# spicedb   N/A             1                 1                     5m

# Describe for details
kubectl describe pdb spicedb -n spicedb
```

### Test PDB During Drain

```bash
# Try to drain a node with SpiceDB pod
kubectl drain <node-name> --ignore-daemonsets

# PDB will:
# 1. Allow draining if maxUnavailable not exceeded
# 2. Block draining if it would violate PDB
# 3. Wait for replacement pod to be ready before continuing
```

## Horizontal Pod Autoscaler

HPA automatically scales SpiceDB based on CPU/memory utilization.

### Enable HPA

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80
```

### Prerequisites

```bash
# Verify metrics-server is installed
kubectl get apiservice v1beta1.metrics.k8s.io

# Should show: v1beta1.metrics.k8s.io   metrics-server/metrics-server   True

# Check if metrics are available
kubectl top pods -n spicedb

# Should show CPU and memory usage for pods
```

**Install metrics-server** (if not available):

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

### Verify HPA

```bash
# Check HPA status
kubectl get hpa -n spicedb

# Should show:
# NAME      REFERENCE            TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
# spicedb   Deployment/spicedb   50%/80%   2         10        3          5m

# Describe for details
kubectl describe hpa spicedb -n spicedb

# Watch HPA scale pods
kubectl get hpa spicedb -n spicedb --watch
```

### Test HPA Scaling

```bash
# Generate load to trigger scaling
# Use ghz or similar gRPC load testing tool
ghz --insecure \
  --proto schema.proto \
  --call authzed.api.v1.PermissionsService/CheckPermission \
  --data '{"resource": {"objectType": "document", "objectId": "1"}, "permission": "read", "subject": {"object": {"objectType": "user", "objectId": "alice"}}}' \
  --duration 5m \
  --concurrency 100 \
  localhost:50051

# In another terminal, watch HPA scale up
kubectl get hpa spicedb -n spicedb --watch

# Should see REPLICAS increase as CPU/memory exceeds targets
```

## Anti-Affinity Rules

Anti-affinity distributes pods across nodes to prevent single points of failure.

### Soft Anti-Affinity (Recommended)

Preferred scheduling - tries to spread pods but allows scheduling if not possible:

```yaml
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

**Use when**:

- Cluster has fewer nodes than replicas
- Cost optimization is priority
- Can tolerate multiple pods on same node

### Hard Anti-Affinity

Required scheduling - pods will not start if can't spread across nodes:

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: app.kubernetes.io/name
          operator: In
          values:
          - spicedb
      topologyKey: kubernetes.io/hostname
```

**Use when**:

- Cluster has sufficient nodes (>= replica count)
- Maximum fault tolerance is required
- Production critical deployments

### Verify Pod Distribution

```bash
# Check pods are on different nodes
kubectl get pods -n spicedb -o wide

# Should see different NODE values for each pod

# Count pods per node
kubectl get pods -n spicedb -o wide | awk '{print $7}' | sort | uniq -c
```

## Topology Spread Constraints

Topology spread constraints distribute pods across availability zones for zone-level fault tolerance.

### Configure Topology Spread

```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app.kubernetes.io/name: spicedb
```

**Parameters**:

- **maxSkew**: Maximum difference in pod count between zones
  - `1`: Nearly equal distribution (recommended)
  - `2`: Allow some imbalance for flexibility

- **whenUnsatisfiable**: What to do if constraint can't be satisfied
  - `DoNotSchedule`: Block pod scheduling (strict)
  - `ScheduleAnyway`: Best effort only (soft)

### Verify Zone Distribution

```bash
# Check pod distribution across zones
kubectl get pods -n spicedb \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone

# Should show even distribution across zones

# Count pods per zone
kubectl get pods -n spicedb \
  -o custom-columns=ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone --no-headers | sort | uniq -c
```

## Complete HA Example

Comprehensive HA configuration combining all features:

```yaml
# production-ha-values.yaml
replicaCount: 5

image:
  repository: authzed/spicedb
  tag: "v1.39.0"

config:
  datastoreEngine: postgres
  existingSecret: spicedb-database
  logLevel: info

# Dispatch cluster (enabled by default with 2+ replicas)
dispatch:
  enabled: true

# TLS for all endpoints
tls:
  enabled: true
  grpc:
    secretName: spicedb-grpc-tls
  http:
    secretName: spicedb-http-tls
  dispatch:
    secretName: spicedb-dispatch-tls

# Resource requests and limits for predictable scheduling
resources:
  requests:
    cpu: 1000m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 2Gi

# Pod disruption budget
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1

# Horizontal pod autoscaling
autoscaling:
  enabled: true
  minReplicas: 5
  maxReplicas: 20
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80

# Anti-affinity - spread across nodes
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

# Topology spread - distribute across zones
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app.kubernetes.io/name: spicedb

# Migrations
migrations:
  enabled: true
  logLevel: info
```

## Post-Deployment Verification

After configuring HA features, verify everything works correctly.

### Verify Migrations

```bash
# Check migration job status
kubectl get jobs -n spicedb -l app.kubernetes.io/component=migration

# View migration logs
kubectl logs -n spicedb -l app.kubernetes.io/component=migration

# Should see "migrations completed successfully"
```

### Verify Pod Health

```bash
# Check all pods are running
kubectl get pods -n spicedb

# All should show READY 1/1 and STATUS Running

# Check readiness probes
kubectl get pods -n spicedb -o wide

# View pod events for any issues
kubectl describe pods -n spicedb -l app.kubernetes.io/name=spicedb
```

### Verify Service Connectivity

```bash
# Check service endpoints
kubectl get svc -n spicedb
kubectl get endpoints -n spicedb

# Endpoints should list all pod IPs

# Port-forward to test
kubectl port-forward -n spicedb svc/spicedb 50051:50051

# In another terminal, test gRPC API
grpcurl -plaintext localhost:50051 list

# Should return list of services
```

### Verify Database Connectivity

```bash
# Check logs for database connection
kubectl logs -n spicedb -l app.kubernetes.io/name=spicedb | grep -i datastore

# Should see successful connection messages like:
# - "datastore connected"
# - No connection errors
```

### Verify TLS Configuration

```bash
# Check TLS is enabled in environment variables
kubectl exec -n spicedb spicedb-0 -- env | grep TLS

# Verify certificates are mounted
kubectl exec -n spicedb spicedb-0 -- ls -la /etc/spicedb/tls/

# Should show grpc/, http/, dispatch/, datastore/ directories

# Test TLS endpoint
kubectl get secret -n spicedb spicedb-grpc-tls \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt

grpcurl -cacert ca.crt spicedb.spicedb.svc.cluster.local:50051 list
```

### Load Testing

Perform load testing to validate production readiness:

```bash
# Install ghz (gRPC load testing tool)
# brew install ghz  # macOS
# go install github.com/bojand/ghz/cmd/ghz@latest  # Using Go

# Run load test
ghz --insecure \
  --proto schema.proto \
  --call authzed.api.v1.PermissionsService/CheckPermission \
  --data '{"resource": {"objectType": "document", "objectId": "1"}, "permission": "read", "subject": {"object": {"objectType": "user", "objectId": "alice"}}}' \
  --duration 60s \
  --concurrency 50 \
  localhost:50051

# Monitor metrics during load test
kubectl port-forward -n spicedb svc/spicedb 9090:9090
# Visit http://localhost:9090/metrics
```

### Monitoring Setup

Verify Prometheus is scraping metrics:

```bash
# Check metrics endpoint is accessible
kubectl port-forward -n spicedb svc/spicedb 9090:9090
curl http://localhost:9090/metrics | grep spicedb_

# If using ServiceMonitor, check it was created
kubectl get servicemonitor -n spicedb

# Verify Prometheus is scraping
# Check Prometheus UI targets page
```

### Disaster Recovery Test

Test backup and restore procedures:

```bash
# PostgreSQL backup
pg_dump -h postgres-host -U spicedb -d spicedb > spicedb-backup.sql

# Verify backup file
ls -lh spicedb-backup.sql

# CockroachDB backup (to cloud storage)
kubectl exec -it cockroachdb-0 -n database -- \
  ./cockroach sql --certs-dir=/cockroach/cockroach-certs \
  --execute="BACKUP DATABASE spicedb TO 's3://backups/spicedb?AWS_ACCESS_KEY_ID=xxx&AWS_SECRET_ACCESS_KEY=xxx';"

# Test restore on separate environment
# (Don't test on production!)
```

## Next Steps

After configuring high availability:

1. **Set Up Monitoring**: Configure Prometheus and Grafana dashboards
2. **Configure Alerts**: Set up alerting for critical metrics
3. **Automate Backups**: Schedule regular database backups
4. **Create Runbooks**: Document operational procedures
5. **Plan DR**: Test and document disaster recovery procedures
6. **Security Review**: Conduct security review and penetration testing

## Additional Resources

- [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) - Common issues and solutions
- [UPGRADE_GUIDE.md](../UPGRADE_GUIDE.md) - Upgrade procedures
- [SECURITY.md](../SECURITY.md) - Security best practices

**Navigation:** [← CockroachDB Deployment](cockroachdb-deployment.md) | [Index](index.md)
