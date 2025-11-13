# SpiceDB Helm Chart Value Presets

Ready-to-use value presets for common SpiceDB deployment scenarios.

## Available Presets

| Preset | Use Case | Datastore | Replicas | Key Features |
|--------|----------|-----------|----------|--------------|
| `development.yaml` | Local dev/testing | Memory | 1 | Minimal resources, debug logging |
| `production-postgres.yaml` | Production PostgreSQL | PostgreSQL | 2-5 (HPA) | TLS, PDB, HPA, anti-affinity, topology spread |
| `production-cockroachdb.yaml` | Production CockroachDB | CockroachDB | 2 | mTLS dispatch, distributed |

## Quick Start

```bash
# Development
helm install spicedb . -f values-presets/development.yaml

# Production PostgreSQL (includes all HA features)
kubectl create secret generic spicedb-config \
  --from-literal=preshared-key="$(openssl rand -base64 32)" \
  --from-literal=datastore-uri="postgresql://user:pass@host:5432/spicedb"

helm install spicedb . \
  -f values-presets/production-postgres.yaml \
  --set config.existingSecret=spicedb-config

# Customize replica count for higher availability
helm install spicedb . \
  -f values-presets/production-postgres.yaml \
  --set config.existingSecret=spicedb-config \
  --set autoscaling.minReplicas=5 \
  --set autoscaling.maxReplicas=10 \
  --set podDisruptionBudget.maxUnavailable=2
```

## Documentation

For complete preset documentation, customization examples, and best practices, see:

**[Configuration Presets Guide](../docs/configuration/presets.md)**

This includes:
- Detailed configuration explanations
- Security best practices
- Customization examples
- Resource sizing recommendations
- Production deployment patterns

---

For the main chart documentation, see [README.md](../README.md).
