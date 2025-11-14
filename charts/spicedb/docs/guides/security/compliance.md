# Compliance and Regulatory Requirements

This guide covers compliance considerations, encryption requirements, audit logging, and regulatory framework requirements for SpiceDB deployments.

## Encryption

### Encryption at Rest

**Database encryption:**

- **AWS RDS**: Enable storage encryption

  ```hcl
  resource "aws_db_instance" "spicedb" {
    storage_encrypted = true
    kms_key_id       = aws_kms_key.spicedb.arn
  }
  ```

- **GCP Cloud SQL**: Automatic encryption with Cloud KMS

  ```hcl
  resource "google_sql_database_instance" "spicedb" {
    encryption_key_name = google_kms_crypto_key.spicedb.id
  }
  ```

- **CockroachDB**: Enable encryption at rest

  ```yaml
  cockroach start --enterprise-encryption=path=/cockroach/cockroach-data,key=/cockroach/keys/aes-128.key
  ```

**Kubernetes secrets encryption:**

```yaml
# kube-apiserver configuration
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <BASE64_ENCODED_SECRET>
  - identity: {}
```

**Backup encryption:**

```bash
# PostgreSQL backup with encryption
pg_dump -h localhost -U spicedb spicedb | \
  openssl enc -aes-256-cbc -salt -pbkdf2 -out backup.sql.enc

# Restore encrypted backup
openssl enc -d -aes-256-cbc -pbkdf2 -in backup.sql.enc | \
  psql -h localhost -U spicedb spicedb
```

### Encryption in Transit

**Full encryption configuration:**

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

**What this provides:**

- **Client to SpiceDB**: TLS required (gRPC, HTTP)
- **SpiceDB to database**: SSL/TLS required (sslMode: require/verify-full)
- **Pod-to-pod**: mTLS for dispatch (strongly recommended)
- **Ingress**: TLS termination or passthrough

## Audit Logging

### Kubernetes Audit Logging

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

# Log RBAC changes
- level: RequestResponse
  resources:
  - group: "rbac.authorization.k8s.io"
    resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
  verbs: ["create", "update", "patch", "delete"]
```

### SpiceDB Audit Logging

SpiceDB logs can be sent to centralized logging (ELK, Splunk, etc.):

```yaml
logging:
  level: info
  format: json  # Structured logging for parsing
```

### What to Audit

- Database connection attempts
- Migration executions
- Configuration changes
- Secret access
- Pod lifecycle events
- Network policy violations
- Authentication failures
- RBAC changes

### Log Aggregation Example

```yaml
# Fluentd configuration for SpiceDB logs
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd-config
  namespace: logging
data:
  fluent.conf: |
    <source>
      @type tail
      path /var/log/containers/spicedb-*.log
      pos_file /var/log/spicedb.log.pos
      tag spicedb.*
      <parse>
        @type json
        time_key time
        time_format %Y-%m-%dT%H:%M:%S.%NZ
      </parse>
    </source>

    <filter spicedb.**>
      @type record_transformer
      <record>
        application spicedb
        environment ${ENVIRONMENT}
      </record>
    </filter>

    <match spicedb.**>
      @type elasticsearch
      host elasticsearch.logging.svc
      port 9200
      logstash_format true
      logstash_prefix spicedb
    </match>
```

## Access Controls

### Principle of Least Privilege

#### 1. Database Permissions

```sql
-- Grant only required permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO spicedb;
-- Do NOT grant DROP, CREATE, ALTER

-- For migrations (separate user)
GRANT ALL PRIVILEGES ON SCHEMA public TO spicedb_migrations;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO spicedb_migrations;
```

#### 2. Kubernetes RBAC

```yaml
# Minimal RBAC (created by chart)
rbac:
  create: true  # Only necessary permissions
```

The chart creates only these permissions:

- Get/list pods (for dispatch discovery)
- Get/list/delete jobs (for migration cleanup)

#### 3. Network Access

```yaml
# Restrict to required namespaces only
networkPolicy:
  enabled: true
  ingressControllerNamespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: ingress-nginx
```

#### 4. Secret Access

- Use separate service accounts per application
- Restrict secret access via RBAC
- Use external secret management (AWS Secrets Manager, Vault, etc.)

## Compliance Frameworks

### PCI DSS (Payment Card Industry Data Security Standard)

**Requirements:**

- ✅ Encryption in transit (TLS) - **Requirement 4**
- ✅ Encryption at rest (database, secrets) - **Requirement 3**
- ✅ Access controls (RBAC, NetworkPolicy) - **Requirement 7**
- ✅ Audit logging - **Requirement 10**
- ✅ Regular security updates - **Requirement 6**
- ✅ Network segmentation - **Requirement 1**

**Configuration:**

```yaml
# PCI DSS compliant configuration
tls:
  enabled: true
  grpc:
    secretName: spicedb-grpc-tls
  dispatch:
    secretName: spicedb-dispatch-tls

config:
  datastore:
    sslMode: verify-full

networkPolicy:
  enabled: true

podSecurityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault

logging:
  level: info
  format: json
