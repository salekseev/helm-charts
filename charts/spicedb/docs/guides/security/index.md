# SpiceDB Security Guide

This guide covers security features, best practices, and compliance considerations for SpiceDB deployments.

## Security Documentation Navigation

This security guide is organized into domain-specific sections:

- **[TLS Configuration](tls-configuration.md)** - Transport Layer Security setup, certificate management, and mTLS
- **[Authentication](authentication.md)** - Preshared keys, RBAC, and secret management
- **[Network Security](network-security.md)** - NetworkPolicy, service mesh integration, and firewall configuration
- **[Pod Security](pod-security.md)** - Pod Security Standards, image security, and resource limits
- **[Compliance](compliance.md)** - Regulatory compliance, audit logging, and encryption requirements

## Security Overview

SpiceDB and this Helm chart provide multiple layers of security:

### Transport Layer Security (TLS)

**Available for all endpoints:**

- gRPC API (client-to-server)
- HTTP Dashboard (client-to-server)
- Dispatch cluster (mutual TLS for pod-to-pod)
- Datastore connections (client-to-server or mutual TLS)

**Benefits:**

- Encrypts data in transit
- Prevents man-in-the-middle attacks
- Authenticates endpoints (mutual TLS)
- Required for regulatory compliance (PCI DSS, HIPAA, etc.)

### Network Isolation

**NetworkPolicy support:**

- Namespace-level isolation
- Pod-level access control
- Ingress and egress filtering
- Defense-in-depth security

**Benefits:**

- Limits attack surface
- Prevents lateral movement
- Implements zero-trust principles
- Meets compliance requirements

### Pod Security Standards

**Implements Kubernetes restricted profile:**

- Non-root containers
- Read-only root filesystem
- Dropped capabilities
- Seccomp profiles
- No privilege escalation

**Benefits:**

- Reduces container breakout risk
- Limits impact of vulnerabilities
- Meets security baselines
- Complies with CIS benchmarks

### RBAC Integration

**Kubernetes RBAC:**

- Service account with minimal permissions
- Role-based access control
- Optional pod identity (IRSA, Workload Identity)
- Secrets access control

**Benefits:**

- Least privilege principle
- Audit trail for actions
- Fine-grained access control
- Cloud IAM integration

## Pre-Production Security Checklist

### TLS Configuration

- [ ] **TLS enabled for all endpoints**
  - [ ] gRPC TLS configured
  - [ ] HTTP TLS configured
  - [ ] Dispatch mTLS configured (multi-replica deployments)
  - [ ] Database SSL/TLS configured (verify-full mode)
  - [ ] Certificate management automated (cert-manager recommended)
  - [ ] Certificate expiration monitoring configured

### Authentication and Secrets

- [ ] **Strong authentication configured**
  - [ ] Strong preshared key generated (32+ bytes random)
  - [ ] Secrets stored in external secret manager (not in values files)
  - [ ] Database credentials rotated from defaults
  - [ ] Different secrets per environment
  - [ ] Secret rotation schedule established
  - [ ] Secret access auditing enabled

### Network Security

- [ ] **Network isolation implemented**
  - [ ] NetworkPolicy enabled
  - [ ] Ingress restricted to required namespaces
  - [ ] Egress restricted to database only
  - [ ] Security groups/firewall rules configured
  - [ ] Service mesh integration (if applicable)

### Pod Security

- [ ] **Pod hardening applied**
  - [ ] Pod Security Standards enforced (restricted profile)
  - [ ] Non-root containers verified
  - [ ] Read-only root filesystem enabled
  - [ ] Resource limits configured
  - [ ] Image scanning enabled
  - [ ] Specific image tags used (not latest)

### RBAC and Access Control

- [ ] **Access controls enforced**
  - [ ] RBAC enabled
  - [ ] Service account with minimal permissions
  - [ ] Cloud IAM integration configured (if applicable)
  - [ ] Database user permissions minimized

### Monitoring and Audit

- [ ] **Observability configured**
  - [ ] Audit logging enabled
  - [ ] Metrics collection configured
  - [ ] Alerts set up for security events
  - [ ] Log aggregation configured
  - [ ] Runtime security monitoring deployed

### Compliance

- [ ] **Compliance requirements met**
  - [ ] Encryption at rest enabled (database, secrets)
  - [ ] Encryption in transit verified (all endpoints)
  - [ ] Audit requirements documented
  - [ ] Backup and disaster recovery tested
  - [ ] Compliance framework requirements mapped

### Operational Security

- [ ] **Security operations ready**
  - [ ] Vulnerability scanning enabled (containers, dependencies)
  - [ ] Update process documented
  - [ ] Incident response plan created
  - [ ] Security contacts documented
  - [ ] Security advisory subscription active

## Runtime Security Monitoring

**Monitor for:**

- Failed authentication attempts
- Unusual network traffic patterns
- Resource exhaustion attempts
- Certificate expiration
- Database connection failures
- Unauthorized access attempts

**Recommended tools:**

- Falco: Runtime security monitoring
- Prometheus + Grafana: Metrics and alerting
- ELK/Splunk: Log analysis
- Network monitoring: Flow logs, packet inspection

## Additional Resources

- [SpiceDB Security Model](https://authzed.com/docs/spicedb/concepts/security)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [OWASP Kubernetes Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Kubernetes_Security_Cheat_Sheet.html)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [PRODUCTION_GUIDE.md](../PRODUCTION_GUIDE.md)
- [TROUBLESHOOTING.md](../TROUBLESHOOTING.md)
