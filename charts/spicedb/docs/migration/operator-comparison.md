# SpiceDB Operator vs Helm Chart Comparison

## Executive Summary

This guide helps you choose between deploying SpiceDB using the **Helm chart** or the **SpiceDB Operator**. Both approaches are production-ready and officially supported, but they offer different trade-offs.

**Choose the Helm Chart if you:**

- Have existing Helm-based workflows and GitOps pipelines (ArgoCD, Flux)
- Need NetworkPolicy for network isolation and security
- Require Ingress configuration for external access
- Want fine-grained control over resource management
- Prefer explicit configuration and declarative infrastructure
- Cannot or do not want to install custom operators in your cluster
- Need to integrate with existing Helm-based monitoring/security tools

**Choose the SpiceDB Operator if you:**

- Want automated update management with release channels
- Prefer simplified Kubernetes-native API (CRD-based)
- Need automatic datastore migration during upgrades
- Want continuous reconciliation and self-healing
- Value built-in status reporting via Kubernetes resources
- Prefer operator-pattern management for stateful applications
- Are comfortable running operators in your cluster

## Feature Comparison Matrix

| Feature | Helm Chart | SpiceDB Operator | Notes |
|---------|-----------|------------------|-------|
| **Deployment & Management** |
| Configuration Complexity | Medium (50+ lines) | Low (10-15 lines) | Operator uses simplified CRD spec |
| Installation Method | `helm install` | `kubectl apply -f operator.yaml` then create `SpiceDBCluster` | Operator requires operator installation first |
| Update Method | `helm upgrade` | Update `SpiceDBCluster` CR or automatic via channels | Operator can auto-update within channels |
| GitOps Compatibility | Excellent (ArgoCD, Flux) | Good (requires CRD support) | Both work, Helm more common |
| Configuration Format | values.yaml | SpiceDBCluster CRD YAML | Different API surfaces |
| **High Availability** |
| Multiple Replicas | Yes (replicaCount) | Yes (spec.replicas) | Both support HA |
| PodDisruptionBudget | Yes (configurable) | Managed automatically | Operator creates PDB automatically |
| Rolling Updates | Yes (updateStrategy) | Yes (automatic) | Both support zero-downtime updates |
| HorizontalPodAutoscaler | Yes (autoscaling.enabled) | Yes (spec.autoscaling) | Both support HPA |
| Pod Anti-Affinity | Yes (affinity) | Yes (via podSpec) | Both support advanced scheduling |
| Topology Spread | Yes (topologySpreadConstraints) | Yes (via podSpec) | Both support zone distribution |
| **Datastore Support** |
| PostgreSQL | Yes | Yes | Both support |
| CockroachDB | Yes | Yes | Both support |
| MySQL | No | Yes | Operator-only |
| Cloud Spanner | No | Yes | Operator-only |
| Memory (development) | Yes | Yes | Both support |
| **Database Migrations** |
| Automated Migrations | Yes (Helm hooks) | Yes (automatic on upgrade) | Operator fully automated |
| Migration Jobs | Yes (pre-install, pre-upgrade) | Managed by operator | Helm uses Jobs, Operator internal |
| Phased Migrations | Yes (targetPhase) | Yes (automatic) | Both support zero-downtime |
| Migration Rollback | Manual | Automatic (on failure) | Operator has built-in rollback |
| Migration Cleanup | Optional (cleanup.enabled) | Automatic | Operator cleans up automatically |
| **Security** |
| TLS for gRPC | Yes (tls.grpc) | Yes (spec.tlsSecretName) | Both support |
| TLS for HTTP | Yes (tls.http) | Yes (spec.tlsSecretName) | Both support |
| TLS for Dispatch | Yes (tls.dispatch) | Yes (spec.tlsSecretName) | Both support mTLS |
| TLS for Datastore | Yes (tls.datastore) | Yes (spec.datastoreEngine.tls) | Both support |
| cert-manager Integration | Yes (annotations) | Yes (cert-manager references) | Both compatible |
| NetworkPolicy | **Yes (networkPolicy.enabled)** | **No** | Helm-only feature |
| RBAC | Yes (rbac.create) | Yes (automatic) | Both support |
| Pod Security Context | Yes (detailed control) | Yes (via podSpec) | Both follow best practices |
| Secret Management | External Secrets Operator | External Secrets Operator | Both compatible |
| **Networking** |
| Service Creation | Yes (service.type) | Yes (automatic) | Both create Services |
| Headless Service | Yes (service.headless) | Yes (automatic for StatefulSet) | Both support |
| Ingress | **Yes (ingress.enabled)** | **No** | Helm-only feature |
| Multi-host Ingress | **Yes (ingress.hosts[])** | **No** | Helm-only feature |
| Path-based Routing | **Yes** | **No** | Helm-only feature |
| **Monitoring & Observability** |
| Prometheus Metrics | Yes (monitoring.enabled) | Yes (automatic) | Both expose /metrics |
| ServiceMonitor | Yes (monitoring.serviceMonitor) | Create manually | Helm creates automatically |
| Metrics Annotations | Yes (automatic) | Yes (automatic) | Both add annotations |
| Structured Logging | Yes (logging.format) | Yes (spec.logLevel) | Both support JSON/console |
| Log Level Control | Yes (logging.level) | Yes (spec.logLevel) | Both configurable |
| **Dispatch Clustering** |
| Dispatch Mode | Yes (dispatch.enabled) | Yes (spec.dispatchCluster) | Both support |
| Cluster Name | Yes (dispatch.clusterName) | Yes (spec.clusterName) | Both support |
| Upstream CA | Yes (dispatch.upstreamCASecretName) | Yes (spec.dispatchUpstreamCASecret) | Both support |
| **Update Management** |
| Manual Version Control | Yes (image.tag) | Yes (spec.version) | Both support pinning |
| Update Channels | **No** | **Yes (spec.channel)** | Operator-only feature |
| Automatic Updates | **No** | **Yes (channel: stable)** | Operator-only feature |
| Suggested Updates | **No** | **Yes (channel: manual)** | Operator-only feature |
| Safe Upgrade Paths | Manual (UPGRADE_GUIDE.md) | Automatic (validated) | Operator prevents unsafe upgrades |
| **Status & Health** |
| Readiness Probes | Yes (automatic) | Yes (automatic) | Both configure probes |
| Liveness Probes | Yes (automatic) | Yes (automatic) | Both configure probes |
| Status Reporting | kubectl commands | **CRD .status field** | Operator has structured status |
| Health Dashboard | Via HTTP endpoint | Via HTTP endpoint + CRD status | Operator adds CRD status |
| **Resource Management** |
| Resource Limits | Yes (resources.limits) | Yes (spec.resources.limits) | Both support |
| Resource Requests | Yes (resources.requests) | Yes (spec.resources.requests) | Both support |
| Init Containers | Yes (via templates) | Yes (via podSpec) | Both support |
| Extra Volumes | Yes (extraVolumes) | Yes (spec.extraVolumes) | Both support |
| Extra Env Vars | Yes (extraEnv) | Yes (spec.extraEnv) | Both support |
| **Testing & Validation** |
| Helm Unit Tests | **Yes (90%+ coverage)** | N/A | Helm-only |
| Integration Tests | **Yes (Kind + PostgreSQL)** | Operator has own tests | Helm has dedicated tests |
| OPA Policies | **Yes (Conftest)** | N/A | Helm-only |
| CI/CD Integration | **Yes (GitHub Actions)** | Via operator testing | Helm has CI |
| **Documentation** |
| Quick Start Guide | Yes (QUICKSTART.md) | Operator docs | Both documented |
| Production Guide | Yes (PRODUCTION_GUIDE.md) | Operator docs | Helm has detailed guides |
| Security Guide | Yes (SECURITY.md) | Operator docs | Helm has comprehensive guide |
| Troubleshooting Guide | Yes (TROUBLESHOOTING.md) | Operator docs | Helm has detailed guide |
| Upgrade Guide | Yes (UPGRADE_GUIDE.md) | Automatic (via operator) | Helm requires manual process |
| Examples | Yes (examples/, values-examples/) | Operator examples | Helm has many examples |

