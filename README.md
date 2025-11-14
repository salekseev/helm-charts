# Helm Charts Repository

Production-ready Helm charts for various applications and services.

## Available Charts

### [SpiceDB](./charts/spicedb/)

A production-grade Helm chart for [SpiceDB](https://github.com/authzed/spicedb), Google Zanzibar-inspired authorization system.

**Features:**

- Multiple datastore backends (memory, PostgreSQL, CockroachDB)
- Automated database migrations
- Comprehensive TLS support
- High availability configuration
- Observability and monitoring
- Network policies and security hardening
- Full documentation and examples

**Quick Start:**

```bash
# Install SpiceDB from OCI registry
helm install spicedb oci://ghcr.io/salekseev/helm-charts/spicedb --version 1.0.0
```

For detailed documentation, see the [SpiceDB chart README](./charts/spicedb/README.md).

## Installation

### Using OCI Registry (Recommended)

Charts are published to GitHub Container Registry as OCI artifacts:

```bash
# Install a specific version
helm install my-release oci://ghcr.io/salekseev/helm-charts/spicedb --version 1.0.0

# Pull the chart locally
helm pull oci://ghcr.io/salekseev/helm-charts/spicedb --version 1.0.0

# Show available versions
helm show chart oci://ghcr.io/salekseev/helm-charts/spicedb --version 1.0.0
```

## Chart Versions

Charts are automatically published to [GitHub Container Registry](https://github.com/salekseev?tab=packages&repo_name=helm-charts) when releases are created.

Each chart maintains its own versioning and changelog. See individual chart directories for:

- Version history and compatibility
- Breaking changes
- Upgrade guides
- Configuration documentation

## Contributing

We welcome contributions! Please see our [Contributing Guide](./CONTRIBUTING.md) for:

- Development setup
- Commit message format (conventional commits)
- Pull request process
- Testing requirements

## Repository Structure

```text
.
├── charts/              # Individual Helm charts
│   └── spicedb/        # SpiceDB chart
│       ├── Chart.yaml
│       ├── values.yaml
│       ├── templates/
│       ├── examples/
│       └── README.md
├── .github/            # GitHub Actions workflows
│   └── workflows/
└── README.md          # This file
```

## Automation

This repository uses automated release management:

- **Conventional Commits** for semantic versioning
- **release-please** for automatic changelog and version updates
- **Automated OCI publishing** to GitHub Container Registry
- **Comprehensive CI/CD** with testing and validation

## Support

- **Documentation**: See individual chart READMEs
- **Issues**: [GitHub Issues](https://github.com/salekseev/helm-charts/issues)
- **Discussions**: [GitHub Discussions](https://github.com/salekseev/helm-charts/discussions)

## License

Charts in this repository are licensed under the Apache License 2.0. See individual chart directories for specific license information.
