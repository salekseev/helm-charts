# SpiceDB Helm Chart

[![Helm Chart CI](https://github.com/salekseev/helm-charts/actions/workflows/ci.yaml/badge.svg)](https://github.com/salekseev/helm-charts/actions/workflows/ci.yaml)

Production-ready Helm chart for deploying [SpiceDB](https://authzed.com/spicedb) - an open source, Google Zanzibar-inspired permissions database for fine-grained authorization at scale.

## Quick Start

```bash
# Development (single replica, memory datastore)
helm install spicedb oci://ghcr.io/salekseev/helm-charts/spicedb \
  -f values-presets/development.yaml

# Production PostgreSQL
helm install spicedb oci://ghcr.io/salekseev/helm-charts/spicedb \
  -f values-presets/production-postgres.yaml \
  --set config.existingSecret=spicedb-config

# Production High Availability
helm install spicedb oci://ghcr.io/salekseev/helm-charts/spicedb \
  -f values-presets/production-postgres.yaml \
  -f values-presets/production-ha.yaml \
  --set config.existingSecret=spicedb-config
```

See the [Quick Start Guide](docs/quickstart.md) for detailed setup instructions.

## Features

- **Operator Parity**: Feature-complete with the SpiceDB Kubernetes operator (validated against source)
- **HA by Default**: 2 replicas with dispatch enabled (basic HA, matches operator)
- **Configuration Presets**: 4 production-ready presets (development, production-postgres, production-cockroachdb, production-ha)
- **Migration Tracking**: Automatic migration state tracking with validation hooks
- **Cloud Integration**: AWS EKS Pod Identity, GCP Workload Identity, Azure Workload Identity support
- **High Availability**: Auto-scaling, pod anti-affinity, topology spread constraints
- **Security**: Comprehensive TLS/mTLS, NetworkPolicy, RBAC, Pod Security Standards
- **Observability**: Prometheus metrics, health probes, status monitoring script

## Documentation

### Getting Started
- [Quick Start Guide](docs/quickstart.md) - Get up and running in minutes
- [Configuration Presets](docs/configuration/presets.md) - Production-ready configurations

### Configuration
- [Values Reference](values.yaml) - Complete configuration options with inline documentation
- [Preset Guide](docs/configuration/presets.md) - Detailed preset documentation and customization

### Migration
- [Operator Comparison](docs/migration/operator-comparison.md) - Feature comparison with Kubernetes operator
- [Helm to Operator Migration](docs/migration/helm-to-operator.md) - Migrate from Helm to operator
- [Operator to Helm Migration](docs/migration/operator-to-helm.md) - Migrate from operator to Helm

### Operations
- [Status Monitoring](docs/operations/status-script.md) - Check deployment health with scripts/status.sh

### Guides
- [Production Guide](docs/guides/production.md) - Production deployment best practices
- [Security Guide](docs/guides/security.md) - Security hardening and compliance
- [Troubleshooting Guide](docs/guides/troubleshooting.md) - Common issues and solutions
- [Upgrade Guide](docs/guides/upgrading.md) - Version upgrade procedures

### Development
- [Testing Guide](docs/development/testing.md) - Running unit and integration tests
- [Technical Debt](docs/development/tech-debt.md) - Known issues and improvements
- [Changelog](docs/CHANGELOG.md) - Release history and changes

## Configuration Presets

This chart includes 4 production-ready presets:

| Preset | Use Case | Replicas | Datastore | Features |
|--------|----------|----------|-----------|----------|
| `development.yaml` | Local development | 1 | Memory | Minimal resources |
| `production-postgres.yaml` | Production PostgreSQL | 2 | PostgreSQL | TLS, PDB, dispatch (matches operator defaults) |
| `production-cockroachdb.yaml` | Production CockroachDB | 2 | CockroachDB | mTLS dispatch, distributed (matches operator defaults) |
| `production-ha.yaml` | High availability add-on | 5 | Any | HPA, anti-affinity, topology spread |

See [Configuration Presets](docs/configuration/presets.md) for detailed usage.

## Minimum Requirements

- Kubernetes 1.19+
- Helm 3.8+
- For production: PostgreSQL 11+ or CockroachDB 20.2+

## Installation

### Add Helm Repository

```bash
helm repo add salekseev https://salekseev.github.io/helm-charts
helm repo update
```

### Install with Default Values

```bash
helm install spicedb salekseev/spicedb
```

### Install with Production Preset

```bash
# Create secret with credentials
kubectl create secret generic spicedb-config \
  --from-literal=preshared-key="$(openssl rand -base64 32)" \
  --from-literal=datastore-uri="postgresql://user:password@postgres:5432/spicedb"

# Install with production-postgres preset
helm install spicedb salekseev/spicedb \
  -f values-presets/production-postgres.yaml \
  --set config.existingSecret=spicedb-config
```

## Values

The chart is highly configurable through `values.yaml`. Key configuration sections:

- **Replicas & Scaling**: `replicaCount`, `autoscaling`
- **Datastore**: `config.datastoreEngine`, `config.datastoreURI`
- **Security**: `config.presharedKey`, `tls`, `networkPolicy`
- **High Availability**: `dispatch`, `podDisruptionBudget`, `affinity`, `topologySpreadConstraints`
- **Observability**: `metrics`, `logging`
- **Migrations**: `migrations.enabled`, `migrations.tracking`

See [values.yaml](values.yaml) for complete documentation with inline comments.

## Monitoring

Check deployment health using the status script:

```bash
./scripts/status.sh --namespace spicedb --release spicedb
```

See [Status Monitoring](docs/operations/status-script.md) for more details.

## Upgrading

```bash
# Update Helm repo
helm repo update

# Upgrade release
helm upgrade spicedb salekseev/spicedb \
  -f values-presets/production-postgres.yaml \
  --set config.existingSecret=spicedb-config
```

The chart includes migration hooks that automatically handle database schema updates during upgrades.

## Uninstalling

```bash
helm uninstall spicedb
```

**Note**: This does not delete the database. To fully clean up, manually delete the database or drop the schema.

## Support & Contributing

- **Documentation**: https://authzed.com/docs
- **SpiceDB GitHub**: https://github.com/authzed/spicedb
- **Issues**: https://github.com/salekseev/helm-charts/issues

## License

Apache 2.0 License. See [LICENSE](../../LICENSE) for full details.

---

**Generated with ❤️ for the SpiceDB community**