## Helm Chart Strengths

### 1. Network Isolation with NetworkPolicy

The Helm chart provides comprehensive NetworkPolicy support for zero-trust security:

```yaml
networkPolicy:
  enabled: true
  ingressControllerNamespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: ingress-nginx
  prometheusNamespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: monitoring
  databaseEgress:
    ports:
    - protocol: TCP
      port: 5432
    to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: database
```

**Why this matters:**

- Implements defense-in-depth security
- Restricts network traffic to only necessary paths
- Required for compliance (PCI-DSS, SOC 2)
- Prevents lateral movement in case of compromise

### 2. Ingress Configuration

Multi-host, path-based Ingress routing with multiple controller support:

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
    - path: /v1
      pathType: Prefix
      servicePort: grpc
  - host: metrics.spicedb.example.com
    paths:
    - path: /metrics
      pathType: Exact
      servicePort: metrics
  tls:
  - secretName: spicedb-tls
    hosts:
    - api.spicedb.example.com
    - metrics.spicedb.example.com
```

**Why this matters:**

- Expose SpiceDB externally without manual Service configuration
- Support for multiple ingress controllers (NGINX, Contour, Traefik)
- Automated TLS with cert-manager
- Path-based routing for API versioning

### 3. Fine-Grained Resource Control

Detailed control over every aspect of the deployment:

```yaml
# Separate resource limits for main deployment and migrations
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi

