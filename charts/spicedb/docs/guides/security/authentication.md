# Authentication and Secret Management

This guide covers authentication mechanisms, RBAC configuration, and secret management best practices for SpiceDB.

## Preshared Key Authentication

SpiceDB uses preshared keys for API authentication:

### Configuration

```yaml
config:
  presharedKey: "your-secure-random-key-here"
```

### Best Practices

#### 1. Generate Cryptographically Secure Keys

```bash
# Generate 32-byte random key (base64 encoded)
openssl rand -base64 32
```

#### 2. Store in Existing Secret (Recommended)

```yaml
config:
  existingSecret: spicedb-credentials
```

```bash
kubectl create secret generic spicedb-credentials \
  --from-literal=preshared-key="$(openssl rand -base64 32)"
```

#### 3. Never Commit Preshared Keys to Version Control

- Use `.gitignore` for values files with secrets
- Use encrypted secrets (sealed-secrets, SOPS)
- Use external secret management

#### 4. Rotate Keys Regularly

- Update secret
- Rolling restart to pick up new key
- Update all clients

#### 5. Use Different Keys Per Environment

- Development, staging, production use different keys
- Prevents accidental production access from dev

## RBAC Configuration

The chart creates minimal RBAC permissions:

```yaml
rbac:
  create: true  # Creates Role and RoleBinding

serviceAccount:
  create: true
  annotations: {}
```

### Default Permissions

- Get/list pods (for dispatch discovery)
- Get/list/delete jobs (for migration cleanup)

### Cloud IAM Integration

#### AWS (IRSA)

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/spicedb-role
```

#### GCP (Workload Identity)

```yaml
serviceAccount:
  annotations:
    iam.gke.io/gcp-service-account: spicedb@PROJECT_ID.iam.gserviceaccount.com
```

#### Azure (Workload Identity)

```yaml
serviceAccount:
  annotations:
    azure.workload.identity/client-id: AZURE_CLIENT_ID
```

## Secret Management

### Kubernetes Secrets

#### Built-in Secret Creation

The chart creates a secret for database credentials if `existingSecret` is not provided:

```yaml
# Not recommended for production
config:
  datastore:
    password: "insecure-password"
```

#### Recommended: Use Existing Secret

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

#### Example with AWS Secrets Manager

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

See [examples/postgres-external-secrets.yaml](../../examples/postgres-external-secrets.yaml) for complete configuration.

#### Benefits of External Secrets Operator

- Centralized secret management
- Automatic secret rotation
- Audit trail for secret access
- Separation of duties (ops vs. dev)

### Secret Best Practices

#### 1. Never Commit Secrets to Git

- Use `.gitignore` for values files with secrets
- Use encrypted secrets (sealed-secrets, SOPS)
- Use external secret management

#### 2. Use Different Secrets Per Environment

- Development, staging, production use different credentials
- Prevents accidental cross-environment access

#### 3. Rotate Secrets Regularly

- Database passwords: Every 90 days
- Preshared keys: Every 90 days
- TLS certificates: Every 90 days (automated with cert-manager)

#### 4. Limit Secret Access

```bash
# Check who can access secrets
kubectl auth can-i get secrets --as=system:serviceaccount:spicedb:spicedb

# Use RBAC to restrict access
```

#### 5. Encrypt Secrets at Rest

- Enable Kubernetes secrets encryption
- Use cloud provider KMS integration

#### 6. Audit Secret Access

- Enable Kubernetes audit logging
- Monitor secret access patterns
- Alert on unusual access

## Database Access Control

### Database Permissions

Grant only required permissions:

```sql
-- Grant only required permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO spicedb;
-- Do NOT grant DROP, CREATE, ALTER
```

### Connection Security

```yaml
config:
  datastoreEngine: postgres
  datastore:
    sslMode: verify-full  # Verifies certificate AND hostname
    sslRootCert: /etc/spicedb/tls/datastore/ca.crt
```

## Secret Rotation Procedure

### Rotating Preshared Keys

```bash
# 1. Generate new key
NEW_KEY=$(openssl rand -base64 32)

# 2. Update secret
kubectl create secret generic spicedb-credentials-new \
  --from-literal=preshared-key="$NEW_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Update Helm values
helm upgrade spicedb charts/spicedb \
  --set config.existingSecret=spicedb-credentials-new \
  --reuse-values

# 4. Wait for rollout
kubectl rollout status deployment/spicedb -n spicedb

# 5. Update all clients with new key

# 6. Verify clients are using new key

# 7. Delete old secret
kubectl delete secret spicedb-credentials -n spicedb
```

### Rotating Database Credentials

```bash
# 1. Create new database user with same permissions
psql -c "CREATE USER spicedb_new WITH PASSWORD 'new-password';"
psql -c "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO spicedb_new;"

# 2. Update secret
kubectl create secret generic spicedb-database-new \
  --from-literal=datastore-uri='postgresql://spicedb_new:new-password@host:5432/db?sslmode=require' \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Update Helm values
helm upgrade spicedb charts/spicedb \
  --set config.existingSecret=spicedb-database-new \
  --reuse-values

# 4. Wait for rollout
kubectl rollout status deployment/spicedb -n spicedb

# 5. Verify connectivity

# 6. Drop old database user
psql -c "DROP USER spicedb;"

# 7. Delete old secret
kubectl delete secret spicedb-database -n spicedb
```

## Secret Management Tools

### Sealed Secrets

Encrypt secrets for safe storage in Git:

```bash
# Install sealed-secrets controller
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml

# Create sealed secret
kubeseal --format yaml < secret.yaml > sealed-secret.yaml

# Commit sealed-secret.yaml to git
git add sealed-secret.yaml
git commit -m "Add sealed secret"
```

### SOPS (Secrets OPerationS)

Encrypt individual values in YAML files:

```bash
# Encrypt secrets in place
sops -e -i values-prod.yaml

# Decrypt during deployment
helm secrets upgrade spicedb charts/spicedb -f values-prod.yaml
```

### HashiCorp Vault

Integrate with Vault for dynamic secrets:

```yaml
# vault-secret.yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: spicedb-database
  namespace: spicedb
spec:
  vaultAuthRef: vault-auth
  mount: secret
  type: kv-v2
  path: spicedb/database
  refreshAfter: 1h
  destination:
    create: true
    name: spicedb-database
```

## Compliance and Audit

### Secret Access Audit

Enable Kubernetes audit logging for secret access:

```yaml
# kube-apiserver audit policy
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: RequestResponse
  resources:
  - group: ""
    resources: ["secrets"]
  namespaces: ["spicedb"]
```

### Access Reviews

Regularly review who has access to secrets:

```bash
# List who can get secrets
kubectl auth can-i list secrets --as-group=system:serviceaccounts:spicedb -n spicedb

# Review RBAC policies
kubectl get rolebindings,clusterrolebindings -n spicedb -o yaml
```

## Additional Resources

- [Kubernetes Secrets Best Practices](https://kubernetes.io/docs/concepts/configuration/secret/)
- [External Secrets Operator](https://external-secrets.io/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [SOPS](https://github.com/mozilla/sops)
- [HashiCorp Vault](https://www.vaultproject.io/)
