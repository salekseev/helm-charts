# SpiceDB Helm Chart

[![Helm Chart CI](https://github.com/salekseev/helm-charts/actions/workflows/ci-unit.yaml/badge.svg)](https://github.com/salekseev/helm-charts/actions/workflows/ci-unit.yaml)

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
```

For detailed setup instructions, see the [Quick Start Guide](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Quick-Start).

## Features

- **Operator Parity**: Feature-complete with the SpiceDB Kubernetes operator (validated against source)
- **HA by Default**: 2 replicas with dispatch enabled (basic HA, matches operator)
- **Configuration Presets**: 3 production-ready presets (development, production-postgres, production-cockroachdb)
- **Migration Tracking**: Automatic migration state tracking with validation hooks
- **Cloud Integration**: AWS EKS Pod Identity, GCP Workload Identity, Azure Workload Identity support
- **High Availability**: Auto-scaling, pod anti-affinity, topology spread constraints
- **Security**: Comprehensive TLS/mTLS, NetworkPolicy, RBAC, Pod Security Standards
- **Observability**: Prometheus metrics, health probes, status monitoring script

## Documentation

**Comprehensive documentation is available on the [GitHub Wiki](https://github.com/salekseev/helm-charts/wiki):**

### Getting Started

- [SpiceDB Chart Home](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Home) - Overview and navigation
- [Quick Start Guide](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Quick-Start) - Get up and running in 5 minutes
- [Configuration Presets](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Configuration-Presets) - Production-ready configurations

### Production Deployment

- [Production Guide](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Guides-Production-Index) - Complete production deployment guide
- [Infrastructure Setup](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Guides-Production-Infrastructure) - Database and network configuration
- [TLS Certificates](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Guides-Production-TLS-Certificates) - Certificate management
- [High Availability](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Guides-Production-High-Availability) - HA configuration and scaling

### Security

- [Security Guide](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Guides-Security-Index) - Security hardening and compliance
- [TLS Configuration](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Guides-Security-TLS-Configuration) - TLS/mTLS setup
- [Authentication](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Guides-Security-Authentication) - Authentication methods
- [Network Security](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Guides-Security-Network-Security) - NetworkPolicy configuration

### Migration

- [Operator Comparison](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Migration-Operator-Comparison) - Feature comparison with Kubernetes operator
- [Operator to Helm Migration](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Migration-Operator-to-Helm-Index) - Migrate from operator to Helm
- [Helm to Operator Migration](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Migration-Helm-to-Operator-Index) - Migrate from Helm to operator

### Operations & Troubleshooting

- [Status Monitoring](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Operations-Status-Script) - Health monitoring with scripts/status.sh
- [Upgrading Guide](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Guides-Upgrading) - Version upgrade procedures
- [Troubleshooting Guide](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Guides-Troubleshooting-Index) - Common issues and solutions

### Development

- [Testing Guide](docs/development/testing.md) - Running unit and integration tests
- [Technical Debt](docs/development/tech-debt.md) - Known issues and improvements
- [Values Reference](values.yaml) - Complete configuration options with inline documentation
- [Changelog](CHANGELOG.md) - Release history and changes

## Configuration Presets

This chart includes 3 production-ready presets:

| Preset | Use Case | Replicas | Datastore | Features |
|--------|----------|----------|-----------|----------|
| `development.yaml` | Local development | 1 | Memory | Minimal resources |
| `production-postgres.yaml` | Production PostgreSQL | 2-5 (HPA) | PostgreSQL | TLS, PDB, HPA, anti-affinity, topology spread |
| `production-cockroachdb.yaml` | Production CockroachDB | 2 | CockroachDB | mTLS dispatch, distributed (matches operator defaults) |

See [Configuration Presets](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Configuration-Presets) for detailed usage and customization.

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

See [Status Monitoring](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Operations-Status-Script) for detailed usage and monitoring options.

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

- **Documentation**: <https://authzed.com/docs>
- **SpiceDB GitHub**: <https://github.com/authzed/spicedb>
- **Issues**: <https://github.com/salekseev/helm-charts/issues>

## License

Apache 2.0 License. See [LICENSE](../../LICENSE) for full details.

---

**Generated with ❤️ for the SpiceDB community**
