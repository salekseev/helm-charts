# SpiceDB Production Deployment Guide

This guide provides comprehensive instructions for deploying SpiceDB in production environments with PostgreSQL or CockroachDB.

## Overview

This production deployment guide is organized into focused sections covering all aspects of deploying and operating SpiceDB in production:

- [Infrastructure Setup](infrastructure.md) - Database provisioning, network configuration, and storage setup
- [TLS Certificates](tls-certificates.md) - Certificate generation and management with cert-manager or manual methods
- [PostgreSQL Deployment](postgresql-deployment.md) - Step-by-step PostgreSQL-based deployment
- [CockroachDB Deployment](cockroachdb-deployment.md) - Step-by-step CockroachDB-based deployment
- [High Availability](high-availability.md) - HA configuration, scaling, and verification

## Quick Start

For experienced users, here's the fast path to production deployment:

```bash
# 1. Create namespace
kubectl create namespace spicedb

# 2. Set up database (PostgreSQL or CockroachDB)
# See Infrastructure Setup guide

# 3. Create database credentials secret
kubectl create secret generic spicedb-database \
  --from-literal=datastore-uri='postgresql://user:pass@host:5432/spicedb?sslmode=require' \
  --namespace=spicedb

# 4. Install cert-manager (recommended)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# 5. Apply certificate manifests
kubectl apply -f examples/cert-manager-integration.yaml

# 6. Deploy SpiceDB
helm install spicedb charts/spicedb \
  --namespace=spicedb \
  --values=production-postgres-values.yaml \
  --wait
```

## Prerequisites

### Kubernetes Requirements

- Kubernetes 1.19+
- Helm 3.14.0+
- kubectl configured to access your cluster
- Sufficient cluster resources (see resource requirements below)

### Database Requirements

Choose one of the following databases:

**PostgreSQL:**

- PostgreSQL 13+ (14+ recommended)
- Dedicated database instance (managed service or self-hosted)
- Network connectivity from Kubernetes cluster to database
- Database credentials with appropriate permissions

**CockroachDB:**

- CockroachDB 22.1+ (23.1+ recommended)
- Multi-node cluster recommended for production
- TLS certificates (CockroachDB requires TLS in production)
- Network connectivity from Kubernetes cluster to CockroachDB

### Optional Components

**For TLS (Recommended for Production):**

- [cert-manager](https://cert-manager.io/) v1.13.0+ for automated certificate management
- OR manual TLS certificates (server certificates, CA certificates)

**For External Secrets:**

- [External Secrets Operator](https://external-secrets.io/) for secure credential management
- OR Kubernetes secrets created manually/via CI/CD

### Resource Requirements

**Minimum Production Configuration:**

- 3 nodes (for high availability)
- 6 vCPUs total (2 vCPUs per node)
- 12 GB RAM total (4 GB per node)
- 50 GB disk space for database

**Recommended Production Configuration:**

- 5+ nodes across multiple availability zones
- 15+ vCPUs total (3+ vCPUs per node)
- 30+ GB RAM total (6+ GB per node)
- 200+ GB SSD storage for database

## Deployment Paths

Choose the deployment path that matches your database choice:

### PostgreSQL Path

1. Read [Infrastructure Setup](infrastructure.md) - Database provisioning section
2. Read [TLS Certificates](tls-certificates.md) - Generate certificates for SpiceDB
3. Follow [PostgreSQL Deployment](postgresql-deployment.md) - Complete deployment steps
4. Configure [High Availability](high-availability.md) - Enable HA features

### CockroachDB Path

1. Read [Infrastructure Setup](infrastructure.md) - CockroachDB provisioning section
2. Read [TLS Certificates](tls-certificates.md) - Generate certificates (required for CockroachDB)
3. Follow [CockroachDB Deployment](cockroachdb-deployment.md) - Complete deployment steps
4. Configure [High Availability](high-availability.md) - Enable HA features

## Post-Deployment

After successful deployment:

1. **Verify Installation**: Follow verification steps in deployment guides
2. **Configure Monitoring**: Set up Prometheus and Grafana dashboards
3. **Set Up Alerts**: Configure alerting for critical metrics
4. **Configure Backup**: Automate database backups
5. **Document Runbooks**: Create operational runbooks for common scenarios
6. **Plan Disaster Recovery**: Test and document DR procedures
7. **Review Security**: Conduct security review and penetration testing

## Additional Resources

- [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) - Common issues and solutions
- [UPGRADE_GUIDE.md](../UPGRADE_GUIDE.md) - Upgrade procedures
- [SECURITY.md](../SECURITY.md) - Security best practices

## Support

For issues and questions:

- GitHub Issues: [helm-charts repository](https://github.com/salekseev/helm-charts/issues)
- SpiceDB Community: [Discord](https://authzed.com/discord)
- Documentation: [SpiceDB Docs](https://authzed.com/docs)