```

### HIPAA (Health Insurance Portability and Accountability Act)

**Requirements:**

- ✅ PHI encryption (TLS + database encryption) - **Security Rule § 164.312(a)(2)(iv)**
- ✅ Access controls and authentication - **Security Rule § 164.312(a)(1)**
- ✅ Audit logs for PHI access - **Security Rule § 164.312(b)**
- ✅ Disaster recovery (backups) - **Security Rule § 164.308(a)(7)(ii)(A)**
- ✅ Security assessments (vulnerability scanning) - **Security Rule § 164.308(a)(8)**

**Business Associate Agreement (BAA) considerations:**

- Ensure cloud provider has signed BAA
- Document PHI data flows
- Implement access controls
- Enable comprehensive audit logging

### SOC 2 (Service Organization Control 2)

**Trust Service Criteria:**

- ✅ Logical access controls - **CC6.1, CC6.2**
- ✅ Encryption - **CC6.7**
- ✅ Monitoring and logging - **CC7.2**
- ✅ Change management (GitOps) - **CC8.1**
- ✅ Incident response - **CC7.3, CC7.4, CC7.5**

**Configuration:**

```yaml
# SOC 2 control mappings
# CC6.1: Logical access controls
rbac:
  create: true

networkPolicy:
  enabled: true

# CC6.7: Encryption
tls:
  enabled: true

# CC7.2: Monitoring
serviceMonitor:
  enabled: true

# CC8.1: Change management (use GitOps)
# Deploy via ArgoCD or Flux
```

### GDPR (General Data Protection Regulation)

**Requirements:**

- ✅ Data encryption - **Article 32(1)(a)**
- ✅ Access controls - **Article 32(1)(b)**
- ✅ Audit trail - **Article 30**
- ✅ Right to erasure (database deletion capabilities) - **Article 17**
- ✅ Data portability - **Article 20**

**Data deletion procedure:**

```bash
# Delete specific subject data
kubectl exec -it spicedb-0 -- \
  spicedb datastore delete --subject-id "user:12345"

# Verify deletion
kubectl exec -it spicedb-0 -- \
  spicedb datastore check --subject-id "user:12345"
```

**Data export procedure:**

```bash
# Export relationships for data portability
kubectl exec -it spicedb-0 -- \
  spicedb datastore export --subject-id "user:12345" > user-data.json
```

### ISO 27001

**Relevant controls:**

- ✅ A.9: Access control
- ✅ A.10: Cryptography
- ✅ A.12.4: Logging and monitoring
- ✅ A.13: Network security
- ✅ A.14: System acquisition, development and maintenance

## Regular Security Updates

### Keep SpiceDB Updated

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

### Update Dependencies

**Critical dependencies to monitor:**

- Kubernetes cluster
- Database (PostgreSQL/CockroachDB)
- cert-manager
- Monitoring tools (Prometheus, Grafana)
- Ingress controllers

### Vulnerability Scanning

```bash
# Scan Helm chart
checkov -f values.yaml

# Scan deployed resources
kubesec scan deployment.yaml

# Scan container images
trivy image authzed/spicedb:v1.39.0
grype authzed/spicedb:v1.39.0
```

## Compliance Checklist

### Pre-Production Compliance Review

- [ ] **Encryption**
  - [ ] TLS enabled for all endpoints
  - [ ] Database encryption at rest enabled
  - [ ] Kubernetes secrets encryption enabled
  - [ ] Backup encryption configured
  - [ ] SSL mode set to verify-full

- [ ] **Access Controls**
  - [ ] RBAC enabled with minimal permissions
  - [ ] NetworkPolicy configured
  - [ ] Database user permissions minimized
  - [ ] Cloud IAM integration configured
  - [ ] Multi-factor authentication for admin access

- [ ] **Audit Logging**
  - [ ] Kubernetes audit logging enabled
  - [ ] Application logs aggregated
  - [ ] Log retention policy configured
  - [ ] Security event alerting configured
  - [ ] Audit log integrity protection

- [ ] **Data Protection**
  - [ ] Data classification documented
  - [ ] Data retention policy implemented
  - [ ] Backup and recovery tested
  - [ ] Data deletion procedure documented
  - [ ] Data export capability verified

- [ ] **Security Operations**
  - [ ] Vulnerability scanning enabled
  - [ ] Security patch process documented
  - [ ] Incident response plan created
  - [ ] Security contacts documented
  - [ ] Disaster recovery plan tested

- [ ] **Compliance Documentation**
  - [ ] Compliance requirements mapped
  - [ ] Security controls documented
  - [ ] Risk assessment completed
  - [ ] Privacy impact assessment (if applicable)
  - [ ] Third-party attestations obtained

## Continuous Compliance Monitoring

### Automated Compliance Checks

```bash
# Use Open Policy Agent for continuous compliance
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: requireencryption
spec:
  crd:
    spec:
      names:
        kind: RequireEncryption
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package requireencryption
      violation[{"msg": msg}] {
        input.review.object.kind == "Deployment"
        not input.review.object.spec.template.metadata.annotations["encryption.enabled"]
        msg := "Deployment must have encryption enabled"
      }
EOF
```

### Compliance Reporting

```bash
# Generate compliance report
kubectl get all -n spicedb -o json | \
  jq -r '.items[] | select(.kind == "Deployment") |
  {name: .metadata.name, tls: .spec.template.spec.containers[].env[] |
  select(.name | startswith("TLS")) | .value}'
```

## Additional Resources

- [PCI DSS v4.0](https://www.pcisecuritystandards.org/document_library/)
- [HIPAA Security Rule](https://www.hhs.gov/hipaa/for-professionals/security/index.html)
- [SOC 2 Trust Service Criteria](https://www.aicpa.org/interestareas/frc/assuranceadvisoryservices/aicpasoc2report.html)
- [GDPR](https://gdpr-info.eu/)
- [ISO 27001](https://www.iso.org/isoiec-27001-information-security.html)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
