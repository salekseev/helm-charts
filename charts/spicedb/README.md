# SpiceDB Helm Chart

[![Helm Chart CI](https://github.com/salekseev/helm-charts/actions/workflows/ci.yaml/badge.svg)](https://github.com/salekseev/helm-charts/actions/workflows/ci.yaml)

A Helm chart for deploying [SpiceDB](https://github.com/authzed/spicedb) - an open source, Zanzibar-inspired permissions database.

## Status

This chart is currently under active development. See the project roadmap in `.taskmaster/tasks/` for planned features.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.14.0+

## Installation

```bash
# Add the helm repository (once published)
# helm repo add spicedb https://example.com/charts

# Install the chart
helm install my-spicedb charts/spicedb
```

## Quick Start (Memory Mode)

For development and testing, you can deploy SpiceDB with in-memory datastore:

```bash
helm install spicedb charts/spicedb \
  --set config.datastoreEngine=memory
```

## Configuration

See [values.yaml](values.yaml) for all configuration options.

### Key Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of SpiceDB replicas | `1` |
| `image.repository` | SpiceDB image repository | `authzed/spicedb` |
| `image.tag` | SpiceDB image tag | `""` (uses appVersion) |
| `config.datastoreEngine` | Datastore engine: memory, postgres, cockroachdb | `memory` |
| `config.logLevel` | Log level: debug, info, warn, error | `info` |
| `service.type` | Kubernetes service type | `ClusterIP` |

## Development

This chart follows Test-Driven Development (TDD) practices. See [CONTRIBUTING.md](../../CONTRIBUTING.md) for the development workflow.

### Running Tests

```bash
# Lint the chart
helm lint . --strict

# Run unit tests
helm unittest .

# Validate security policies
helm template . | conftest test -p policies/ -
```

## License

Apache 2.0 - See [LICENSE](../../LICENSE) for details.
