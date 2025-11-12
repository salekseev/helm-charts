# SpiceDB Helm Chart Value Presets

Ready-to-use value presets for common SpiceDB deployment scenarios.

## Available Presets

| Preset | Use Case | Datastore | Replicas | Key Features |
|--------|----------|-----------|----------|--------------|
| `development.yaml` | Local dev/testing | Memory | 1 | Minimal resources, debug logging |
| `production-postgres.yaml` | Production PostgreSQL | PostgreSQL | 3 | TLS, PDB, dispatch enabled |
| `production-cockroachdb.yaml` | Production CockroachDB | CockroachDB | 3 | mTLS dispatch, distributed |
| `production-ha.yaml` | High availability add-on | Any | 5 | HPA, anti-affinity, topology spread |

## Quick Start

```bash
# Development
helm install spicedb . -f values-presets/development.yaml

# Production PostgreSQL
kubectl create secret generic spicedb-config \
  --from-literal=preshared-key="$(openssl rand -base64 32)" \
  --from-literal=datastore-uri="postgresql://user:pass@host:5432/spicedb"

helm install spicedb . \
  -f values-presets/production-postgres.yaml \
  --set config.existingSecret=spicedb-config

# Production HA (layered on PostgreSQL)
helm install spicedb . \
  -f values-presets/production-postgres.yaml \
  -f values-presets/production-ha.yaml \
  --set config.existingSecret=spicedb-config
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
