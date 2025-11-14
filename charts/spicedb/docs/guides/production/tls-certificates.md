# TLS Certificate Generation

This guide covers TLS certificate generation and management for SpiceDB production deployments using cert-manager or manual methods.

**Navigation:** [← Infrastructure](infrastructure.md) | [Index](index.md) | [Next: PostgreSQL Deployment →](postgresql-deployment.md)

## Table of Contents

- [Overview](#overview)
- [Using cert-manager (Recommended)](#using-cert-manager-recommended)
  - [Install cert-manager](#install-cert-manager)
  - [Configure Certificate Issuer](#configure-certificate-issuer)
  - [Create Certificates](#create-certificates)
- [Manual Certificate Creation](#manual-certificate-creation)
  - [Generate CA Certificate](#generate-ca-certificate)
  - [Generate Server Certificates](#generate-server-certificates)
  - [Generate Dispatch mTLS Certificates](#generate-dispatch-mtls-certificates)
  - [Generate Datastore Client Certificates](#generate-datastore-client-certificates)
  - [Create Kubernetes Secrets](#create-kubernetes-secrets)
- [Certificate Requirements](#certificate-requirements)

## Overview

TLS is strongly recommended for production deployments. This section covers certificate generation for all SpiceDB endpoints:

- **gRPC Endpoint**: Client API (port 50051)
- **HTTP Endpoint**: Dashboard and metrics (port 8443)
- **Dispatch Endpoint**: Inter-pod communication (port 50053)
- **Datastore Endpoint**: Database connection (PostgreSQL/CockroachDB)

## Using cert-manager (Recommended)

cert-manager automates certificate creation, renewal, and rotation. This is the recommended approach for production deployments.

### Install cert-manager

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Verify installation
kubectl wait --for=condition=Available --timeout=300s \
  deployment/cert-manager -n cert-manager
kubectl wait --for=condition=Available --timeout=300s \
  deployment/cert-manager-webhook -n cert-manager

# Check all components are running
kubectl get pods -n cert-manager
```

### Configure Certificate Issuer

Choose between Let's Encrypt (for public domains) or a private CA (for internal deployments).

#### Option 1: Let's Encrypt (Public Domains)

Use Let's Encrypt for SpiceDB instances exposed to the internet with valid DNS names.

```yaml
# letsencrypt-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com  # Change to your email
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
    # Or use DNS01 for wildcard certificates
    # - dns01:
    #     cloudflare:
    #       email: admin@example.com
    #       apiTokenSecretRef:
    #         name: cloudflare-api-token
    #         key: api-token
```

Apply the issuer:

```bash
kubectl apply -f letsencrypt-issuer.yaml

# Verify issuer is ready
kubectl get clusterissuer letsencrypt-prod
```

#### Option 2: Private CA (Internal Deployments)

Use a private CA for internal deployments or when external DNS is not available.

```yaml
# private-ca-issuer.yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned-issuer
  namespace: default
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: spicedb-ca
  namespace: default
spec:
  isCA: true
  commonName: spicedb-ca
  secretName: spicedb-ca-key-pair
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: selfsigned-issuer
    kind: Issuer
  duration: 87600h  # 10 years
  renewBefore: 8760h  # Renew 1 year before expiry
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: spicedb-ca-issuer
  namespace: default
spec:
  ca:
    secretName: spicedb-ca-key-pair
```

Apply the issuer:

```bash
kubectl apply -f private-ca-issuer.yaml

# Wait for CA certificate to be ready
kubectl wait --for=condition=Ready certificate spicedb-ca --timeout=60s

# Verify CA secret was created
kubectl get secret spicedb-ca-key-pair
```

### Create Certificates

Use the complete cert-manager integration example provided in the repository.

#### Apply Certificate Manifests

```bash
# Apply certificate manifests
kubectl apply -f examples/cert-manager-integration.yaml

# Wait for certificates to be ready
kubectl wait --for=condition=Ready certificate \
  spicedb-grpc-tls \
  spicedb-http-tls \
  spicedb-dispatch-tls \
  spicedb-datastore-tls \
  --timeout=300s

# Verify secrets were created
kubectl get secret spicedb-grpc-tls spicedb-http-tls \
  spicedb-dispatch-tls spicedb-datastore-tls
```

#### Certificate Configuration Example

Here's what the certificate manifests look like (see `examples/cert-manager-integration.yaml` for complete configuration):

```yaml
# gRPC Certificate
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: spicedb-grpc-tls
  namespace: default
spec:
  commonName: spicedb
  dnsNames:
  - spicedb
  - spicedb.default
  - spicedb.default.svc
  - spicedb.default.svc.cluster.local
  - spicedb.example.com  # External DNS if applicable
  secretName: spicedb-grpc-tls
  usages:
  - server auth
  - digital signature
  - key encipherment
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: spicedb-ca-issuer
    kind: Issuer
  duration: 2160h  # 90 days
  renewBefore: 720h  # Renew 30 days before expiry
```

See [examples/cert-manager-integration.yaml](../../examples/cert-manager-integration.yaml) for detailed certificate configuration including HTTP, dispatch, and datastore certificates.

## Manual Certificate Creation

If cert-manager is not available, generate certificates manually using OpenSSL.

### Generate CA Certificate

First, create a Certificate Authority (CA) to sign all certificates.

```bash
# Create directory for certificates
mkdir -p certs
cd certs

# Generate CA private key
openssl ecparam -name prime256v1 -genkey -noout -out ca.key

# Generate CA certificate (valid for 10 years)
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
  -out ca.crt \
  -subj "/CN=spicedb-ca/O=SpiceDB"

# Verify CA certificate
openssl x509 -in ca.crt -text -noout
```

### Generate Server Certificates

Generate certificates for gRPC and HTTP endpoints.

#### gRPC Certificate

```bash
# Generate private key
openssl ecparam -name prime256v1 -genkey -noout -out grpc.key

# Generate certificate signing request
openssl req -new -key grpc.key -out grpc.csr \
  -subj "/CN=spicedb-grpc/O=SpiceDB"

# Create SAN (Subject Alternative Names) configuration
cat > grpc-san.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
[req_distinguished_name]
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = spicedb
DNS.2 = spicedb.default
DNS.3 = spicedb.default.svc
DNS.4 = spicedb.default.svc.cluster.local
DNS.5 = spicedb.example.com
EOF

# Sign certificate with CA
openssl x509 -req -in grpc.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out grpc.crt -days 365 -sha256 \
  -extfile grpc-san.cnf -extensions v3_req

# Verify certificate
openssl x509 -in grpc.crt -text -noout | grep -A1 "Subject Alternative Name"
```

#### HTTP Certificate

```bash
# Generate private key
openssl ecparam -name prime256v1 -genkey -noout -out http.key

# Generate CSR
openssl req -new -key http.key -out http.csr \
  -subj "/CN=spicedb-http/O=SpiceDB"

# Create SAN configuration
cat > http-san.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
[req_distinguished_name]
[v3_req]
subjectAltName = @alt_names
[alt_names]
DNS.1 = spicedb
DNS.2 = spicedb.default.svc.cluster.local
DNS.3 = spicedb-dashboard.example.com
EOF

# Sign certificate
openssl x509 -req -in http.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out http.crt -days 365 -sha256 \
  -extfile http-san.cnf -extensions v3_req
```

### Generate Dispatch mTLS Certificates

Dispatch requires mutual TLS (both client and server authentication).

```bash
# Generate private key
openssl ecparam -name prime256v1 -genkey -noout -out dispatch.key

# Generate CSR
openssl req -new -key dispatch.key -out dispatch.csr \
  -subj "/CN=spicedb-dispatch/O=SpiceDB"

# Create configuration with both server and client auth
cat > dispatch-san.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
[req_distinguished_name]
[v3_req]
subjectAltName = @alt_names
extendedKeyUsage = serverAuth, clientAuth
[alt_names]
DNS.1 = spicedb
DNS.2 = *.spicedb.default.svc.cluster.local
EOF

# Sign certificate with CA
openssl x509 -req -in dispatch.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out dispatch.crt -days 365 -sha256 \
  -extfile dispatch-san.cnf -extensions v3_req

# Verify both client and server auth are present
openssl x509 -in dispatch.crt -text -noout | grep -A1 "Extended Key Usage"
```

### Generate Datastore Client Certificates

For CockroachDB or PostgreSQL with client certificate authentication.

#### CockroachDB Client Certificate

CockroachDB requires the CN to be `client.<username>`.

```bash
# Generate private key
openssl ecparam -name prime256v1 -genkey -noout -out client.spicedb.key

# Generate CSR (CN must be client.spicedb)
openssl req -new -key client.spicedb.key -out client.spicedb.csr \
  -subj "/CN=client.spicedb/O=SpiceDB"

# Sign certificate
openssl x509 -req -in client.spicedb.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out client.spicedb.crt -days 365 -sha256

# Verify certificate
openssl x509 -in client.spicedb.crt -text -noout | grep "Subject:"
# Should show: Subject: O=SpiceDB, CN=client.spicedb
```

#### PostgreSQL Client Certificate

For PostgreSQL with client certificate authentication:

```bash
# Generate private key
openssl ecparam -name prime256v1 -genkey -noout -out postgres-client.key

# Generate CSR (CN should match database username)
openssl req -new -key postgres-client.key -out postgres-client.csr \
  -subj "/CN=spicedb/O=SpiceDB"

# Sign certificate
openssl x509 -req -in postgres-client.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out postgres-client.crt -days 365 -sha256
```

### Create Kubernetes Secrets

Store certificates in Kubernetes secrets for use by SpiceDB.

```bash
# gRPC TLS secret
kubectl create secret tls spicedb-grpc-tls \
  --cert=grpc.crt \
  --key=grpc.key \
  --namespace=spicedb

# HTTP TLS secret
kubectl create secret tls spicedb-http-tls \
  --cert=http.crt \
  --key=http.key \
  --namespace=spicedb

# Dispatch mTLS secret (includes CA for mutual verification)
kubectl create secret generic spicedb-dispatch-tls \
  --from-file=tls.crt=dispatch.crt \
  --from-file=tls.key=dispatch.key \
  --from-file=ca.crt=ca.crt \
  --namespace=spicedb

# Datastore TLS secret (for CockroachDB)
kubectl create secret generic spicedb-datastore-tls \
  --from-file=tls.crt=client.spicedb.crt \
  --from-file=tls.key=client.spicedb.key \
  --from-file=ca.crt=cockroachdb-ca.crt \
  --namespace=spicedb

# Verify secrets were created
kubectl get secrets -n spicedb | grep spicedb-.*-tls
```

## Certificate Requirements

Each endpoint has specific certificate requirements.

### gRPC Endpoint (Client API)

**Purpose**: Secures client API connections (port 50051)

**Requirements**:

- Server certificate with DNS names matching service endpoints
- Required usages: `server auth`, `digital signature`, `key encipherment`
- Optional: CA certificate for client certificate verification (mTLS)

**DNS Names**:

- Internal: `spicedb`, `spicedb.default.svc.cluster.local`
- External: `spicedb.example.com` (if exposed externally)

### HTTP Endpoint (Dashboard/Metrics)

**Purpose**: Secures dashboard and metrics endpoints (port 8443)

**Requirements**:

- Server certificate with DNS names matching service endpoints
- Required usages: `server auth`, `digital signature`, `key encipherment`

**DNS Names**:

- Internal: `spicedb`, `spicedb.default.svc.cluster.local`
- External: `spicedb-dashboard.example.com` (if exposed externally)

### Dispatch Endpoint (Inter-pod Communication)

**Purpose**: Secures inter-pod communication for distributed request processing (port 50053)

**Requirements**:

- mTLS certificate (both client and server usages)
- Required usages: `server auth`, `client auth`, `digital signature`, `key encipherment`
- Must include CA certificate for mutual verification
- All pods must share the same CA

**DNS Names**:

- Wildcard: `*.spicedb.default.svc.cluster.local` (for pod-to-pod communication)
- Service: `spicedb` (for service discovery)

**Important**: The dispatch certificate must support both client and server authentication for mutual TLS.

### Datastore Endpoint (Database Connection)

**Purpose**: Authenticates SpiceDB to the database using client certificates

**Requirements**:

- Client certificate for database authentication
- Required usages: `client auth`, `digital signature`, `key encipherment`
- For CockroachDB: CN must be `client.<username>` (e.g., `client.spicedb`)
- For PostgreSQL: CN should match database username
- CA certificate to verify database server

**CockroachDB Specific**:

- Must use CockroachDB's CA or generate certificates with compatible CN format
- Supports `verify-full` SSL mode only in production

**PostgreSQL Specific**:

- Can use custom CA
- Supports various SSL modes: `require`, `verify-ca`, `verify-full`

## Certificate Rotation

### Automatic Rotation with cert-manager

cert-manager automatically renews certificates before they expire.

```bash
# Check certificate status
kubectl get certificate -n spicedb

# Force renewal (if needed)
kubectl delete certificaterequest -n spicedb -l cert-manager.io/certificate-name=spicedb-grpc-tls

# Watch renewal process
kubectl get certificaterequest -n spicedb --watch
```

### Manual Certificate Rotation

When using manual certificates:

1. Generate new certificates following the steps above
2. Update Kubernetes secrets:

```bash
# Update secret with new certificate
kubectl create secret tls spicedb-grpc-tls \
  --cert=grpc-new.crt \
  --key=grpc-new.key \
  --namespace=spicedb \
  --dry-run=client -o yaml | kubectl apply -f -
```

3. Restart SpiceDB pods to use new certificates:

```bash
kubectl rollout restart deployment/spicedb -n spicedb
```

## Next Steps

After configuring TLS certificates:

1. **PostgreSQL Path**: Continue to [PostgreSQL Deployment](postgresql-deployment.md)
2. **CockroachDB Path**: Continue to [CockroachDB Deployment](cockroachdb-deployment.md)
3. **High Availability**: Configure [High Availability](high-availability.md) features

**Navigation:** [← Infrastructure](infrastructure.md) | [Index](index.md) | [Next: PostgreSQL Deployment →](postgresql-deployment.md)
