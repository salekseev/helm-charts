# TLS Configuration

Transport Layer Security (TLS) is critical for production SpiceDB deployments. This guide covers TLS setup, certificate management, and mutual TLS (mTLS) configuration.

## Overview

TLS is critical for production deployments. This chart supports TLS for four distinct endpoints:

| Endpoint | Purpose | Recommended TLS | Certificate Type |
|----------|---------|----------------|------------------|
| gRPC | Client API | **Required** in production | Server TLS or mTLS |
| HTTP | Dashboard/Metrics | Recommended | Server TLS |
| Dispatch | Inter-pod communication | **Strongly recommended** | Mutual TLS (mTLS) |
| Datastore | Database connection | **Required** for CockroachDB | Client TLS or mTLS |

## Enabling TLS

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

## Certificate Management

### Option 1: cert-manager (Recommended)

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

See [examples/cert-manager-integration.yaml](../../examples/cert-manager-integration.yaml) for complete configuration.

### Option 2: Manual Certificates

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

## TLS Best Practices

### 1. Use TLS for All Endpoints in Production

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

### 2. Enable Dispatch mTLS for Multi-Replica Deployments

- Prevents unauthorized pods from joining the cluster
- Ensures internal communication is authenticated
- Required for zero-trust environments

### 3. Use verify-full SSL Mode for Databases

```yaml
config:
  datastore:
    sslMode: verify-full  # Verifies certificate AND hostname
    sslRootCert: /etc/spicedb/tls/datastore/ca.crt
```

### 4. Rotate Certificates Regularly

- cert-manager handles this automatically
- For manual certificates: Set calendar reminders
- Recommended: 90-day certificates, rotate at 60 days

### 5. Monitor Certificate Expiration

```bash
# Check expiration dates
kubectl get certificate -o custom-columns=\
NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter

# Set up alerts (Prometheus)
# Alert when certificates expire in < 30 days
```

### 6. Separate Certificates Per Endpoint

- Limits blast radius if a certificate is compromised
- Allows independent certificate rotation
- Easier to track and manage

### 7. Use Strong Cipher Suites

- SpiceDB uses secure defaults
- Regularly update to latest SpiceDB version for security patches

### 8. Backup CA Certificates and Keys

```bash
kubectl get secret spicedb-ca-key-pair -o yaml > spicedb-ca-backup.yaml
# Store securely outside the cluster (encrypted backup)
```

## mTLS for Dispatch Cluster

Mutual TLS (mTLS) for dispatch is critical in multi-replica deployments:

### Why mTLS?

- Prevents rogue pods from joining the cluster
- Ensures both client and server are authenticated
- Encrypts sensitive authorization data in transit

### Configuration

```yaml
dispatch:
  enabled: true

tls:
  enabled: true
  dispatch:
    secretName: spicedb-dispatch-tls

replicaCount: 3  # Multiple replicas required
```

### Certificate Requirements

- Must include both `server auth` and `client auth` usages
- All pods must use certificates from the same CA
- Secret must contain: `tls.crt`, `tls.key`, `ca.crt`

### Verification

```bash
# Check certificate has correct usages
kubectl get secret spicedb-dispatch-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -text -noout | grep -A 1 "X509v3 Extended Key Usage"

# Should show: TLS Web Server Authentication, TLS Web Client Authentication
```

## cert-manager Integration Example

Complete example for all endpoints:

```yaml
# Create a ClusterIssuer (one-time setup)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: spicedb-ca-issuer
spec:
  ca:
    secretName: spicedb-ca-key-pair

---
# gRPC certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: spicedb-grpc
  namespace: spicedb
spec:
  secretName: spicedb-grpc-tls
  duration: 2160h # 90 days
  renewBefore: 720h # 30 days
  subject:
    organizations:
      - spicedb
  commonName: spicedb-grpc.spicedb.svc.cluster.local
  dnsNames:
    - spicedb-grpc.spicedb.svc.cluster.local
    - spicedb.spicedb.svc
    - spicedb
  issuerRef:
    name: spicedb-ca-issuer
    kind: ClusterIssuer
  usages:
    - server auth
    - client auth

---
# HTTP certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: spicedb-http
  namespace: spicedb
spec:
  secretName: spicedb-http-tls
  duration: 2160h
  renewBefore: 720h
  subject:
    organizations:
      - spicedb
  commonName: spicedb-http.spicedb.svc.cluster.local
  dnsNames:
    - spicedb-http.spicedb.svc.cluster.local
    - spicedb.spicedb.svc
  issuerRef:
    name: spicedb-ca-issuer
    kind: ClusterIssuer
  usages:
    - server auth

---
# Dispatch mTLS certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: spicedb-dispatch
  namespace: spicedb
spec:
  secretName: spicedb-dispatch-tls
  duration: 2160h
  renewBefore: 720h
  subject:
    organizations:
      - spicedb
  commonName: spicedb-dispatch.spicedb.svc.cluster.local
  dnsNames:
    - spicedb-dispatch.spicedb.svc.cluster.local
    - "*.spicedb.spicedb.svc.cluster.local"
    - spicedb.spicedb.svc
  issuerRef:
    name: spicedb-ca-issuer
    kind: ClusterIssuer
  usages:
    - server auth
    - client auth  # Required for mTLS
```

## Datastore TLS Configuration

### PostgreSQL with TLS

```yaml
config:
  datastoreEngine: postgres
  datastore:
    sslMode: verify-full
    sslRootCert: /etc/spicedb/tls/datastore/ca.crt

tls:
  enabled: true
  datastore:
    secretName: spicedb-datastore-tls
```

### CockroachDB with mTLS

```yaml
config:
  datastoreEngine: cockroachdb
  datastore:
    sslMode: verify-full
    sslRootCert: /etc/spicedb/tls/datastore/ca.crt

tls:
  enabled: true
  datastore:
    secretName: spicedb-datastore-tls
    # CockroachDB requires client certificates
```

## Troubleshooting TLS

### Certificate Not Ready

```bash
# Check certificate status
kubectl describe certificate spicedb-grpc-tls -n spicedb

# Check cert-manager logs
kubectl logs -n cert-manager deploy/cert-manager

# Verify issuer is ready
kubectl get clusterissuer spicedb-ca-issuer -o yaml
```

### TLS Handshake Failures

```bash
# Check SpiceDB logs
kubectl logs -n spicedb -l app.kubernetes.io/name=spicedb

# Verify certificate content
kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -text -noout

# Test TLS connection
openssl s_client -connect spicedb.spicedb:50051 -showcerts
```

### Certificate Expiration Issues

```bash
# Check certificate expiration
kubectl get certificate -n spicedb -o custom-columns=\
NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter

# Force certificate renewal
kubectl delete secret spicedb-grpc-tls -n spicedb
# cert-manager will recreate it automatically
```

## Additional Resources

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [TLS Best Practices](https://github.com/ssllabs/research/wiki/SSL-and-TLS-Deployment-Best-Practices)
- [SpiceDB TLS Configuration](https://authzed.com/docs/spicedb/configuration/tls)
- [PRODUCTION_GUIDE.md](../PRODUCTION_GUIDE.md)
