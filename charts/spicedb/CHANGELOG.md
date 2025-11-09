# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
