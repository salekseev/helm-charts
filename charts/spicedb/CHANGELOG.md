# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
