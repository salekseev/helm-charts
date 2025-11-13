# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.1](https://github.com/salekseev/helm-charts/compare/spicedb-2.0.0...spicedb-2.0.1) (2025-11-13)

### Bug Fixes

* **docs:** correct CI badge workflow reference in SpiceDB README ([#22](https://github.com/salekseev/helm-charts/issues/22)) ([46e2731](https://github.com/salekseev/helm-charts/commit/46e27317bdea7e24306a87c5e7d7d7411c9e03a1))

### Miscellaneous

* release 2.0.1 ([6dbccb1](https://github.com/salekseev/helm-charts/commit/6dbccb14c7d5eb4c3bb4ad19c343f60ee38b7384))

## [2.0.0](https://github.com/salekseev/helm-charts/compare/spicedb-1.1.2...spicedb-2.0.0) (2025-11-13)

**This is a major release bringing SpiceDB Helm chart to feature parity with the SpiceDB Operator while maintaining full backward compatibility.**

### BREAKING CHANGES

**None** - Despite the major version bump, this release maintains 100% backward compatibility with v1.x configurations. All breaking changes planned for v2.0.0 were reverted based on community feedback to ensure smooth upgrades.

### Added

#### Operator Compatibility Mode
- **Operator-style configuration support** (`operatorCompatibility.enabled`)
  - Enables seamless migration from SpiceDB Operator to Helm chart
  - Adds operator-compatible annotations and labels
  - Reference: [Operator Comparison Guide](migration/operator-comparison.md)
  - Reference: [Helm to Operator Migration](migration/helm-to-operator.md)
  - Reference: [Operator to Helm Migration](migration/operator-to-helm.md)

#### Production-Ready Presets
- **Four comprehensive configuration presets** in `values-presets/` directory:
  - `development.yaml` - Local development with memory datastore (1 replica, minimal resources)
  - `production-postgres.yaml` - PostgreSQL production deployment (3 replicas, HA enabled)
  - `production-cockroachdb.yaml` - CockroachDB production deployment (3 replicas, HA enabled)
  - `production-ha.yaml` - High-availability multi-zone deployment (5 replicas, topology spread)
- Usage: `helm install spicedb . -f values-presets/production-postgres.yaml`
- Reference: [Preset Configuration Guide](configuration/presets.md)

#### Strategic Merge Patch System
- **Resource customization via patches** without modifying templates
- Patch support for:
  - Deployment patches (`deployment.patches[]`)
  - Service patches (`service.patches[]`)
  - Ingress patches (`ingress.patches[]`)
- Enables advanced Kubernetes features not exposed via values.yaml
- Reference: `examples/patches-examples.yaml`

#### Self-Healing Features
- **Enhanced health check configuration**:
  - Startup probes with configurable failure thresholds (default: 30 attempts × 5s = 150s)
  - Liveness probes with gRPC protocol support (Kubernetes 1.23+)
  - Readiness probes with HTTP fallback for older clusters
  - Per-probe protocol configuration (`grpc` or `http`)
- **Graceful shutdown handling**:
  - Configurable termination grace period (default: 60s)
  - PreStop hooks to drain in-flight requests
  - SIGTERM signal handling for clean shutdowns

#### Migration Management
- **Migration status tracking via ConfigMap**:
  - Records migration history and completion status
  - Enables rollback decision support
  - Accessible via `kubectl get configmap spicedb-migration-status`
- **Migration validation hooks**:
  - Pre-upgrade validation of database connectivity
  - Schema compatibility checks before applying migrations
  - Automatic rollback on validation failures
- **Automatic cleanup of migration resources**:
  - Post-migration cleanup jobs remove completed migration Jobs
  - Configurable retention via `migrations.cleanup.enabled`

#### Auto-Secret Generation
- **Automatic secret generation** (`config.autogenerateSecret`)
  - Generates secure random preshared keys automatically
  - Eliminates manual secret management for development
  - Production deployments should use `config.existingSecret` or external secret managers

#### Cloud Workload Identity Support
- **ServiceAccount annotations for cloud IAM**:
  - AWS EKS Pod Identity integration
  - GCP Workload Identity Federation
  - Azure Workload Identity
- Reference: `examples/cloud-workload-identity.yaml`

#### Enhanced Documentation
- **Comprehensive migration guides**:
  - SpiceDB Operator vs Helm Chart comparison (672 lines)
  - Helm to Operator migration guide (1,455 lines)
  - Operator to Helm migration guide (1,395 lines)
- **Organized documentation structure** under `docs/`:
  - `docs/configuration/` - Configuration guides and presets
  - `docs/migration/` - Migration and comparison documentation
  - `docs/guides/` - Production, security, troubleshooting, upgrading guides
  - `docs/operations/` - Operational scripts and utilities
  - `docs/development/` - Testing guide (310+ tests), tech debt tracking
- **Development documentation**:
  - Comprehensive testing guide covering 310+ unit tests
  - Technical debt tracking in `docs/development/tech-debt.md`
  - Integration test documentation

### Changed

#### Enhanced Default Values
- **Improved resource defaults** aligned with operator:
  - CPU requests: 500m (was: 100m)
  - Memory requests: 1Gi (was: 256Mi)
  - CPU limits: 2000m (was: 1000m)
  - Memory limits: 4Gi (was: 1Gi)
- **Better health check configurations**:
  - Startup probe: 30 failures × 5s = 150s startup window (was: 10 × 10s = 100s)
  - Liveness probe: gRPC protocol by default (was: HTTP only)
  - Readiness probe: Enhanced with proper thresholds
- **Rolling update strategy**:
  - `maxUnavailable: 0` ensures zero-downtime upgrades (unchanged)
  - `maxSurge: 1` allows one extra pod during updates (unchanged)

#### Template Improvements
- **Operator-aligned deployment annotations** when `operatorCompatibility.enabled: true`
- **Enhanced secret validation**:
  - Mutual exclusivity checks for `autogenerateSecret` and `existingSecret`
  - Clear error messages for misconfiguration
- **Migration hook improvements**:
  - Skip migration hooks when using memory datastore (no migrations needed)
  - Conditional secret mounting based on availability
  - Better error handling and logging
- **values.schema.json validation**:
  - Extended schema for new fields
  - Validation for patch syntax
  - Type checking for operator compatibility options

#### Documentation Reorganization
- **README.md simplified**: 1031 lines → 166 lines (84% reduction)
  - Focused on quick start and essential information
  - Clear navigation to detailed documentation
  - Removed redundant examples (preserved in dedicated docs)
- **values-presets/README.md simplified**: 268 lines → 52 lines (81% reduction)
  - Brief overview with links to comprehensive guide
- **All documentation moved to `docs/` hierarchy**:
  - Following AI Developer Guide "short and simple" principles
  - Improved discoverability and organization
  - Consistent formatting across all documents

### Fixed

- **Migration hook secret references**: Prevent failures when secrets are not available
- **Migration job execution**: Skip migration jobs for memory datastore configurations
- **Migration cleanup job**: Use `/bin/sh` instead of `/bin/bash` for compatibility
- **Migration validation hook**: Use kubectl image with shell support
- **Chart linting**: Removed duplicate `operatorCompatibility` key in values.yaml
- **CI preset validation**: Explicitly disable `autogenerateSecret` when testing with `existingSecret`

### Testing

- **310+ comprehensive unit tests** covering:
  - All template files with 90%+ coverage
  - Migration hooks and cleanup (113 tests)
  - Operator-style configuration (11 tests)
  - Strategic merge patches (18 tests)
  - Health probes (8 tests)
  - High-availability features (18 tests)
  - Preset validation tests for all four presets
- **Integration test infrastructure**:
  - Kind cluster-based integration tests
  - PostgreSQL deployment testing
  - Migration persistence verification
  - Automated cleanup validation
- **OPA policy validation**:
  - Conftest policies for security compliance
  - Automated policy checks in CI

### Migration Notes

**Upgrading from v1.x:**
- No breaking changes - upgrade with `helm upgrade` using existing values.yaml
- All v1.x configurations remain fully compatible
- To adopt production-ready defaults, use presets: `helm upgrade spicedb . -f values-presets/production-postgres.yaml`
- Review [Migration Guide](migration/v1-to-v2.md) for detailed upgrade procedures

**Migrating from SpiceDB Operator:**
- Follow [Operator to Helm Migration Guide](migration/operator-to-helm.md)
- Use `operatorCompatibility.enabled: true` for seamless transition
- Configuration conversion script available at `scripts/convert-operator-to-helm.sh`

### Contributors

Special thanks to all contributors who made v2.0.0 possible through testing, feedback, and code contributions.

### See Also

- [Operator Comparison Guide](migration/operator-comparison.md) - Detailed feature comparison
- [Preset Configuration Guide](configuration/presets.md) - Production-ready configurations
- [Upgrade Guide](guides/upgrading.md) - Version compatibility and upgrade procedures
- [Production Guide](guides/production.md) - Best practices for production deployments

## [1.1.2](https://github.com/salekseev/helm-charts/compare/spicedb-1.1.1...spicedb-1.1.2) (2025-11-09)


### Bug Fixes

* resolve race condition in PostgreSQL deployment wait ([#9](https://github.com/salekseev/helm-charts/issues/9)) ([d18d6af](https://github.com/salekseev/helm-charts/commit/d18d6afe0ceab17cabdde91b49650a410cdc941f))

## [1.1.1](https://github.com/salekseev/helm-charts/compare/spicedb-1.1.0...spicedb-1.1.1) (2025-11-09)


### Bug Fixes

* configure chart-testing to skip version increment check ([#7](https://github.com/salekseev/helm-charts/issues/7)) ([43f7c89](https://github.com/salekseev/helm-charts/commit/43f7c896bfc314c47242ce6ffde4aa1fb11c3727))

## [1.1.0](https://github.com/salekseev/helm-charts/compare/spicedb-1.0.0...spicedb-1.1.0) (2025-11-09)


### Features

* add observability and dispatch cluster mode support ([864d9fa](https://github.com/salekseev/helm-charts/commit/864d9fa22d8f285415fcef51d175411420c7027b))
* complete task 10 - documentation and release automation ([4880464](https://github.com/salekseev/helm-charts/commit/48804641a760326a18fd17343e690a4058d924d4))
* establish test infrastructure and TDD foundation ([c7fc24e](https://github.com/salekseev/helm-charts/commit/c7fc24eba8fee04cf9de98752f5f24c20bc7adf3))
* implement comprehensive integration testing infrastructure (task 11) ([59d792e](https://github.com/salekseev/helm-charts/commit/59d792eab79415d8da647ddb61702d641113be96))
* implement core Kubernetes resources with memory datastore ([1da440a](https://github.com/salekseev/helm-charts/commit/1da440a02ea7217b92133c588af4d980e7cdeab2))
* implement Ingress and NetworkPolicy support (task 9) ([e819dae](https://github.com/salekseev/helm-charts/commit/e819daeec813c89b9a87cbf991efe0cb50fbade5))
* implement PostgreSQL and CockroachDB datastore support ([d22c59b](https://github.com/salekseev/helm-charts/commit/d22c59bb51356028e25b473ed960c5a74f7aa9a3))
* implement production-ready SpiceDB Helm chart (Tasks 1-6) ([c4bc21f](https://github.com/salekseev/helm-charts/commit/c4bc21fcd14b36cdd19e31cf36361890170aa167))
* parametrize SpiceDB versions and fix kubectl image in integration tests ([c420def](https://github.com/salekseev/helm-charts/commit/c420def86411067b580e0ead57754daa48cbda56))
* production-ready SpiceDB chart ([956ea0e](https://github.com/salekseev/helm-charts/commit/956ea0e10f77827e5202f4a321f3f80c68c3c702))


### Bug Fixes

* add required gRPC preshared key configuration ([a7bb113](https://github.com/salekseev/helm-charts/commit/a7bb1135b2dc2293309225e81010a5ed236708cf))
* add spicedb serve command to deployment ([da0d2c1](https://github.com/salekseev/helm-charts/commit/da0d2c1a3df4e24c411f062fe14b50e9c5a60d41))
* handle existing Kind clusters in CI environment ([ecbadc3](https://github.com/salekseev/helm-charts/commit/ecbadc323f73c148bc423eb25a6f6fcc03c2b9d4))
* resolve integration test failures ([e132a95](https://github.com/salekseev/helm-charts/commit/e132a95bdf35fe9f6b9bd3d155f6ac5b4c2da6ad))
* resolve integration test failures ([bbc5c84](https://github.com/salekseev/helm-charts/commit/bbc5c84b3fa585dad734b2b6f2a46b8bb4041fb1))
* skip migration jobs for memory datastore and update tests ([ef4c900](https://github.com/salekseev/helm-charts/commit/ef4c9006d7b13ad9b3b4923dda7945e85e4d49cd))
* update Chart.yaml maintainer to valid GitHub user ([3c0ae81](https://github.com/salekseev/helm-charts/commit/3c0ae815706a52965590c6ad9e6d0d721aa7d873))
* update migration-cleanup test expectations to match current template ([1b548b0](https://github.com/salekseev/helm-charts/commit/1b548b0e60fbdd83671526ced58191062bc128e9))
* update test-unit target to find tests in subdirectories ([2d15a25](https://github.com/salekseev/helm-charts/commit/2d15a25b196a0347ca536553cdf64780b2ce793a))
* use /bin/sh instead of /bin/bash in migration cleanup job ([4794058](https://github.com/salekseev/helm-charts/commit/4794058a1744809a7678cec783845bfebf6e9eb0))
* use Bitnami kubectl image with shell support ([ae4855f](https://github.com/salekseev/helm-charts/commit/ae4855f40bd63538fab9d2a2c2cfeeb989b06009))
* use correct version for idempotent upgrade test ([c4e09aa](https://github.com/salekseev/helm-charts/commit/c4e09aae26c08c58fd82e1dc83d21784f7cb63fa))


### Miscellaneous

* update TaskMaster with Task 11 for integration testing ([22122c8](https://github.com/salekseev/helm-charts/commit/22122c8429b653828d819a5d0c687c19cb63038f))


### Code Refactoring

* reorganize for multi-chart repository structure ([44a7220](https://github.com/salekseev/helm-charts/commit/44a72207aa4edfc568d772362d2f77ea84802408))

## [Unreleased]

## [1.0.0] - 2025-11-09

### Added
- Full SpiceDB support with multiple datastore backends (memory, PostgreSQL, CockroachDB)
- Comprehensive migration management system with Kubernetes Jobs and automatic cleanup
- TLS support for all endpoints (gRPC, HTTP, dispatch, metrics)
  - Integrated cert-manager support for automatic certificate management
  - Manual certificate configuration options
  - Per-endpoint TLS configuration (gRPC, HTTP, dispatch, metrics)
- Dispatch cluster mode for horizontal scaling and improved performance
- High availability features
  - Horizontal Pod Autoscaler (HPA) configuration
  - Pod Disruption Budget (PDB) support
  - Advanced pod affinity and anti-affinity rules
  - Topology spread constraints for multi-zone deployments
- Complete observability stack
  - Prometheus ServiceMonitor integration for metrics collection
  - Configurable logging levels and formats
  - OpenTelemetry support with OTLP endpoint configuration
- Security hardening
  - Kubernetes NetworkPolicy support for network isolation
  - RBAC configuration with ServiceAccount, Role, and RoleBinding
  - Pod and container security contexts with configurable settings
  - Secret management via Kubernetes Secrets
- External Secrets Operator integration
  - Support for external secret stores (AWS Secrets Manager, Google Secret Manager, HashiCorp Vault, etc.)
  - Automatic secret synchronization
  - Configurable refresh intervals
- Comprehensive documentation
  - Detailed README with feature overview and quick start guide
  - Production deployment guide with best practices
  - Migration guide for upgrading and datastore migrations
  - Troubleshooting guide for common issues
  - Integration guides for external systems
- Example configurations
  - Production-ready PostgreSQL setup
  - High-availability CockroachDB deployment
  - TLS with cert-manager configuration
  - External Secrets Operator integration
  - Complete values examples for various scenarios
- Extensive test coverage
  - Unit tests for all template files
  - Integration tests for deployment scenarios
  - Makefile targets for automated testing
  - CI/CD pipeline configuration

[Unreleased]: https://github.com/salekseev/helm-charts/compare/spicedb-1.0.0...HEAD
[1.0.0]: https://github.com/salekseev/helm-charts/releases/tag/spicedb-1.0.0