migrations:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

# Detailed update strategy
updateStrategy:
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1

# Explicit PDB configuration
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1
```

**Why this matters:**

- Cost optimization through precise resource allocation
- Separate limits for migrations vs runtime
- Fine-tuned update behavior for zero-downtime
- Explicit availability guarantees

### 4. GitOps Compatibility

First-class support for GitOps workflows:

```yaml
# values.yaml is version-controlled
# ArgoCD/Flux can track changes
# Helm diff shows exact changes before apply
# values-examples/ provides tested configurations
```

**Why this matters:**

- Standard Helm tooling (helm diff, helm template)
- Native ArgoCD and Flux integration
- values.yaml is easier to review than CRDs
- Mature ecosystem of Helm tools

### 5. No Operator Installation Required

Deploy without cluster-wide CRDs or operators:

```bash
# Single command deployment
helm install spicedb charts/spicedb -f values.yaml

# No operator permissions required
# No CRD installation
# No watching custom resources
# Works in restricted environments
```

**Why this matters:**

- Reduced cluster dependencies
- No operator upgrade coordination
- Works in environments that prohibit operators
- Simpler security model (no cluster-wide RBAC)

## SpiceDB Operator Strengths

### 1. Simplified Configuration

Compare 10-line operator config vs 50-line Helm config for the same deployment:

**SpiceDB Operator:**

```yaml
apiVersion: authzed.com/v1alpha1
kind: SpiceDBCluster
metadata:
  name: spicedb
spec:
  version: "v1.35.0"
  channel: stable          # Automatic updates within channel
  replicas: 3
  secretName: spicedb-config
  datastoreEngine:
    postgres:
      connectionString:
        secretKeyRef:
          name: spicedb-db
          key: uri
```

**Helm Chart (equivalent):**

```yaml
replicaCount: 3
image:
  repository: authzed/spicedb
  tag: "v1.35.0"
config:
  datastoreEngine: postgres
  presharedKey: "secret-key"
  existingSecret: spicedb-db
service:
  type: ClusterIP
  grpcPort: 50051
  httpPort: 8443
  metricsPort: 9090
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1
updateStrategy:
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
migrations:
  enabled: true
monitoring:
  enabled: true
```

**Why this matters:**

- Less configuration to maintain
- Fewer opportunities for misconfiguration
- Operator sets production-ready defaults
- Shorter learning curve

### 2. Automatic Update Channels

Set-it-and-forget-it updates within stability channels:

```yaml
apiVersion: authzed.com/v1alpha1
kind: SpiceDBCluster
metadata:
  name: spicedb
spec:
  channel: stable  # Automatically updates to latest stable version
  # channel: manual  # Suggests updates, manual approval
```

**Update Channels:**

- `stable`: Latest stable release, automatic updates
- `v1.35.x`: Latest patch within v1.35, automatic patches
- `manual`: Operator suggests updates via status, you approve

**Why this matters:**

- Automatic security patches within channel
- No manual version tracking
- Safe upgrade paths validated by operator
- Phased rollout support

### 3. Status CRD and Health Reporting

Built-in status reporting via Kubernetes API:

```bash
kubectl get spicedbcluster spicedb -o yaml

# Output includes structured status:
# status:
#   conditions:
#   - type: Ready
#     status: "True"
#   - type: Migrated
#     status: "True"
#   version: v1.35.0
#   availableReplicas: 3
#   observedGeneration: 5
#   phase: Running
```

**Why this matters:**

- Kubernetes-native status checks
- Programmatic health monitoring
- Integration with cluster monitoring tools
- Clear migration state tracking

### 4. Dynamic Reconciliation

Operator continuously monitors and corrects drift:

```yaml
# If someone manually scales pods:
kubectl scale deployment spicedb --replicas=5

