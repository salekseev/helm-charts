# SpiceDB Helm Chart Value Presets

This directory contains ready-to-use value presets for common SpiceDB deployment scenarios. These presets provide production-tested configurations that can be used directly or as starting points for customization.

## Available Presets

### 1. Development (`development.yaml`)

**Purpose**: Local development and testing

**Features**:
- Memory datastore (no database required)
- Single replica
- Debug logging
- Minimal resource requirements
- TLS disabled for simplified setup

**Usage**:
```bash
helm install dev-spicedb . -f values-presets/development.yaml
```

**Resource Requirements**:
- CPU: 100m-500m
- Memory: 256Mi-512Mi

**Warning**: Memory datastore is not persistent. All data is lost on pod restart.

---

### 2. Production PostgreSQL (`production-postgres.yaml`)

**Purpose**: Production deployments with PostgreSQL backend

**Features**:
- PostgreSQL datastore
- 3 replicas for high availability
- Production resource limits
- TLS enabled for secure communication
- Pod Disruption Budget
- JSON logging for log aggregation

**Prerequisites**:
1. PostgreSQL instance (external or in-cluster)
2. Kubernetes secret with credentials
3. TLS certificates (optional but recommended)

**Required Secret**:
```bash
kubectl create secret generic spicedb-secrets \
  --from-literal=datastore-uri="postgresql://user:pass@host:5432/db?sslmode=require" \
  --from-literal=preshared-key="your-secure-key"
```

**Usage**:
```bash
helm install prod-spicedb . \
  -f values-presets/production-postgres.yaml \
  --set config.existingSecret=spicedb-secrets
```

**Resource Requirements**:
- CPU: 500m-2000m per pod
- Memory: 1Gi-4Gi per pod

---

### 3. Production CockroachDB (`production-cockroachdb.yaml`)

**Purpose**: Production deployments with CockroachDB and dispatch cluster

**Features**:
- CockroachDB datastore
- 3 replicas for high availability
- Dispatch cluster enabled for distributed permission checking
- Production resource limits
- TLS enabled for all endpoints (gRPC, HTTP, dispatch)
- Pod Disruption Budget
- JSON logging

**Prerequisites**:
1. CockroachDB cluster
2. Kubernetes secret with credentials
3. TLS certificates for gRPC/HTTP endpoints
4. mTLS certificates for dispatch cluster

**Required Secrets**:
```bash
# Database credentials
kubectl create secret generic spicedb-secrets \
  --from-literal=datastore-uri="postgresql://user:pass@crdb:26257/db?sslmode=verify-full" \
  --from-literal=preshared-key="your-secure-key"

# TLS certificates
kubectl create secret tls spicedb-tls \
  --cert=tls.crt --key=tls.key

kubectl create secret tls spicedb-dispatch-tls \
  --cert=dispatch-tls.crt --key=dispatch-tls.key

kubectl create secret generic spicedb-dispatch-ca \
  --from-file=ca.crt=dispatch-ca.crt
```

**Usage**:
```bash
helm install prod-spicedb . \
  -f values-presets/production-cockroachdb.yaml \
  --set config.existingSecret=spicedb-secrets \
  --set tls.grpc.secretName=spicedb-tls \
  --set tls.dispatch.secretName=spicedb-dispatch-tls \
  --set dispatch.upstreamCASecretName=spicedb-dispatch-ca
```

**Resource Requirements**:
- CPU: 500m-2000m per pod
- Memory: 1Gi-4Gi per pod

---

### 4. High Availability (`production-ha.yaml`)

**Purpose**: Maximum availability layer for production deployments

**Features**:
- 5 base replicas
- Horizontal Pod Autoscaler (5-10 replicas)
- Pod Disruption Budget allowing 2 unavailable
- Pod Anti-Affinity for zone spreading
- Topology Spread Constraints

**Prerequisites**:
1. Kubernetes cluster with multiple availability zones (recommended)
2. Metrics Server installed (required for HPA)
3. A production preset (postgres or cockroachdb)

**Usage** (layered with other presets):
```bash
# PostgreSQL HA
helm install ha-spicedb . \
  -f values-presets/production-postgres.yaml \
  -f values-presets/production-ha.yaml \
  --set config.existingSecret=spicedb-secrets

# CockroachDB HA
helm install ha-spicedb . \
  -f values-presets/production-cockroachdb.yaml \
  -f values-presets/production-ha.yaml \
  --set config.existingSecret=spicedb-secrets \
  --set tls.grpc.secretName=spicedb-tls \
  --set tls.dispatch.secretName=spicedb-dispatch-tls \
  --set dispatch.upstreamCASecretName=spicedb-dispatch-ca
```

**Resource Requirements**:
- Same as underlying production preset
- Total cluster capacity for 5-10 replicas

---

## Preset Layering

Presets can be layered to combine configurations. Later presets override values from earlier ones:

```bash
# Base + Enhancement
helm install spicedb . \
  -f values-presets/production-postgres.yaml \
  -f values-presets/production-ha.yaml \
  --set config.existingSecret=spicedb-secrets
```

**Common Combinations**:
- `production-postgres.yaml` + `production-ha.yaml` → PostgreSQL with maximum availability
- `production-cockroachdb.yaml` + `production-ha.yaml` → CockroachDB with maximum availability

---

## Customization

To customize a preset:

1. **Override specific values**:
   ```bash
   helm install spicedb . \
     -f values-presets/production-postgres.yaml \
     --set replicaCount=5 \
     --set resources.limits.memory=8Gi
   ```

2. **Create custom preset**:
   ```bash
   # Copy and modify
   cp values-presets/production-postgres.yaml my-custom.yaml
   # Edit my-custom.yaml
   helm install spicedb . -f my-custom.yaml
   ```

3. **Layer multiple files**:
   ```bash
   helm install spicedb . \
     -f values-presets/production-postgres.yaml \
     -f my-overrides.yaml
   ```

---

## Testing

All presets have been tested and validated:

```bash
# Run all preset tests
cd charts/spicedb
helm unittest -f 'tests/unit/preset_*.yaml' .

# Test individual preset
helm unittest -f tests/unit/preset_development_test.yaml .

# Validate rendering
helm template test . -f values-presets/development.yaml
```

---

## Quick Start Guide

### Development Environment
```bash
helm install dev-spicedb . -f values-presets/development.yaml
```

### Production Environment (PostgreSQL)
```bash
# 1. Create secrets
kubectl create secret generic spicedb-secrets \
  --from-literal=datastore-uri="postgresql://..." \
  --from-literal=preshared-key="..."

# 2. Install
helm install prod-spicedb . \
  -f values-presets/production-postgres.yaml \
  --set config.existingSecret=spicedb-secrets
```

### Production Environment (CockroachDB with HA)
```bash
# 1. Create all required secrets (see CockroachDB preset above)

# 2. Install with HA
helm install ha-spicedb . \
  -f values-presets/production-cockroachdb.yaml \
  -f values-presets/production-ha.yaml \
  --set config.existingSecret=spicedb-secrets \
  --set tls.grpc.secretName=spicedb-tls \
  --set tls.dispatch.secretName=spicedb-dispatch-tls \
  --set dispatch.upstreamCASecretName=spicedb-dispatch-ca
```

---

## Support

For more information:
- [SpiceDB Documentation](https://authzed.com/docs)
- [Chart README](../README.md)
- [Production Guide](../PRODUCTION_GUIDE.md)
- [Security Guide](../SECURITY.md)
