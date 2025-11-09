# SpiceDB Helm Chart

[![Helm Chart CI](https://github.com/salekseev/helm-charts/actions/workflows/ci.yaml/badge.svg)](https://github.com/salekseev/helm-charts/actions/workflows/ci.yaml)

A production-ready Helm chart for deploying [SpiceDB](https://authzed.com/spicedb) - an open source, Google Zanzibar-inspired permissions database for fine-grained authorization at scale.

## Overview

**What is SpiceDB?**

SpiceDB is a graph-based permissions database that makes it easy to build and manage authorization systems. Inspired by Google's Zanzibar paper, SpiceDB provides:

- **Fine-grained permissions**: Define complex authorization rules with relationships and hierarchies
- **Consistent at scale**: Built on proven database backends (PostgreSQL, CockroachDB) for production reliability
- **Developer-friendly**: gRPC and HTTP APIs with client libraries in multiple languages
- **Audit and compliance**: Built-in schema versioning and change tracking

**What does this Helm chart provide?**

This chart simplifies deploying SpiceDB to Kubernetes with:

- Production-ready defaults and best practices
- Multiple deployment modes (development, production, high availability)
- Comprehensive configurability via values.yaml
- Built-in observability and security features
- Support for multiple datastore backends
- Automated database migrations
- Full TLS/mTLS support

## Features

This chart implements all production features needed for running SpiceDB at scale:

### Datastore Support
- **Multiple backends**: Memory (development), PostgreSQL, CockroachDB
- **Automated migrations**: Pre-install and pre-upgrade hooks with cleanup jobs
- **Phased migrations**: Support for zero-downtime schema changes
- **Connection management**: SSL/TLS connections, custom URI support
- **External secrets**: Integration with External Secrets Operator

### Security
- **Comprehensive TLS**: Support for gRPC, HTTP, dispatch, and datastore endpoints
- **mTLS dispatch**: Mutual TLS for inter-pod communication
- **cert-manager integration**: Automated certificate management
- **NetworkPolicy**: Network isolation and segmentation
- **RBAC**: Kubernetes role-based access control
- **Security contexts**: Non-root execution, read-only filesystem, dropped capabilities
- **Pod Security Standards**: Implements restricted profile

### High Availability
- **Horizontal Pod Autoscaler**: CPU and memory-based autoscaling
- **PodDisruptionBudget**: Ensures availability during disruptions
- **Pod anti-affinity**: Distributes pods across zones/nodes
- **Topology spread constraints**: Even distribution for resilience
- **Zero-downtime updates**: Rolling update strategy with surge control
- **Dispatch cluster mode**: Distributed permission checking

### Observability
- **Prometheus integration**: ServiceMonitor for Prometheus Operator
- **Metrics endpoint**: Standard /metrics endpoint on port 9090
- **Structured logging**: JSON and console output formats
- **Configurable log levels**: Debug, info, warn, error
- **Health checks**: Liveness and readiness probes
- **Custom labels/annotations**: Pod-level metadata for tracking

### Ingress Support
- **Multiple controllers**: NGINX, Contour, Traefik
- **Multi-host configuration**: Separate hosts for different services
- **Path-based routing**: Route multiple paths to different ports
- **TLS termination**: Ingress-level and passthrough modes
- **cert-manager integration**: Automated certificate provisioning

### Testing
- **Comprehensive unit tests**: 90%+ template coverage with helm-unittest
- **Integration tests**: End-to-end validation with Kind and PostgreSQL
- **OPA policies**: Conftest security policy validation
- **CI/CD pipeline**: Automated testing on every commit

## Quick Start

Deploy SpiceDB in memory mode (suitable for development and testing):

```bash
# Install SpiceDB with default settings (memory datastore)
helm install spicedb charts/spicedb

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=spicedb --timeout=60s

# Get the preshared key for authentication
export SPICEDB_TOKEN=$(kubectl get secret spicedb -o jsonpath='{.data.preshared-key}' | base64 -d)

# Port-forward to access SpiceDB
kubectl port-forward svc/spicedb 50051:50051 &

# Test the connection (requires zed CLI: https://github.com/authzed/zed)
zed context set local localhost:50051 "$SPICEDB_TOKEN" --insecure
zed schema read
```

See [QUICKSTART.md](./QUICKSTART.md) for a complete 5-minute guide.

## Installation

### Prerequisites

- Kubernetes 1.19+ (for networking.k8s.io/v1 Ingress API)
- Helm 3.12+
- kubectl configured to access your cluster

### Optional Prerequisites

- **Prometheus Operator**: For ServiceMonitor support (monitoring.serviceMonitor.enabled)
- **cert-manager**: For automated TLS certificate management
- **External Secrets Operator**: For external secret management
- **NetworkPolicy-enabled CNI**: Calico, Cilium, Weave, etc. (for networkPolicy.enabled)

### Install Chart

**Basic installation with memory datastore:**

```bash
helm install spicedb charts/spicedb
```

**Production installation with PostgreSQL:**

```bash
helm install spicedb charts/spicedb \
  --set config.datastoreEngine=postgres \
  --set config.datastore.hostname=postgres.database.svc.cluster.local \
  --set config.datastore.username=spicedb \
  --set config.datastore.password=changeme \
  --set config.datastore.database=spicedb \
  --set config.datastore.sslMode=require \
  --set replicaCount=3
```

**Production installation with CockroachDB:**

```bash
helm install spicedb charts/spicedb \
  --set config.datastoreEngine=cockroachdb \
  --set config.datastore.hostname=cockroachdb-public.database.svc.cluster.local \
  --set config.datastore.port=26257 \
  --set config.datastore.username=spicedb \
  --set config.datastore.password=changeme \
  --set config.datastore.database=spicedb \
  --set config.datastore.sslMode=verify-full \
  --set dispatch.enabled=true \
  --set replicaCount=5
```

**High availability configuration:**

```bash
helm install spicedb charts/spicedb -f examples/production-ha.yaml
```

### Verify Installation

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=spicedb

# Check migration job completion
kubectl get jobs -l app.kubernetes.io/component=migration

# View SpiceDB logs
kubectl logs -l app.kubernetes.io/name=spicedb --tail=50

# Test gRPC endpoint health
kubectl port-forward svc/spicedb 50051:50051 &
grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check
```

## Configuration Reference

### Image Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` | SpiceDB container image repository | `authzed/spicedb` |
| `image.tag` | SpiceDB image tag (overrides appVersion) | `""` (uses Chart.appVersion) |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `imagePullSecrets` | Image pull secrets for private registries | `[]` |

### Datastore Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `config.datastoreEngine` | Datastore type: `memory`, `postgres`, `cockroachdb` | `memory` |
| `config.presharedKey` | gRPC authentication preshared key | `insecure-default-key-change-in-production` |
| `config.existingSecret` | Name of existing secret with datastore credentials | `""` |
| `config.datastoreURI` | Explicit datastore connection URI (overrides generated) | `""` |
| `config.datastore.hostname` | Database hostname | `localhost` |
| `config.datastore.port` | Database port | `5432` (postgres), `26257` (cockroachdb) |
| `config.datastore.username` | Database username | `spicedb` |
| `config.datastore.password` | Database password | `""` |
| `config.datastore.database` | Database name | `spicedb` |
| `config.datastore.sslMode` | SSL mode: `disable`, `require`, `verify-full` | `disable` |

### Migration Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `migrations.enabled` | Enable automatic database migrations | `true` |
| `migrations.logLevel` | Migration log level: `debug`, `info`, `warn`, `error` | `info` |
| `migrations.targetMigration` | Target specific migration version | `""` |
| `migrations.targetPhase` | Target migration phase: `write`, `read`, `complete` | `""` |
| `migrations.resources` | Resource requests/limits for migration jobs | `{}` |
| `migrations.cleanup.enabled` | Enable automatic cleanup of completed migration jobs | `false` |

#### Database Migrations

Migrations run automatically as Helm hooks before installation and upgrades:

- **pre-install/pre-upgrade**: Migration job runs `spicedb migrate head`
- **post-install/post-upgrade**: Cleanup job removes old migration jobs (if cleanup.enabled)
- **Phased migrations**: Support zero-downtime schema changes

**View migration logs:**

```bash
kubectl logs -l app.kubernetes.io/component=migration --tail=100
```

**Check migration job status:**

```bash
kubectl get jobs -l app.kubernetes.io/component=migration
```

**Manual migration (if migrations.enabled=false):**

```bash
kubectl run spicedb-migrate --rm -it --restart=Never \
  --image=authzed/spicedb:v1.39.0 \
  --env="SPICEDB_DATASTORE_ENGINE=postgres" \
  --env="SPICEDB_DATASTORE_CONN_URI=postgresql://user:pass@host:5432/spicedb" \
  -- spicedb migrate head
```

**Phased migration workflow:**

Zero-downtime migrations using phases:

```bash
# 1. Phase: write - Make schema changes, old code still works
helm upgrade spicedb charts/spicedb \
  --set migrations.targetPhase=write \
  --reuse-values

# Wait for migration to complete
kubectl wait --for=condition=complete job -l app.kubernetes.io/component=migration --timeout=5m

# 2. Deploy new application version that can read new schema
kubectl rollout status deployment/spicedb

# 3. Phase: read - New code reads new schema, old code deprecated
helm upgrade spicedb charts/spicedb \
  --set migrations.targetPhase=read \
  --reuse-values

kubectl wait --for=condition=complete job -l app.kubernetes.io/component=migration --timeout=5m

# 4. Phase: complete - Migration fully complete, old code support removed
helm upgrade spicedb charts/spicedb \
  --set migrations.targetPhase=complete \
  --reuse-values
```

**Common migration issues:**

| Issue | Diagnosis | Resolution |
|-------|-----------|------------|
| Migration timeout | `kubectl describe job -l app.kubernetes.io/component=migration` | Increase `activeDeadlineSeconds` via `migrations.resources` |
| Connection failure | `kubectl logs -l app.kubernetes.io/component=migration` | Verify datastore URI, check network connectivity, verify credentials |
| Job stuck | `kubectl get jobs` shows job not completing | Delete job: `kubectl delete job -l app.kubernetes.io/component=migration` and retry upgrade |

### TLS Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `tls.enabled` | Master switch for TLS features | `false` |
| `tls.grpc.secretName` | Secret containing gRPC TLS certificates | `""` |
| `tls.grpc.certPath` | Path to gRPC server certificate | `/etc/spicedb/tls/grpc/tls.crt` |
| `tls.grpc.keyPath` | Path to gRPC server private key | `/etc/spicedb/tls/grpc/tls.key` |
| `tls.grpc.caPath` | Path to gRPC CA certificate | `/etc/spicedb/tls/grpc/ca.crt` |
| `tls.http.secretName` | Secret containing HTTP TLS certificates | `""` |
| `tls.http.certPath` | Path to HTTP server certificate | `/etc/spicedb/tls/http/tls.crt` |
| `tls.http.keyPath` | Path to HTTP server private key | `/etc/spicedb/tls/http/tls.key` |
| `tls.dispatch.secretName` | Secret containing dispatch mTLS certificates | `""` |
| `tls.dispatch.certPath` | Path to dispatch certificate | `/etc/spicedb/tls/dispatch/tls.crt` |
| `tls.dispatch.keyPath` | Path to dispatch private key | `/etc/spicedb/tls/dispatch/tls.key` |
| `tls.dispatch.caPath` | Path to dispatch CA certificate | `/etc/spicedb/tls/dispatch/ca.crt` |
| `tls.datastore.secretName` | Secret containing datastore client TLS certificates | `""` |
| `tls.datastore.caPath` | Path to datastore CA certificate | `/etc/spicedb/tls/datastore/ca.crt` |

**Example with cert-manager:**

See [examples/cert-manager-integration.yaml](./examples/cert-manager-integration.yaml) for complete configuration.

### Dispatch Cluster Mode

| Parameter | Description | Default |
|-----------|-------------|---------|
| `dispatch.enabled` | Enable dispatch cluster mode | `false` |
| `dispatch.upstreamCASecretName` | Secret containing upstream CA certificate | `""` |
| `dispatch.upstreamCAPath` | Path to upstream CA certificate | `/etc/dispatch-ca/ca.crt` |
| `dispatch.clusterName` | Cluster name for logging/metrics | `""` |

Dispatch cluster mode enables distributed permission checking across SpiceDB pods. When enabled:

- Pods communicate via Kubernetes DNS service discovery
- Dispatch port 50053 is used for inter-pod gRPC communication
- Combine with `tls.dispatch` for mTLS encryption
- Recommended: `replicaCount >= 2` for distributed workloads

### Observability Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `monitoring.enabled` | Enable Prometheus metrics scraping annotations | `true` |
| `monitoring.serviceMonitor.enabled` | Create Prometheus Operator ServiceMonitor | `false` |
| `monitoring.serviceMonitor.interval` | Metrics scrape interval | `30s` |
| `monitoring.serviceMonitor.scrapeTimeout` | Metrics scrape timeout | `10s` |
| `monitoring.serviceMonitor.labels` | ServiceMonitor metadata labels | `{}` |
| `monitoring.serviceMonitor.additionalLabels` | ServiceMonitor selector labels for Prometheus | `{}` |
| `logging.level` | Log level: `debug`, `info`, `warn`, `error` | `info` |
| `logging.format` | Log format: `json`, `console` | `json` |

#### Prometheus Metrics Integration

**Method 1: Pod Annotations (monitoring.enabled)**

When `monitoring.enabled=true`, pods are annotated for Prometheus scraping:

```yaml
prometheus.io/scrape: 'true'
prometheus.io/port: '9090'
prometheus.io/path: '/metrics'
```

Prometheus discovers these pods automatically if configured for pod annotation discovery.

**Method 2: ServiceMonitor (monitoring.serviceMonitor.enabled)**

Requires [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator):

```yaml
monitoring:
  serviceMonitor:
    enabled: true
    interval: 30s
    additionalLabels:
      prometheus: kube-prometheus  # Must match your Prometheus serviceMonitorSelector
```

#### Key SpiceDB Metrics

Monitor these metrics for production deployments:

| Metric | Description | Type |
|--------|-------------|------|
| `spicedb_check_duration_seconds` | Time to evaluate permission checks | Histogram |
| `spicedb_datastore_queries_total` | Total datastore queries | Counter |
| `spicedb_dispatch_requests_total` | Total dispatch cluster requests | Counter |
| `spicedb_grpc_server_handled_total` | Total gRPC requests by method | Counter |
| `go_memstats_alloc_bytes` | Memory allocated by SpiceDB | Gauge |
| `process_cpu_seconds_total` | CPU time consumed | Counter |

**Example PromQL queries:**

```promql
# 95th percentile permission check latency
histogram_quantile(0.95, rate(spicedb_check_duration_seconds_bucket[5m]))

# Error rate
rate(spicedb_grpc_server_handled_total{grpc_code!="OK"}[5m])

# Datastore query rate
rate(spicedb_datastore_queries_total[5m])
```

#### Grafana Dashboard

Example dashboard panels:

1. **Permission Check Latency**: Histogram of `spicedb_check_duration_seconds`
2. **Request Rate**: `rate(spicedb_grpc_server_handled_total[5m])`
3. **Error Rate**: `rate(spicedb_grpc_server_handled_total{grpc_code!="OK"}[5m])`
4. **Datastore Query Rate**: `rate(spicedb_datastore_queries_total[5m])`
5. **Memory Usage**: `go_memstats_alloc_bytes`
6. **CPU Usage**: `rate(process_cpu_seconds_total[5m])`

#### Alerting Rules

Example Prometheus alerting rules:

```yaml
groups:
  - name: spicedb
    interval: 30s
    rules:
      - alert: SpiceDBHighLatency
        expr: histogram_quantile(0.95, rate(spicedb_check_duration_seconds_bucket[5m])) > 0.5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "SpiceDB permission check latency is high"
          description: "95th percentile latency is {{ $value }}s (threshold: 0.5s)"

      - alert: SpiceDBHighErrorRate
        expr: rate(spicedb_grpc_server_handled_total{grpc_code!="OK"}[5m]) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "SpiceDB error rate is elevated"
          description: "Error rate is {{ $value }} requests/sec"
```

#### Logging Configuration

**Structured JSON logging (production):**

```yaml
logging:
  level: info
  format: json
```

**Human-readable console logging (development):**

```yaml
logging:
  level: debug
  format: console
```

**View logs:**

```bash
# Real-time logs
kubectl logs -f -l app.kubernetes.io/name=spicedb

# Filter by log level (with jq)
kubectl logs -l app.kubernetes.io/name=spicedb | jq 'select(.level=="error")'
```

#### Health Endpoints

SpiceDB exposes health check endpoints:

| Endpoint | Port | Purpose |
|----------|------|---------|
| `/healthz` | 8443 (HTTP) | Liveness probe |
| `/readyz` | 8443 (HTTP) | Readiness probe |
| `grpc.health.v1.Health/Check` | 50051 (gRPC) | gRPC health check |

**Test health endpoints:**

```bash
# HTTP health check
kubectl port-forward svc/spicedb 8443:8443
curl http://localhost:8443/healthz

# gRPC health check
grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check
```

#### Troubleshooting Metrics

**ServiceMonitor not discovered:**

1. Verify Prometheus Operator is installed:
   ```bash
   kubectl get crd servicemonitors.monitoring.coreos.com
   ```

2. Check ServiceMonitor labels match Prometheus selector:
   ```bash
   kubectl get servicemonitor spicedb -o yaml
   kubectl get prometheus -o jsonpath='{.items[*].spec.serviceMonitorSelector}'
   ```

3. Verify ServiceMonitor targets are active in Prometheus UI: Status → Targets

**Metrics not scraped:**

1. Verify pod annotations (if using pod discovery):
   ```bash
   kubectl get pod -l app.kubernetes.io/name=spicedb -o jsonpath='{.items[0].metadata.annotations}'
   ```

2. Test metrics endpoint directly:
   ```bash
   kubectl port-forward svc/spicedb 9090:9090
   curl http://localhost:9090/metrics
   ```

3. Check Prometheus scrape configuration and logs

### Resources and Scaling

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of SpiceDB pods | `1` |
| `resources.requests.cpu` | CPU resource requests | `500m` |
| `resources.requests.memory` | Memory resource requests | `1Gi` |
| `resources.limits.cpu` | CPU resource limits | `2000m` |
| `resources.limits.memory` | Memory resource limits | `4Gi` |
| `autoscaling.enabled` | Enable HorizontalPodAutoscaler | `false` |
| `autoscaling.minReplicas` | Minimum number of replicas | `2` |
| `autoscaling.maxReplicas` | Maximum number of replicas | `10` |
| `autoscaling.targetCPUUtilizationPercentage` | Target CPU utilization | `80` |
| `autoscaling.targetMemoryUtilizationPercentage` | Target memory utilization | `80` |
| `podDisruptionBudget.enabled` | Enable PodDisruptionBudget | `false` (auto-enabled if replicas > 1) |
| `podDisruptionBudget.maxUnavailable` | Max unavailable pods during disruptions | `1` |
| `updateStrategy.rollingUpdate.maxUnavailable` | Max unavailable pods during updates | `0` |
| `updateStrategy.rollingUpdate.maxSurge` | Max surge pods during updates | `1` |

### Service Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.headless` | Create headless service (for StatefulSet) | `false` |
| `service.grpcPort` | gRPC service port | `50051` |
| `service.httpPort` | HTTP service port | `8443` |
| `service.metricsPort` | Metrics service port | `9090` |
| `service.dispatchPort` | Dispatch service port | `50053` |

### Ingress Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress.enabled` | Enable Ingress resource | `false` |
| `ingress.className` | IngressClass name | `""` |
| `ingress.annotations` | Ingress annotations | `{}` |
| `ingress.hosts` | Ingress hosts configuration | `[]` |
| `ingress.tls` | Ingress TLS configuration | `[]` |

**Example multi-host configuration:**

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
  hosts:
    - host: api.spicedb.example.com
      paths:
        - path: /
          pathType: Prefix
          servicePort: grpc
    - host: metrics.spicedb.example.com
      paths:
        - path: /metrics
          pathType: Exact
          servicePort: metrics
  tls:
    - secretName: spicedb-api-tls
      hosts:
        - api.spicedb.example.com
    - secretName: spicedb-metrics-tls
      hosts:
        - metrics.spicedb.example.com
```

See [examples/](./examples/) directory for controller-specific configurations.

### Security Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `networkPolicy.enabled` | Enable NetworkPolicy | `false` |
| `networkPolicy.ingressControllerNamespaceSelector` | Selector for ingress controller namespace | `{}` |
| `networkPolicy.prometheusNamespaceSelector` | Selector for Prometheus namespace | `{}` |
| `networkPolicy.databaseEgress` | Custom database egress rules | `{}` |
| `networkPolicy.ingress` | Custom ingress rules | `[]` |
| `networkPolicy.egress` | Custom egress rules | `[]` |
| `rbac.create` | Create RBAC resources | `true` |
| `serviceAccount.create` | Create ServiceAccount | `true` |
| `serviceAccount.annotations` | ServiceAccount annotations | `{}` |
| `serviceAccount.name` | ServiceAccount name | `""` (auto-generated) |
| `podSecurityContext` | Pod-level security context | See values.yaml |
| `securityContext` | Container-level security context | See values.yaml |

## Examples

The [examples/](./examples/) directory contains production-ready configurations:

### Development

- **dev-memory.yaml**: Basic development setup with memory datastore (not available yet)

### Production Datastores

- **production-postgres.yaml**: PostgreSQL backend with SSL
- **production-cockroachdb.yaml**: CockroachDB backend
- **production-cockroachdb-tls.yaml**: CockroachDB with full TLS

### High Availability

- **production-ha.yaml**: Full HA with HPA, PDB, anti-affinity, topology spread

### Security

- **postgres-external-secrets.yaml**: External Secrets Operator integration
- **cert-manager-integration.yaml**: Automated TLS certificate management

### Ingress

- **ingress-examples.yaml**: Basic ingress configurations
- **ingress-multi-host-tls.yaml**: Multiple hosts with separate TLS certificates
- **ingress-tls-passthrough.yaml**: End-to-end encryption with TLS passthrough
- **ingress-single-host-multi-path.yaml**: Path-based routing on single host
- **production-ingress-nginx.yaml**: NGINX ingress with production settings
- **ingress-contour-grpc.yaml**: Contour ingress for gRPC
- **ingress-traefik-grpc.yaml**: Traefik ingress for gRPC

### Usage

```bash
# View example
cat examples/production-ha.yaml

# Test rendering
helm template spicedb . -f examples/production-ha.yaml

# Deploy
helm install spicedb . -f examples/production-ha.yaml
```

## Upgrading

### Standard Upgrade

```bash
# Upgrade release
helm upgrade spicedb charts/spicedb --reuse-values

# Or with new values
helm upgrade spicedb charts/spicedb -f my-values.yaml
```

### Upgrade with Custom Migration

```bash
# Target specific migration
helm upgrade spicedb charts/spicedb \
  --set migrations.targetMigration=add-caveats \
  --reuse-values

# Phased migration (see Migration Configuration section)
helm upgrade spicedb charts/spicedb \
  --set migrations.targetPhase=write \
  --reuse-values
```

### Rollback

```bash
# View revision history
helm history spicedb

# Rollback to previous revision
helm rollback spicedb

# Rollback to specific revision
helm rollback spicedb 3
```

**Important**: Rolling back the Helm release does NOT automatically rollback database schema migrations. If you need to rollback schema changes, use SpiceDB's migration commands manually:

```bash
kubectl run spicedb-migrate --rm -it --restart=Never \
  --image=authzed/spicedb:v1.39.0 \
  --env="SPICEDB_DATASTORE_ENGINE=postgres" \
  --env="SPICEDB_DATASTORE_CONN_URI=..." \
  -- spicedb migrate <target-version>
```

## Troubleshooting

### Pod Fails to Start

**Symptoms**: Pod stuck in CrashLoopBackOff or Error state

**Diagnosis**:
```bash
kubectl describe pod -l app.kubernetes.io/name=spicedb
kubectl logs -l app.kubernetes.io/name=spicedb --tail=100
```

**Common causes**:
- Invalid datastore URI: Check `config.datastoreURI` or connection parameters
- Missing preshared key: Verify `config.presharedKey` is set
- Database not accessible: Verify network connectivity and credentials
- Migration failure: Check migration job logs

### Database Connection Issues

**Symptoms**: Logs show "failed to connect to datastore"

**Resolution**:
```bash
# Verify datastore URI
kubectl get secret spicedb -o jsonpath='{.data.datastore-uri}' | base64 -d

# Test database connectivity from pod
kubectl run -it --rm debug --image=postgres:16 --restart=Never -- \
  psql postgresql://user:pass@hostname:5432/database

# Check NetworkPolicy if enabled
kubectl describe networkpolicy spicedb
```

### TLS Certificate Errors

**Symptoms**: Logs show "certificate verify failed" or "x509: certificate signed by unknown authority"

**Resolution**:
```bash
# Verify TLS secret exists and contains correct keys
kubectl get secret spicedb-grpc-tls -o yaml
kubectl describe secret spicedb-grpc-tls

# Check certificate expiration
kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -dates

# For cert-manager, check Certificate status
kubectl get certificate
kubectl describe certificate spicedb-grpc-tls
```

### Ingress Not Working

**Symptoms**: Cannot access SpiceDB via ingress hostname

**Resolution**:
```bash
# Verify Ingress resource created
kubectl get ingress
kubectl describe ingress spicedb

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller

# Test service directly
kubectl port-forward svc/spicedb 50051:50051
grpcurl -plaintext localhost:50051 list

# Verify DNS resolution
nslookup spicedb.example.com
```

### High Memory Usage

**Symptoms**: Pods restarted due to OOMKilled

**Resolution**:
```bash
# Check current memory usage
kubectl top pod -l app.kubernetes.io/name=spicedb

# View memory trends
kubectl logs -l app.kubernetes.io/name=spicedb --tail=1000 | \
  grep -i "memory\|oom"

# Increase memory limits
helm upgrade spicedb charts/spicedb \
  --set resources.limits.memory=8Gi \
  --reuse-values

# Enable HPA for automatic scaling
helm upgrade spicedb charts/spicedb \
  --set autoscaling.enabled=true \
  --set autoscaling.minReplicas=3 \
  --reuse-values
```

### Migration Job Failures

See [Migration Configuration](#migration-configuration) section for detailed troubleshooting.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](../../CONTRIBUTING.md) for:

- Development setup and testing
- Submitting bug reports and feature requests
- Pull request guidelines
- Code of conduct

### Testing

This chart includes comprehensive testing:

```bash
# Run unit tests (requires helm-unittest plugin)
make test-unit

# Run integration tests (requires Kind)
make test-integration

# Run all tests
make test-all

# Lint chart
helm lint charts/spicedb

# Security policy validation (requires conftest)
make test-policy
```

## License

This Helm chart is licensed under the Apache License 2.0. See [LICENSE](../../LICENSE) for details.

SpiceDB itself is also licensed under the Apache License 2.0.

## Links

- **SpiceDB Documentation**: https://authzed.com/docs
- **SpiceDB GitHub**: https://github.com/authzed/spicedb
- **Helm Chart Repository**: https://github.com/salekseev/helm-charts
- **Issue Tracker**: https://github.com/salekseev/helm-charts/issues

## Maintainers

- **salekseev** - https://github.com/salekseev
