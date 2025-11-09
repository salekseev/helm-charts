# SpiceDB Security Guide

This guide covers security features, best practices, and compliance considerations for SpiceDB deployments.

## Table of Contents

- [Security Features](#security-features)
- [TLS Configuration](#tls-configuration)
- [Authentication and Authorization](#authentication-and-authorization)
- [Secret Management](#secret-management)
- [Network Security](#network-security)
- [Pod Security](#pod-security)
- [Compliance Considerations](#compliance-considerations)
- [Security Checklist](#security-checklist)

## Security Features

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

## TLS Configuration

### Overview

TLS is critical for production deployments. This chart supports TLS for four distinct endpoints:

| Endpoint | Purpose | Recommended TLS | Certificate Type |
|----------|---------|----------------|------------------|
| gRPC | Client API | **Required** in production | Server TLS or mTLS |
| HTTP | Dashboard/Metrics | Recommended | Server TLS |
| Dispatch | Inter-pod communication | **Strongly recommended** | Mutual TLS (mTLS) |
| Datastore | Database connection | **Required** for CockroachDB | Client TLS or mTLS |

### Enabling TLS

Basic TLS configuration in Helm values:

```yaml
tls:
  # Master switch - must be true to enable any TLS
  enabled: true

  # gRPC endpoint (client API)
  grpc:
    secretName: spicedb-grpc-tls

  # HTTP endpoint (dashboard)
  http:
    secretName: spicedb-http-tls

  # Dispatch cluster (inter-pod mTLS)
  dispatch:
    secretName: spicedb-dispatch-tls

  # Datastore connection (database)
  datastore:
    secretName: spicedb-datastore-tls
```

### Certificate Management

**Option 1: cert-manager (Recommended)**

Automated certificate lifecycle management:

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Create certificates
kubectl apply -f examples/cert-manager-integration.yaml

# Verify certificates
kubectl get certificate
kubectl wait --for=condition=Ready certificate --all
```

**Benefits:**
- Automated renewal (no manual intervention)
- Consistent certificate management
- Supports multiple CAs (Let's Encrypt, private CA, etc.)
- Handles certificate rotation seamlessly

See [examples/cert-manager-integration.yaml](examples/cert-manager-integration.yaml) for complete configuration.

**Option 2: Manual Certificates**

For environments without cert-manager, create certificates manually:

```bash
# Generate certificates (see PRODUCTION_GUIDE.md for details)
openssl ...

# Create Kubernetes secrets
kubectl create secret tls spicedb-grpc-tls --cert=grpc.crt --key=grpc.key
kubectl create secret generic spicedb-dispatch-tls \
  --from-file=tls.crt=dispatch.crt \
  --from-file=tls.key=dispatch.key \
  --from-file=ca.crt=ca.crt
```

**Important:** You are responsible for certificate renewal before expiration.

### TLS Best Practices

1. **Use TLS for all endpoints in production**
   ```yaml
   tls:
     enabled: true
     grpc:
       secretName: spicedb-grpc-tls
     http:
       secretName: spicedb-http-tls
     dispatch:
       secretName: spicedb-dispatch-tls
   ```

2. **Enable dispatch mTLS for multi-replica deployments**
   - Prevents unauthorized pods from joining the cluster
   - Ensures internal communication is authenticated
   - Required for zero-trust environments

3. **Use verify-full SSL mode for databases**
   ```yaml
   config:
     datastore:
       sslMode: verify-full  # Verifies certificate AND hostname
       sslRootCert: /etc/spicedb/tls/datastore/ca.crt
   ```

4. **Rotate certificates regularly**
   - cert-manager handles this automatically
   - For manual certificates: Set calendar reminders
   - Recommended: 90-day certificates, rotate at 60 days

5. **Monitor certificate expiration**
   ```bash
   # Check expiration dates
   kubectl get certificate -o custom-columns=\
   NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter

   # Set up alerts (Prometheus)
   # Alert when certificates expire in < 30 days
   ```

6. **Separate certificates per endpoint**
   - Limits blast radius if a certificate is compromised
   - Allows independent certificate rotation
   - Easier to track and manage

7. **Use strong cipher suites**
   - SpiceDB uses secure defaults
   - Regularly update to latest SpiceDB version for security patches

8. **Backup CA certificates and keys**
   ```bash
   kubectl get secret spicedb-ca-key-pair -o yaml > spicedb-ca-backup.yaml
   # Store securely outside the cluster (encrypted backup)
   ```

### mTLS for Dispatch Cluster

Mutual TLS (mTLS) for dispatch is critical in multi-replica deployments:

**Why mTLS?**
- Prevents rogue pods from joining the cluster
- Ensures both client and server are authenticated
- Encrypts sensitive authorization data in transit

**Configuration:**
```yaml
dispatch:
  enabled: true

tls:
  enabled: true
  dispatch:
    secretName: spicedb-dispatch-tls

replicaCount: 3  # Multiple replicas required
```

**Certificate requirements:**
- Must include both `server auth` and `client auth` usages
- All pods must use certificates from the same CA
- Secret must contain: `tls.crt`, `tls.key`, `ca.crt`

**Verification:**
```bash
# Check certificate has correct usages
kubectl get secret spicedb-dispatch-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -text -noout | grep -A 1 "X509v3 Extended Key Usage"

# Should show: TLS Web Server Authentication, TLS Web Client Authentication
```

## Authentication and Authorization

### Preshared Key Authentication

SpiceDB uses preshared keys for API authentication:

**Configuration:**
```yaml
config:
  presharedKey: "your-secure-random-key-here"
```

**Best practices:**
1. **Generate cryptographically secure keys:**
   ```bash
   # Generate 32-byte random key (base64 encoded)
   openssl rand -base64 32
   ```

2. **Store in existing secret (recommended):**
   ```yaml
   config:
     existingSecret: spicedb-credentials
   ```
   ```bash
   kubectl create secret generic spicedb-credentials \
     --from-literal=preshared-key="$(openssl rand -base64 32)"
   ```

3. **Never commit preshared keys to version control**

4. **Rotate keys regularly:**
   - Update secret
   - Rolling restart to pick up new key
   - Update all clients

5. **Use different keys per environment:**
   - Development, staging, production use different keys
   - Prevents accidental production access from dev

### RBAC Configuration

The chart creates minimal RBAC permissions:

```yaml
rbac:
  create: true  # Creates Role and RoleBinding

serviceAccount:
  create: true
  annotations: {}
```

**Default permissions:**
- Get/list pods (for dispatch discovery)
- Get/list/delete jobs (for migration cleanup)

**Cloud IAM integration:**

**AWS (IRSA):**
```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/spicedb-role
```

**GCP (Workload Identity):**
```yaml
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: spicedb@PROJECT_ID.iam.gserviceaccount.com
```

**Azure (Workload Identity):**
```yaml
serviceAccount:
  annotations:
    azure.workload.identity/client-id: AZURE_CLIENT_ID
```

## Secret Management

### Kubernetes Secrets

**Built-in secret creation:**

The chart creates a secret for database credentials if `existingSecret` is not provided:

```yaml
# Not recommended for production
config:
  datastore:
    password: "insecure-password"
```

**Recommended: Use existing secret:**
```yaml
config:
  existingSecret: spicedb-database
```
```bash
kubectl create secret generic spicedb-database \
  --from-literal=datastore-uri='postgresql://user:password@host:5432/db?sslmode=require'
```

### External Secrets Operator

**Recommended for production**: Use External Secrets Operator to sync secrets from external secret managers.

**Example with AWS Secrets Manager:**

```yaml
# external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: spicedb-database
  namespace: spicedb
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: spicedb-database
    template:
      data:
        datastore-uri: |
          postgresql://{{ .username }}:{{ .password }}@{{ .hostname }}:5432/{{ .database }}?sslmode=require
  dataFrom:
  - extract:
      key: spicedb/database
```

See [examples/postgres-external-secrets.yaml](examples/postgres-external-secrets.yaml) for complete configuration.

**Benefits:**
- Centralized secret management
- Automatic secret rotation
- Audit trail for secret access
- Separation of duties (ops vs. dev)

### Secret Best Practices

1. **Never commit secrets to git:**
   - Use `.gitignore` for values files with secrets
   - Use encrypted secrets (sealed-secrets, SOPS)
   - Use external secret management

2. **Use different secrets per environment:**
   - Development, staging, production use different credentials
   - Prevents accidental cross-environment access

3. **Rotate secrets regularly:**
   - Database passwords: Every 90 days
   - Preshared keys: Every 90 days
   - TLS certificates: Every 90 days (automated with cert-manager)

4. **Limit secret access:**
   ```bash
   # Check who can access secrets
   kubectl auth can-i get secrets --as=system:serviceaccount:spicedb:spicedb

   # Use RBAC to restrict access
   ```

5. **Encrypt secrets at rest:**
   - Enable Kubernetes secrets encryption
   - Use cloud provider KMS integration

6. **Audit secret access:**
   - Enable Kubernetes audit logging
   - Monitor secret access patterns
   - Alert on unusual access

## Network Security

### NetworkPolicy

Enable NetworkPolicy for zero-trust networking:

```yaml
networkPolicy:
  enabled: true

  # Allow ingress from specific namespaces
  ingressControllerNamespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: ingress-nginx

  # Allow Prometheus to scrape metrics
  prometheusNamespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: monitoring

  # Restrict database egress
  databaseEgress:
    ports:
    - protocol: TCP
      port: 5432
    to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: database
```

**What NetworkPolicy provides:**
- **Namespace isolation**: Only allowed namespaces can access SpiceDB
- **Pod-level access control**: Only specific pods can connect
- **Egress control**: Limit outbound connections
- **Defense in depth**: Network-level security complements application security

**Example production NetworkPolicy:**

```yaml
networkPolicy:
  enabled: true

  # Allow ingress controller (gRPC and HTTP)
  ingressControllerNamespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: ingress-nginx

  # Allow Prometheus (metrics only)
  prometheusNamespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: monitoring

  # Restrict database access
  databaseEgress:
    ports:
    - protocol: TCP
      port: 5432
    to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: database
      podSelector:
        matchLabels:
          app: postgresql

  # Custom rules for specific application access
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          app: my-application
    ports:
    - protocol: TCP
      port: 50051
```

**Verification:**
```bash
# Check NetworkPolicy is created
kubectl get networkpolicy -n spicedb

# Describe NetworkPolicy
kubectl describe networkpolicy spicedb -n spicedb

# Test access from allowed namespace
kubectl run -it --rm test -n ingress-nginx --image=nicolaka/netshoot --restart=Never -- \
  nc -zv spicedb.spicedb 50051

# Test access from denied namespace (should fail)
kubectl run -it --rm test -n default --image=nicolaka/netshoot --restart=Never -- \
  nc -zv spicedb.spicedb 50051
```

### Service Mesh Integration

For advanced traffic management and security, integrate with a service mesh:

**Istio Example:**

```yaml
# Require mTLS for all traffic to SpiceDB
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: spicedb-mtls
  namespace: spicedb
spec:
  mtls:
    mode: STRICT

---
# Authorization policy
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: spicedb-authz
  namespace: spicedb
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: spicedb
  rules:
  - from:
    - source:
        namespaces: ["ingress-nginx", "application"]
    to:
    - operation:
        ports: ["50051", "8443"]
```

**Benefits:**
- Automatic mTLS between services
- Fine-grained authorization policies
- Traffic encryption without application changes
- Observability and tracing

### Firewall and Network Segmentation

**Cloud provider security groups:**

**AWS Security Groups:**
```hcl
# Terraform example
resource "aws_security_group" "spicedb" {
  name        = "spicedb-sg"
  vpc_id      = var.vpc_id

  # Allow gRPC from application tier
  ingress {
    from_port   = 50051
    to_port     = 50051
    protocol    = "tcp"
    cidr_blocks = [var.application_cidr]
  }

  # Allow metrics from monitoring
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = [var.monitoring_cidr]
  }

  # Allow egress to database
  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.database_cidr]
  }
}
```

## Pod Security

### Pod Security Standards

This chart implements the Kubernetes **restricted** Pod Security Standard:

**Pod-level security context:**
```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault
```

**Container-level security context:**
```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
```

**What this provides:**
- **Non-root execution**: Reduces container breakout risk
- **Read-only filesystem**: Prevents malicious writes
- **Dropped capabilities**: Minimal Linux capabilities
- **Seccomp profile**: Restricts syscalls
- **No privilege escalation**: Prevents gaining root

### Pod Security Admission

Enable Pod Security Admission (PSA) at namespace level:

```yaml
# Enforce restricted profile
apiVersion: v1
kind: Namespace
metadata:
  name: spicedb
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

**Verification:**
```bash
# Check namespace labels
kubectl get namespace spicedb -o yaml | grep pod-security

# Try to deploy privileged pod (should be blocked)
kubectl run test --image=nginx --privileged -n spicedb
# Error: pods "test" is forbidden: violates PodSecurity "restricted:latest"
```

### Image Security

**Best practices for container images:**

1. **Use specific image tags:**
   ```yaml
   image:
     tag: "v1.39.0"  # NOT "latest"
   ```

2. **Scan images for vulnerabilities:**
   ```bash
   # Using Trivy
   trivy image authzed/spicedb:v1.39.0

   # Using Grype
   grype authzed/spicedb:v1.39.0
   ```

3. **Use image pull secrets for private registries:**
   ```yaml
   imagePullSecrets:
   - name: registry-credentials
   ```

4. **Enable image verification:**
   - Use cosign to verify image signatures
   - Implement admission controllers (OPA, Kyverno)

### Resource Limits

Enforce resource limits to prevent resource exhaustion attacks:

```yaml
resources:
  limits:
    cpu: 2000m
    memory: 4Gi
  requests:
    cpu: 1000m
    memory: 1Gi
```

**Why resource limits matter:**
- Prevents DoS via resource exhaustion
- Ensures fair resource sharing
- Protects cluster stability
- Required for Guaranteed QoS

## Compliance Considerations

### Encryption

**Encryption at rest:**
- **Database**: Enable encryption at rest for PostgreSQL/CockroachDB
  - AWS RDS: Enable storage encryption
  - GCP Cloud SQL: Automatic encryption
  - CockroachDB: Enable encryption at rest
- **Kubernetes secrets**: Enable secrets encryption
- **Backups**: Encrypt database backups

**Encryption in transit:**
- **Client to SpiceDB**: TLS required (gRPC, HTTP)
- **SpiceDB to database**: SSL/TLS required (sslMode: require/verify-full)
- **Pod-to-pod**: mTLS for dispatch (strongly recommended)
- **Ingress**: TLS termination or passthrough

**Configuration for full encryption:**
```yaml
tls:
  enabled: true
  grpc:
    secretName: spicedb-grpc-tls
  http:
    secretName: spicedb-http-tls
  dispatch:
    secretName: spicedb-dispatch-tls

config:
  datastoreEngine: postgres
  datastore:
    sslMode: verify-full
    sslRootCert: /etc/spicedb/tls/datastore/ca.crt
```

### Audit Logging

**Kubernetes audit logging:**

Enable audit logging at the cluster level:

```yaml
# kube-apiserver audit policy
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
# Log secret access
- level: RequestResponse
  resources:
  - group: ""
    resources: ["secrets"]
  namespaces: ["spicedb"]

# Log pod creation/deletion
- level: Request
  resources:
  - group: ""
    resources: ["pods"]
  verbs: ["create", "delete"]
  namespaces: ["spicedb"]
```

**SpiceDB audit logging:**

SpiceDB logs can be sent to centralized logging (ELK, Splunk, etc.):

```yaml
logging:
  level: info
  format: json  # Structured logging for parsing
```

**What to audit:**
- Database connection attempts
- Migration executions
- Configuration changes
- Secret access
- Pod lifecycle events
- Network policy violations

### Access Controls

**Principle of least privilege:**

1. **Database permissions:**
   ```sql
   -- Grant only required permissions
   GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO spicedb;
   -- Do NOT grant DROP, CREATE, ALTER
   ```

2. **Kubernetes RBAC:**
   ```yaml
   # Minimal RBAC (created by chart)
   rbac:
     create: true  # Only necessary permissions
   ```

3. **Network access:**
   ```yaml
   # Restrict to required namespaces only
   networkPolicy:
     enabled: true
   ```

4. **Secret access:**
   - Use separate service accounts per application
   - Restrict secret access via RBAC

### Compliance Frameworks

**PCI DSS:**
- ✅ Encryption in transit (TLS)
- ✅ Encryption at rest (database, secrets)
- ✅ Access controls (RBAC, NetworkPolicy)
- ✅ Audit logging
- ✅ Regular security updates
- ✅ Network segmentation

**HIPAA:**
- ✅ PHI encryption (TLS + database encryption)
- ✅ Access controls and authentication
- ✅ Audit logs for PHI access
- ✅ Disaster recovery (backups)
- ✅ Security assessments (vulnerability scanning)

**SOC 2:**
- ✅ Logical access controls
- ✅ Encryption
- ✅ Monitoring and logging
- ✅ Change management (GitOps)
- ✅ Incident response

**GDPR:**
- ✅ Data encryption
- ✅ Access controls
- ✅ Audit trail
- ✅ Right to erasure (database deletion capabilities)
- ✅ Data portability

### Regular Security Updates

**Keep SpiceDB updated:**
```bash
# Subscribe to security advisories
# https://github.com/authzed/spicedb/security/advisories

# Check for updates regularly
helm search repo spicedb --versions

# Apply security patches promptly
helm upgrade spicedb charts/spicedb \
  --set image.tag=v1.39.1 \
  --reuse-values
```

**Update dependencies:**
- Kubernetes cluster
- Database (PostgreSQL/CockroachDB)
- cert-manager
- Monitoring tools

## Security Checklist

### Pre-Production Security Checklist

- [ ] **TLS enabled for all endpoints**
  - [ ] gRPC TLS configured
  - [ ] HTTP TLS configured
  - [ ] Dispatch mTLS configured
  - [ ] Database SSL/TLS configured (verify-full mode)

- [ ] **Authentication and secrets**
  - [ ] Strong preshared key generated (32+ bytes random)
  - [ ] Secrets stored in external secret manager (not in values files)
  - [ ] Database credentials rotated from defaults
  - [ ] Different secrets per environment

- [ ] **Network security**
  - [ ] NetworkPolicy enabled
  - [ ] Ingress restricted to required namespaces
  - [ ] Egress restricted to database only
  - [ ] Security groups/firewall rules configured

- [ ] **Pod security**
  - [ ] Pod Security Standards enforced (restricted profile)
  - [ ] Non-root containers verified
  - [ ] Read-only root filesystem enabled
  - [ ] Resource limits configured

- [ ] **RBAC and access control**
  - [ ] RBAC enabled
  - [ ] Service account with minimal permissions
  - [ ] Cloud IAM integration configured (if applicable)

- [ ] **Monitoring and audit**
  - [ ] Audit logging enabled
  - [ ] Metrics collection configured
  - [ ] Alerts set up for security events
  - [ ] Log aggregation configured

- [ ] **Compliance**
  - [ ] Encryption at rest enabled (database, secrets)
  - [ ] Encryption in transit verified (all endpoints)
  - [ ] Audit requirements documented
  - [ ] Backup and disaster recovery tested

- [ ] **Operational security**
  - [ ] Vulnerability scanning enabled (containers, dependencies)
  - [ ] Update process documented
  - [ ] Incident response plan created
  - [ ] Security contacts documented

### Runtime Security Monitoring

**Monitor for:**
- Failed authentication attempts
- Unusual network traffic patterns
- Resource exhaustion attempts
- Certificate expiration
- Database connection failures
- Unauthorized access attempts

**Tools:**
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
- [PRODUCTION_GUIDE.md](PRODUCTION_GUIDE.md)
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