# Operator automatically reverts to spec.replicas=3
# Helm would require manual helm upgrade to reconcile
```

**Why this matters:**

- Self-healing deployments
- Prevents configuration drift
- No manual intervention for most issues
- Kubernetes-native management pattern

## Configuration Examples Side-by-Side

### Example 1: Basic Production Deployment

**SpiceDB Operator:**

```yaml
apiVersion: authzed.com/v1alpha1
kind: SpiceDBCluster
metadata:
  name: spicedb-prod
spec:
  version: "v1.35.0"
  channel: stable
  replicas: 3
  secretName: spicedb-config
  datastoreEngine:
    postgres:
      connectionString:
        secretKeyRef:
          name: postgres-uri
          key: uri
```

**Helm Chart:**

```bash
helm install spicedb-prod charts/spicedb -f - <<EOF
replicaCount: 3
image:
  tag: "v1.35.0"
config:
  datastoreEngine: postgres
  existingSecret: postgres-uri
  presharedKey: "change-me"
podDisruptionBudget:
  enabled: true
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
EOF
```

### Example 2: High Availability with TLS

**SpiceDB Operator:**

```yaml
apiVersion: authzed.com/v1alpha1
kind: SpiceDBCluster
metadata:
  name: spicedb-ha
spec:
  version: "v1.35.0"
  replicas: 5
  tlsSecretName: spicedb-tls
  dispatchCluster:
    enabled: true
    tlsSecretName: spicedb-dispatch-tls
  secretName: spicedb-config
  datastoreEngine:
    postgres:
      connectionString:
        secretKeyRef:
          name: postgres-uri
          key: uri
```

**Helm Chart:**

```yaml
replicaCount: 5
tls:
  enabled: true
  grpc:
    secretName: spicedb-grpc-tls
  http:
    secretName: spicedb-http-tls
  dispatch:
    secretName: spicedb-dispatch-tls
dispatch:
  enabled: true
config:
  datastoreEngine: postgres
  existingSecret: postgres-uri
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1
```

### Example 3: Development with Memory Datastore

**SpiceDB Operator:**

```yaml
apiVersion: authzed.com/v1alpha1
kind: SpiceDBCluster
metadata:
  name: spicedb-dev
spec:
  version: "v1.35.0"
  replicas: 1
  secretName: spicedb-config
  datastoreEngine:
    memory: {}
```

**Helm Chart:**

```yaml
replicaCount: 1
config:
  datastoreEngine: memory
  presharedKey: "dev-key"
podDisruptionBudget:
  enabled: false
resources:
  requests:
    cpu: 100m
    memory: 256Mi
