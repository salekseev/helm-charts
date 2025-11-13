# SpiceDB Helm Chart Preset Customization Guide

This guide provides advanced patterns for using and customizing the SpiceDB Helm chart configuration presets.

## Table of Contents

- [Understanding Presets](#understanding-presets)
- [Combining Multiple Presets](#combining-multiple-presets)
- [Overriding Specific Values](#overriding-specific-values)
- [Adding Custom Environment Variables](#adding-custom-environment-variables)
- [Adjusting Resource Limits](#adjusting-resource-limits)
- [Enabling Additional Features](#enabling-additional-features)
- [Helm Values Precedence](#helm-values-precedence)
- [Common Patterns](#common-patterns)

---

## Understanding Presets

Configuration presets are pre-configured values files that represent common deployment scenarios. Instead of manually configuring dozens of parameters, presets provide production-tested configurations that work out of the box.

**Benefits**:
- Reduced configuration complexity (50+ lines → 10-15 lines)
- Production-tested defaults
- Consistent deployments across environments
- Easy to understand and maintain
- Can be layered and customized

**Available Presets**:
- `development.yaml` - Local development with memory datastore
- `production-postgres.yaml` - Production with PostgreSQL, TLS, HPA, anti-affinity
- `production-cockroachdb.yaml` - Production with CockroachDB and dispatch

---

## Combining Multiple Presets

Presets can be layered to combine configurations. This is useful for building complex deployments from modular components.

### Example: PostgreSQL Production Deployment

```bash
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  --set config.existingSecret=spicedb-secrets
```

**What this includes**:
1. PostgreSQL datastore configuration
2. TLS enabled for gRPC and HTTP
3. HPA with 2-5 replicas (autoscaling enabled)
4. Pod anti-affinity for zone distribution
5. Topology spread constraints
6. Pod disruption budget
7. JSON logging

### Example: CockroachDB Production Deployment

```bash
helm install crdb-spicedb charts/spicedb \
  -f values-presets/production-cockroachdb.yaml \
  --set config.existingSecret=spicedb-secrets
```

**What this includes**:
1. CockroachDB datastore configuration
2. Dispatch cluster enabled with mTLS
3. TLS for gRPC and HTTP
4. Pod disruption budget
5. JSON logging

---

## Overriding Specific Values

You can override individual preset values using `--set` flags or custom values files.

### Using --set Flags

```bash
# Override replica count
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  --set replicaCount=5 \
  --set config.existingSecret=spicedb-secrets

# Override logging configuration
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  --set logging.level=debug \
  --set logging.format=console \
  --set config.existingSecret=spicedb-secrets

# Override resource limits
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  --set resources.limits.cpu=4000m \
  --set resources.limits.memory=8Gi \
  --set config.existingSecret=spicedb-secrets
```

### Using Custom Values Files

Create a custom values file with your overrides:

```yaml
# my-custom-overrides.yaml
replicaCount: 7

logging:
  level: debug
  format: console

resources:
  limits:
    cpu: 4000m
    memory: 8Gi

monitoring:
  serviceMonitor:
    enabled: true
    additionalLabels:
      prometheus: kube-prometheus
```

Apply preset + custom overrides:

```bash
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  -f my-custom-overrides.yaml \
  --set config.existingSecret=spicedb-secrets
```

**Advantages of custom values files**:
- Better for complex overrides
- Version controllable
- Reusable across deployments
- Easier to review and maintain

---

## Adding Custom Environment Variables

You can add custom environment variables to SpiceDB pods while using presets.

### Example: Add Custom Environment Variables

```yaml
# custom-env.yaml
extraEnv:
  - name: SPICEDB_DISPATCH_UPSTREAM_TIMEOUT
    value: "60s"
  - name: SPICEDB_DATASTORE_CONN_MAX_LIFETIME
    value: "30m"
  - name: CUSTOM_ENV_VAR
    value: "custom-value"

extraEnvFrom:
  - configMapRef:
      name: spicedb-config
  - secretRef:
      name: spicedb-extra-secrets
```

Apply with preset:

```bash
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  -f custom-env.yaml \
  --set config.existingSecret=spicedb-secrets
```

### Example: Environment Variables from Secrets

```yaml
# env-from-secrets.yaml
extraEnv:
  - name: CUSTOM_API_KEY
    valueFrom:
      secretKeyRef:
        name: external-api-secrets
        key: api-key
  - name: CUSTOM_ENDPOINT
    valueFrom:
      configMapKeyRef:
        name: endpoints-config
        key: primary-endpoint
```

---

## Adjusting Resource Limits

Resource requirements vary by workload. Here's how to customize resources while using presets.

### Example 1: Increase Resources for High-Load Deployments

```yaml
# high-resources.yaml
resources:
  requests:
    cpu: 2000m
    memory: 4Gi
  limits:
    cpu: 8000m
    memory: 16Gi
```

Apply with preset:

```bash
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  -f high-resources.yaml \
  --set config.existingSecret=spicedb-secrets
```

### Example 2: Reduce Resources for Cost Optimization

```yaml
# cost-optimized.yaml
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 2Gi
```

### Example 3: Adjust HPA Targets

If you need different autoscaling thresholds than the defaults in production-postgres.yaml:

```yaml
# custom-hpa.yaml
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 75
```

Apply with preset:

```bash
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  -f custom-hpa.yaml \
  --set config.existingSecret=spicedb-secrets
```

---

## Enabling Additional Features

Presets provide a foundation. You can enable additional features on top of them.

### Example 1: Add Monitoring (Prometheus ServiceMonitor)

```yaml
# monitoring.yaml
monitoring:
  serviceMonitor:
    enabled: true
    interval: 15s
    scrapeTimeout: 10s
    additionalLabels:
      prometheus: kube-prometheus
      team: platform
```

Apply with preset:

```bash
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  -f monitoring.yaml \
  --set config.existingSecret=spicedb-secrets
```

### Example 2: Add Network Policy

```yaml
# network-policy.yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              app: frontend
        - podSelector:
            matchLabels:
              app: api-gateway
      ports:
        - protocol: TCP
          port: 50051
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: database
      ports:
        - protocol: TCP
          port: 5432
```

### Example 3: Add Ingress with TLS

```yaml
# ingress-tls.yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
  hosts:
    - host: spicedb.example.com
      paths:
        - path: /
          pathType: Prefix
          servicePort: grpc
  tls:
    - secretName: spicedb-tls
      hosts:
        - spicedb.example.com
```

Apply with preset:

```bash
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  -f ingress-tls.yaml \
  --set config.existingSecret=spicedb-secrets
```

### Example 4: Add Custom Pod Affinity/Tolerations

```yaml
# custom-scheduling.yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: node-type
              operator: In
              values:
                - high-memory
                - high-cpu

tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "spicedb"
    effect: "NoSchedule"

nodeSelector:
  disktype: ssd
```

---

## Helm Values Precedence

Understanding Helm's value merge behavior is critical for customizing presets correctly.

### Precedence Order (Lowest to Highest)

1. **Chart default values** (`values.yaml` in the chart)
2. **Preset files** (applied in `-f` order, left to right)
3. **Custom values files** (applied in `-f` order, left to right)
4. **Command-line `--set` flags** (applied in order, left to right)

### Precedence Examples

```bash
# Example 1: Later -f files override earlier ones
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \  # Sets replicaCount: 2, autoscaling.minReplicas: 2
  -f my-overrides.yaml                          # Overrides to replicaCount: 7

# Final result: replicaCount = 7
```

```bash
# Example 2: --set overrides all files
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \  # Sets replicaCount: 2, autoscaling.maxReplicas: 5
  --set replicaCount=10                         # Final override

# Final result: replicaCount = 10
```

### Value Merging Behavior

**Simple values** (strings, numbers, booleans) are **replaced**:

```yaml
# preset.yaml
replicaCount: 3

# override.yaml
replicaCount: 5

# Result: replicaCount = 5 (replaced)
```

**Objects** (maps) are **merged**:

```yaml
# preset.yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi

# override.yaml
resources:
  limits:
    cpu: 2000m

# Result (merged):
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
```

**Arrays** (lists) are **replaced** (not merged):

```yaml
# preset.yaml
extraEnv:
  - name: VAR1
    value: "value1"

# override.yaml
extraEnv:
  - name: VAR2
    value: "value2"

# Result: Only VAR2 (array replaced, not merged)
```

**To preserve array values**, you must repeat them in your override file or use `--set` array syntax.

---

## Common Patterns

### Pattern 1: Progressive Preset Layering

Start simple, add features incrementally:

```bash
# Step 1: Start with production preset (includes HA features)
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  --set config.existingSecret=spicedb-secrets

# Step 2: Add monitoring and network policy
helm upgrade spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  -f monitoring.yaml \
  -f network-policy.yaml \
  --set config.existingSecret=spicedb-secrets
```

### Pattern 2: Environment-Specific Overrides

Maintain base preset + environment-specific files:

```
config/
├── base/
│   └── spicedb-base.yaml          # Shared config (ingress, monitoring, etc.)
├── staging/
│   └── staging-overrides.yaml     # Staging-specific (smaller resources)
└── production/
    └── production-overrides.yaml  # Production-specific (larger resources, more replicas)
```

Deploy to staging:

```bash
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  -f config/base/spicedb-base.yaml \
  -f config/staging/staging-overrides.yaml \
  --set config.existingSecret=spicedb-secrets-staging
```

Deploy to production:

```bash
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  -f config/base/spicedb-base.yaml \
  -f config/production/production-overrides.yaml \
  --set config.existingSecret=spicedb-secrets-production
```

### Pattern 3: Feature Flags via Values

Create modular feature files that can be enabled/disabled:

```
features/
├── monitoring.yaml       # ServiceMonitor + annotations
├── network-policy.yaml   # NetworkPolicy rules
├── ingress-tls.yaml      # Ingress with cert-manager
└── high-resources.yaml   # Increased resource limits
```

Enable features as needed:

```bash
# Minimal production
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  --set config.existingSecret=spicedb-secrets

# Production with monitoring
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  -f features/monitoring.yaml \
  --set config.existingSecret=spicedb-secrets

# Full-featured production
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  -f features/monitoring.yaml \
  -f features/network-policy.yaml \
  -f features/ingress-tls.yaml \
  --set config.existingSecret=spicedb-secrets
```

### Pattern 4: Copy and Customize

For complex customizations, copy a preset and modify it:

```bash
# Copy preset to create custom configuration
cp values-presets/production-postgres.yaml my-custom-spicedb.yaml

# Edit my-custom-spicedb.yaml with your changes
vim my-custom-spicedb.yaml

# Deploy with custom configuration
helm install spicedb charts/spicedb \
  -f my-custom-spicedb.yaml \
  --set config.existingSecret=spicedb-secrets
```

**Advantages**:
- Full control over configuration
- No need to understand value merging
- Easy to review all settings

**Disadvantages**:
- Doesn't benefit from preset updates
- More maintenance overhead

---

## Troubleshooting

### Issue: Override not taking effect

**Symptom**: Setting a value via `--set` or override file doesn't change the deployment.

**Common causes**:
1. Typo in parameter name
2. Wrong precedence order (earlier `-f` files overridden by later ones)
3. Array replacement (trying to merge arrays, but they're replaced)

**Solution**:
```bash
# Debug: Render template to see final values
helm template spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  -f my-overrides.yaml \
  --set config.existingSecret=spicedb-secrets \
  | grep -A 10 "kind: Deployment"

# Check merged values
helm install spicedb charts/spicedb \
  -f values-presets/production-postgres.yaml \
  -f my-overrides.yaml \
  --dry-run --debug
```

### Issue: Preset values conflict

**Symptom**: Deployment fails or behaves unexpectedly after combining presets.

**Solution**: Review preset files and ensure they're meant to be layered:

```bash
# View preset contents
cat values-presets/production-postgres.yaml
cat values-presets/production-cockroachdb.yaml

# All presets are now standalone with HA features included where appropriate
```

### Issue: Can't find where a value is set

**Symptom**: A value in deployment doesn't match any of your files.

**Solution**: Check the full value precedence chain:

```bash
# 1. Check chart defaults
cat charts/spicedb/values.yaml | grep -A 5 "replicaCount"

# 2. Check all preset files
grep -r "replicaCount" values-presets/

# 3. Check your override files
grep -r "replicaCount" my-overrides.yaml

# 4. Use helm get values to see final merged values
helm get values spicedb
```

---

## Additional Resources

- [Helm Values Documentation](https://helm.sh/docs/chart_template_guide/values_files/)
- [SpiceDB Documentation](https://authzed.com/docs)
- [Chart README](./README.md)
- [Production Guide](./PRODUCTION_GUIDE.md)
- [values-presets/README.md](./values-presets/README.md)

---

**Questions or Issues?**

If you encounter issues or have questions about preset customization, please [open an issue](https://github.com/salekseev/helm-charts/issues) on GitHub.