```

## Feature Parity Table

### Features Exclusive to Helm Chart

| Feature | Description | Use Case |
|---------|-------------|----------|
| NetworkPolicy | Network isolation and segmentation | Security compliance, zero-trust networks |
| Ingress | External access configuration | Public API exposure, multi-tenant routing |
| ServiceMonitor | Automated Prometheus scraping | Prometheus Operator integration |
| Migration Cleanup Jobs | TTL-based job cleanup | Resource management in large clusters |
| Helm Unit Tests | Template testing with helm-unittest | CI/CD validation, template verification |
| OPA Policy Validation | Conftest security policies | Security scanning, compliance checks |
| Values Examples | Pre-configured deployment scenarios | Quick starts, reference configurations |

### Features Exclusive to Operator

| Feature | Description | Use Case |
|---------|-------------|----------|
| Update Channels | Automatic version management | Automated patching, simplified ops |
| CRD Status Reporting | Structured health in Kubernetes API | Programmatic monitoring, tooling integration |
| Automatic Rollback | Rollback on migration failure | Self-healing, reduced downtime |
| Dynamic Reconciliation | Continuous drift correction | Self-healing, consistency enforcement |
| MySQL Support | MySQL datastore backend | MySQL-based infrastructure |
| Cloud Spanner Support | Google Cloud Spanner backend | Google Cloud deployments |
| Validated Upgrade Paths | Prevents unsafe version jumps | Safety, automated validation |

### Shared Features with Different Implementations

| Feature | Helm Implementation | Operator Implementation |
|---------|---------------------|-------------------------|
| Migrations | Pre-install/pre-upgrade Jobs | Automatic during reconciliation |
| TLS Configuration | Separate secrets per endpoint | Unified secret reference |
| Resource Management | Explicit values.yaml config | Defaults with overrides |
| Monitoring | ServiceMonitor + annotations | Annotations (ServiceMonitor manual) |
| Secret Management | Multiple secret sources | Unified secret reference |
| Updates | Manual `helm upgrade` | Automatic or manual via channel |
| Health Checks | Liveness/readiness probes | Probes + CRD status |

## Decision Matrix

### Use Helm Chart If

1. **Existing Helm Workflows**
   - You have GitOps pipelines (ArgoCD, Flux) for Helm charts
   - Your team is experienced with Helm
   - You have Helm-based CI/CD pipelines
   - You use Helm for other components

2. **Network Security Requirements**
   - You need NetworkPolicy for compliance (PCI-DSS, SOC 2, HIPAA)
   - You implement zero-trust networking
   - You require namespace-level network isolation
   - You need fine-grained egress control

3. **Ingress Requirements**
   - You need external access to SpiceDB
   - You use specific ingress controllers (NGINX, Contour, Traefik)
   - You require path-based routing
   - You need multi-host configurations

4. **Operator Restrictions**
   - Your cluster doesn't allow custom operators
   - You have policies against cluster-wide CRDs
   - You prefer not to run additional operators
   - You want minimal cluster dependencies

5. **Fine-Grained Control**
   - You need separate resource limits for migrations
   - You want explicit control over every configuration option
   - You need to customize deployment templates
   - You require specific pod scheduling constraints

### Use SpiceDB Operator If

1. **Automated Operations**
   - You want automatic security patches
   - You prefer set-it-and-forget-it updates
   - You need automatic rollback on failures
   - You value self-healing systems

2. **Kubernetes-Native API**
   - Your team prefers CRD-based management
   - You use kubectl for all operations
   - You integrate with Kubernetes-native tooling
   - You want status via Kubernetes API

3. **Simplified Configuration**
   - You're new to SpiceDB
   - You want production-ready defaults
   - You prefer minimal configuration
   - You trust operator-managed settings

4. **Continuous Reconciliation**
   - You need automatic drift correction
   - You want consistent state enforcement
   - You value operator-pattern benefits
   - You have dynamic environments

5. **Advanced Datastores**
   - You use MySQL for SpiceDB
   - You use Google Cloud Spanner
   - You need operator-validated configurations
   - You want datastore-specific optimizations

### Consider Both If

You can run both deployment methods in different environments:

- **Development/Staging**: Operator for rapid iteration and automatic updates
- **Production**: Helm for explicit control and GitOps workflows

Or:

- **Production**: Operator for simplified operations
- **Testing**: Helm for integration tests and CI/CD

## Migration Between Methods

Both migration paths are supported:

- **Helm → Operator**: See [MIGRATION_HELM_TO_OPERATOR.md](./MIGRATION_HELM_TO_OPERATOR.md)
- **Operator → Helm**: See [MIGRATION_OPERATOR_TO_HELM.md](./MIGRATION_OPERATOR_TO_HELM.md)

## Common Misconceptions

### "Operators are always better than Helm"

**Reality**: Both are tools with different trade-offs. Operators excel at dynamic management and automated operations. Helm excels at explicit configuration, GitOps workflows, and ecosystem integration.

### "Helm charts can't do automatic updates"

**Reality**: Helm charts can be automatically updated via GitOps tools like ArgoCD and Renovate. The difference is that Helm updates are explicit (change values.yaml and commit) while operator updates can be automatic within channels.

### "Operators don't work with GitOps"

**Reality**: Operators work fine with GitOps. You commit SpiceDBCluster YAML to Git and ArgoCD/Flux applies it. The difference is that operators add a reconciliation loop on top of GitOps.

### "You need an operator for production deployments"

**Reality**: Many production deployments use Helm charts successfully. The choice depends on your operational model, tooling, and preferences.

## Resources

### SpiceDB Operator

- **Repository**: <https://github.com/authzed/spicedb-operator>
- **Documentation**: <https://github.com/authzed/spicedb-operator/tree/main/docs>
- **Installation**: <https://github.com/authzed/spicedb-operator/releases>

### Helm Chart

- **Repository**: <https://github.com/salekseev/helm-charts>
- **Documentation**: [README.md](./README.md), [PRODUCTION_GUIDE.md](./PRODUCTION_GUIDE.md)
- **Installation**: `helm install spicedb charts/spicedb`

### SpiceDB

- **Official Site**: <https://authzed.com/spicedb>
- **Documentation**: <https://authzed.com/docs>
- **GitHub**: <https://github.com/authzed/spicedb>

## Support

- **Helm Chart Issues**: <https://github.com/salekseev/helm-charts/issues>
- **Operator Issues**: <https://github.com/authzed/spicedb-operator/issues>
- **SpiceDB Discord**: <https://authzed.com/discord>
- **SpiceDB Discussions**: <https://github.com/authzed/spicedb/discussions>
