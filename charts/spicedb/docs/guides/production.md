# SpiceDB Production Deployment Guide

This guide provides step-by-step instructions for deploying SpiceDB in production environments with PostgreSQL or CockroachDB.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Infrastructure Setup](#infrastructure-setup)
- [TLS Certificate Generation](#tls-certificate-generation)
- [PostgreSQL Deployment](#postgresql-deployment)
- [CockroachDB Deployment](#cockroachdb-deployment)
- [High Availability Configuration](#high-availability-configuration)
- [Post-Deployment Verification](#post-deployment-verification)

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

## Infrastructure Setup

### Database Provisioning

#### PostgreSQL Setup

1. Create a dedicated database instance:

```bash
# Example using managed PostgreSQL (adjust for your cloud provider)
# AWS RDS example:
aws rds create-db-instance \
  --db-instance-identifier spicedb-postgres \
  --db-instance-class db.t3.medium \
  --engine postgres \
  --engine-version 15.3 \
  --master-username spicedb \
  --master-user-password 'CHANGE_ME_SECURE_PASSWORD' \
  --allocated-storage 100 \
  --storage-type gp3 \
  --storage-encrypted \
  --backup-retention-period 7 \
  --multi-az \
  --publicly-accessible false \
  --vpc-security-group-ids sg-xxxxx
```

2. Create the SpiceDB database:

```bash
# Connect to PostgreSQL
psql -h postgres-host.rds.amazonaws.com -U spicedb -d postgres

# Create database
CREATE DATABASE spicedb;

# Grant permissions
GRANT ALL PRIVILEGES ON DATABASE spicedb TO spicedb;
```

3. Enable SSL/TLS (recommended):

```sql
-- Verify SSL is enabled
SHOW ssl;

-- Should return "on"
```

#### CockroachDB Setup

1. Create a CockroachDB cluster:

```bash
# Example using CockroachDB Kubernetes Operator
kubectl apply -f https://raw.githubusercontent.com/cockroachdb/cockroach-operator/master/install/crds.yaml
kubectl apply -f https://raw.githubusercontent.com/cockroachdb/cockroach-operator/master/install/operator.yaml

# Create CockroachDB cluster
cat <<EOF | kubectl apply -f -
apiVersion: crdb.cockroachlabs.com/v1alpha1
kind: CrdbCluster
metadata:
  name: cockroachdb
  namespace: database
spec:
  dataStore:
    pvc:
      spec:
        accessModes:
        - ReadWriteOnce
        resources:
          requests:
            storage: 100Gi
        storageClassName: fast-ssd
  resources:
    requests:
      cpu: 2
      memory: 4Gi
    limits:
      cpu: 4
      memory: 8Gi
  tlsEnabled: true
  nodes: 3
EOF
```

2. Create the SpiceDB database and user:

```bash
# Connect to CockroachDB
kubectl exec -it cockroachdb-0 -n database -- ./cockroach sql --certs-dir=/cockroach/cockroach-certs

# Create database
CREATE DATABASE spicedb;

# Create user
CREATE USER spicedb WITH PASSWORD 'CHANGE_ME_SECURE_PASSWORD';

# Grant permissions
GRANT ALL ON DATABASE spicedb TO spicedb;
```

3. Generate client certificates for SpiceDB (see TLS section below).

### Network Requirements

#### Network Connectivity

Ensure Kubernetes pods can reach the database:

```bash
# Test database connectivity from a pod
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql "postgresql://spicedb:password@postgres-host:5432/spicedb?sslmode=require"

# For CockroachDB
kubectl run -it --rm debug --image=cockroachdb/cockroach:latest --restart=Never -- \
  sql --url "postgresql://spicedb:password@cockroachdb-public.database:26257/spicedb?sslmode=verify-full"
```

#### Firewall Rules

Configure security groups/firewall rules:

**PostgreSQL:**
- Allow inbound TCP 5432 from Kubernetes node CIDR ranges
- Deny all other inbound traffic

**CockroachDB:**
- Allow inbound TCP 26257 (SQL) from Kubernetes node CIDR ranges
- Allow inbound TCP 8080 (Admin UI) from admin networks (optional)
- Deny all other inbound traffic

#### DNS Resolution

Verify DNS resolution works from within the cluster:

```bash
# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup postgres-host.rds.amazonaws.com

# For in-cluster database
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup cockroachdb-public.database.svc.cluster.local
```

### Storage Considerations

#### Database Storage

**PostgreSQL:**
- Use SSD-backed storage (gp3 on AWS, pd-ssd on GCP)
- Provision IOPS based on expected workload (minimum 3000 IOPS)
- Enable automated backups (7-30 day retention)
- Consider read replicas for read-heavy workloads

**CockroachDB:**
- Use local SSD storage for best performance
- Provision 2-3x expected data size for compaction overhead
- Enable incremental backups to S3/GCS
- Use separate storage class for production workloads

#### Kubernetes Storage

SpiceDB itself is stateless, but consider:
- Ephemeral volume for `/tmp` (if using readOnlyRootFilesystem)
- EmptyDir for temporary TLS certificate generation
- Persistent volumes NOT required for SpiceDB pods

## TLS Certificate Generation

TLS is strongly recommended for production deployments. This section covers certificate generation for all SpiceDB endpoints.

### Using cert-manager (Recommended)

cert-manager automates certificate creation, renewal, and rotation.

#### Install cert-manager

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Verify installation
kubectl wait --for=condition=Available --timeout=300s \
  deployment/cert-manager -n cert-manager
kubectl wait --for=condition=Available --timeout=300s \
  deployment/cert-manager-webhook -n cert-manager
```

#### Configure Certificate Issuer

Choose between Let's Encrypt (public domains) or private CA (internal deployments):

**Option 1: Let's Encrypt (Public Domains)**

```yaml
# letsencrypt-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
```

**Option 2: Private CA (Internal Deployments)**

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
# For Let's Encrypt
kubectl apply -f letsencrypt-issuer.yaml

# For private CA
kubectl apply -f private-ca-issuer.yaml
```

#### Create Certificates

Use the complete cert-manager integration example:

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

See [examples/cert-manager-integration.yaml](examples/cert-manager-integration.yaml) for detailed certificate configuration.

### Manual Certificate Creation

If cert-manager is not available, generate certificates manually using OpenSSL.

#### Generate CA Certificate

```bash
# Generate CA private key
openssl ecparam -name prime256v1 -genkey -noout -out ca.key

# Generate CA certificate
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
  -out ca.crt \
  -subj "/CN=spicedb-ca/O=SpiceDB"
```

#### Generate Server Certificates (gRPC, HTTP)

```bash
# gRPC certificate
openssl ecparam -name prime256v1 -genkey -noout -out grpc.key

openssl req -new -key grpc.key -out grpc.csr \
  -subj "/CN=spicedb-grpc/O=SpiceDB"

# Create SAN configuration
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

# Sign certificate
openssl x509 -req -in grpc.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out grpc.crt -days 365 -sha256 \
  -extfile grpc-san.cnf -extensions v3_req

# Repeat for HTTP certificate (adjust DNS names as needed)
```

#### Generate Dispatch mTLS Certificates

```bash
# Dispatch certificate (mTLS - both client and server auth)
openssl ecparam -name prime256v1 -genkey -noout -out dispatch.key

openssl req -new -key dispatch.key -out dispatch.csr \
  -subj "/CN=spicedb-dispatch/O=SpiceDB"

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

openssl x509 -req -in dispatch.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out dispatch.crt -days 365 -sha256 \
  -extfile dispatch-san.cnf -extensions v3_req
```

#### Generate Datastore Client Certificates (CockroachDB)

```bash
# CockroachDB client certificate
openssl ecparam -name prime256v1 -genkey -noout -out client.spicedb.key

openssl req -new -key client.spicedb.key -out client.spicedb.csr \
  -subj "/CN=client.spicedb/O=SpiceDB"

openssl x509 -req -in client.spicedb.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out client.spicedb.crt -days 365 -sha256
```

#### Create Kubernetes Secrets

```bash
# gRPC TLS secret
kubectl create secret tls spicedb-grpc-tls \
  --cert=grpc.crt \
  --key=grpc.key

# HTTP TLS secret
kubectl create secret tls spicedb-http-tls \
  --cert=http.crt \
  --key=http.key

# Dispatch mTLS secret (includes CA)
kubectl create secret generic spicedb-dispatch-tls \
  --from-file=tls.crt=dispatch.crt \
  --from-file=tls.key=dispatch.key \
  --from-file=ca.crt=ca.crt

# Datastore TLS secret (for CockroachDB)
kubectl create secret generic spicedb-datastore-tls \
  --from-file=tls.crt=client.spicedb.crt \
  --from-file=tls.key=client.spicedb.key \
  --from-file=ca.crt=cockroachdb-ca.crt
```

### Certificate Requirements

Each endpoint has specific certificate requirements:

**gRPC Endpoint (Client API):**
- Server certificate with DNS names matching service endpoints
- Required usages: `server auth`, `digital signature`, `key encipherment`
- Optional: CA certificate for client certificate verification (mTLS)

**HTTP Endpoint (Dashboard/Metrics):**
- Server certificate with DNS names matching service endpoints
- Required usages: `server auth`, `digital signature`, `key encipherment`

**Dispatch Endpoint (Inter-pod Communication):**
- mTLS certificate (both client and server usages)
- Required usages: `server auth`, `client auth`, `digital signature`, `key encipherment`
- Must include CA certificate for mutual verification
- All pods must share the same CA

**Datastore Endpoint (Database Connection):**
- Client certificate for database authentication
- Required usages: `client auth`, `digital signature`, `key encipherment`
- For CockroachDB: CN must be `client.<username>` (e.g., `client.spicedb`)
- CA certificate to verify database server

## PostgreSQL Deployment

This section provides step-by-step instructions for deploying SpiceDB with PostgreSQL.

### Step 1: Create Namespace

```bash
# Create dedicated namespace for SpiceDB
kubectl create namespace spicedb

# Set as default namespace for convenience
kubectl config set-context --current --namespace=spicedb
```

### Step 2: Setup Database

Follow the [Database Provisioning](#database-provisioning) section above to create PostgreSQL instance.

### Step 3: Configure Credentials

Choose one of the following methods to provide database credentials:

#### Option A: Using Kubernetes Secrets

```bash
# Create secret with database credentials
kubectl create secret generic spicedb-database \
  --from-literal=datastore-uri='postgresql://spicedb:SECURE_PASSWORD@postgres.example.com:5432/spicedb?sslmode=require' \
  --namespace=spicedb
```

#### Option B: Using External Secrets Operator

See [examples/postgres-external-secrets.yaml](examples/postgres-external-secrets.yaml) for complete configuration.

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

Apply the external secret:

```bash
kubectl apply -f external-secret.yaml
```

### Step 4: Enable TLS (Recommended)

If using TLS, create certificates using cert-manager or manual generation (see [TLS Certificate Generation](#tls-certificate-generation)).

For basic deployment without TLS, skip to Step 5.

### Step 5: Configure Migrations

Create a values file for the deployment:

```yaml
# production-postgres-values.yaml
replicaCount: 3

image:
  repository: authzed/spicedb
  tag: "v1.39.0"

config:
  datastoreEngine: postgres
  existingSecret: spicedb-database
  logLevel: info

# Enable automatic migrations
migrations:
  enabled: true
  logLevel: info
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 100m
      memory: 128Mi

resources:
  requests:
    cpu: 1000m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 2Gi

podDisruptionBudget:
  enabled: true
  maxUnavailable: 1

service:
  type: ClusterIP
  grpcPort: 50051
  httpPort: 8443

# Optional: Enable TLS
# tls:
#   enabled: true
#   grpc:
#     secretName: spicedb-grpc-tls
#   http:
#     secretName: spicedb-http-tls
```

### Step 6: Deploy Chart

```bash
# Add Helm repository (once chart is published)
# helm repo add spicedb https://example.com/charts
# helm repo update

# Install SpiceDB
helm install spicedb charts/spicedb \
  --namespace=spicedb \
  --values=production-postgres-values.yaml \
  --wait \
  --timeout=10m

# Watch the deployment
kubectl get pods -n spicedb --watch
```

### Step 7: Verify Deployment

```bash
# Check migration job completed successfully
kubectl get jobs -n spicedb -l app.kubernetes.io/component=migration
kubectl logs -n spicedb -l app.kubernetes.io/component=migration

# Check SpiceDB pods are running
kubectl get pods -n spicedb -l app.kubernetes.io/name=spicedb

# Check pod logs
kubectl logs -n spicedb -l app.kubernetes.io/name=spicedb --tail=50

# Verify service is available
kubectl get svc -n spicedb
```

### Step 8: Test Connectivity

```bash
# Port-forward to test gRPC connection
kubectl port-forward -n spicedb svc/spicedb 50051:50051

# In another terminal, test with grpcurl
grpcurl -plaintext localhost:50051 list

# Should return list of services including:
# - authzed.api.v1.PermissionsService
# - authzed.api.v1.SchemaService
# - authzed.api.v1.WatchService
```

### Complete PostgreSQL Example

For a complete production-ready PostgreSQL configuration, see [examples/production-postgres.yaml](examples/production-postgres.yaml).

## CockroachDB Deployment

This section provides step-by-step instructions for deploying SpiceDB with CockroachDB.

### Step 1: Create Namespace

```bash
# Create dedicated namespace for SpiceDB
kubectl create namespace spicedb

# Set as default namespace
kubectl config set-context --current --namespace=spicedb
```

### Step 2: Setup CockroachDB

Follow the [Database Provisioning](#database-provisioning) section to create CockroachDB cluster.

### Step 3: Generate Client Certificates

CockroachDB requires TLS for production. Generate client certificates:

#### Using cert-manager

```yaml
# cockroachdb-client-cert.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: spicedb-cockroachdb-client
  namespace: spicedb
spec:
  commonName: client.spicedb
  secretName: spicedb-datastore-tls
  usages:
  - client auth
  - digital signature
  - key encipherment
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: cockroachdb-ca-issuer
    kind: Issuer
  duration: 2160h
  renewBefore: 720h
```

Apply and wait for certificate:

```bash
kubectl apply -f cockroachdb-client-cert.yaml
kubectl wait --for=condition=Ready certificate spicedb-cockroachdb-client
```

#### Manual Generation

```bash
# Use CockroachDB's certificate generation tool
cockroach cert create-client spicedb \
  --certs-dir=certs \
  --ca-key=ca.key

# Create Kubernetes secret
kubectl create secret generic spicedb-datastore-tls \
  --from-file=tls.crt=certs/client.spicedb.crt \
  --from-file=tls.key=certs/client.spicedb.key \
  --from-file=ca.crt=certs/ca.crt \
  --namespace=spicedb
```

### Step 4: Configure SpiceDB TLS Certificates

Generate TLS certificates for SpiceDB endpoints (see [TLS Certificate Generation](#tls-certificate-generation)).

### Step 5: Create Values File

```yaml
# production-cockroachdb-values.yaml
replicaCount: 5

image:
  repository: authzed/spicedb
  tag: "v1.39.0"

tls:
  enabled: true
  grpc:
    secretName: spicedb-grpc-tls
  http:
    secretName: spicedb-http-tls
  dispatch:
    secretName: spicedb-dispatch-tls
  datastore:
    secretName: spicedb-datastore-tls

config:
  datastoreEngine: cockroachdb
  logLevel: info

  datastore:
    hostname: cockroachdb-public.database.svc.cluster.local
    port: 26257
    username: spicedb
    password: "CHANGE_ME"
    database: spicedb
    sslMode: verify-full
    sslRootCert: /etc/spicedb/tls/datastore/ca.crt
    sslCert: /etc/spicedb/tls/datastore/tls.crt
    sslKey: /etc/spicedb/tls/datastore/tls.key

resources:
  requests:
    cpu: 1000m
    memory: 1Gi
  limits:
    cpu: 4000m
    memory: 4Gi

podDisruptionBudget:
  enabled: true
  minAvailable: 3

affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: app.kubernetes.io/name
          operator: In
          values:
          - spicedb
      topologyKey: kubernetes.io/hostname
```

### Step 6: Deploy Chart

```bash
# Install SpiceDB with CockroachDB
helm install spicedb charts/spicedb \
  --namespace=spicedb \
  --values=production-cockroachdb-values.yaml \
  --wait \
  --timeout=10m
```

### Step 7: Verify Deployment

```bash
# Check all components
kubectl get all -n spicedb

# Verify TLS certificates are mounted
kubectl exec -n spicedb spicedb-0 -- ls -la /etc/spicedb/tls/

# Check datastore connection
kubectl logs -n spicedb -l app.kubernetes.io/name=spicedb | grep -i "datastore.*connected"
```

### Step 8: Test TLS Connectivity

```bash
# Get CA certificate for client testing
kubectl get secret -n spicedb spicedb-grpc-tls \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt

# Port-forward
kubectl port-forward -n spicedb svc/spicedb 50051:50051

# Test with grpcurl using TLS
grpcurl -cacert ca.crt localhost:50051 list
```

### Complete CockroachDB Example

For a complete production-ready CockroachDB configuration with full TLS, see [examples/production-cockroachdb-tls.yaml](examples/production-cockroachdb-tls.yaml).

## High Availability Configuration

This section covers advanced HA features for production deployments.

### Multiple Replicas

Run at least 3 replicas for production:

```yaml
replicaCount: 3  # Minimum for HA
# Or 5 for better availability
```

### Pod Disruption Budget

Ensure availability during voluntary disruptions:

```yaml
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1  # Allow 1 pod to be down during updates
  # Or use minAvailable for stricter guarantees:
  # minAvailable: 2
```

Verify PDB is working:

```bash
kubectl get pdb -n spicedb
kubectl describe pdb spicedb -n spicedb
```

### Horizontal Pod Autoscaler

Enable automatic scaling based on CPU/memory:

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80
```

Prerequisites:
```bash
# Verify metrics-server is installed
kubectl get apiservice v1beta1.metrics.k8s.io

# Check if metrics are available
kubectl top pods -n spicedb
```

Verify HPA is working:

```bash
kubectl get hpa -n spicedb
kubectl describe hpa spicedb -n spicedb

# Watch HPA scale pods
kubectl get hpa spicedb -n spicedb --watch
```

### Anti-Affinity Rules

Distribute pods across nodes:

```yaml
affinity:
  podAntiAffinity:
    # Soft preference (recommended for smaller clusters)
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app.kubernetes.io/name
            operator: In
            values:
            - spicedb
        topologyKey: kubernetes.io/hostname

    # Hard requirement (for larger clusters with sufficient nodes)
    # requiredDuringSchedulingIgnoredDuringExecution:
    # - labelSelector:
    #     matchExpressions:
    #     - key: app.kubernetes.io/name
    #       operator: In
    #       values:
    #       - spicedb
    #   topologyKey: kubernetes.io/hostname
```

Verify pod distribution:

```bash
# Check pods are on different nodes
kubectl get pods -n spicedb -o wide

# Should see different NODE values for each pod
```

### Topology Spread Constraints

Distribute pods across availability zones:

```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app.kubernetes.io/name: spicedb
```

Verify zone distribution:

```bash
# Check pod distribution across zones
kubectl get pods -n spicedb \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone
```

### Complete HA Example

For a comprehensive HA configuration with all features enabled, see [examples/production-ha.yaml](examples/production-ha.yaml).

## Post-Deployment Verification

### Verify Migrations

```bash
# Check migration job status
kubectl get jobs -n spicedb -l app.kubernetes.io/component=migration

# View migration logs
kubectl logs -n spicedb -l app.kubernetes.io/component=migration

# Should see "migrations completed successfully"
```

### Verify Pod Health

```bash
# Check all pods are running
kubectl get pods -n spicedb

# Check readiness probes
kubectl get pods -n spicedb -o wide

# View pod events
kubectl describe pods -n spicedb -l app.kubernetes.io/name=spicedb
```

### Verify Service Connectivity

```bash
# Check service endpoints
kubectl get svc -n spicedb
kubectl get endpoints -n spicedb

# Port-forward to test
kubectl port-forward -n spicedb svc/spicedb 50051:50051

# Test gRPC API
grpcurl -plaintext localhost:50051 list
```

### Verify Database Connectivity

```bash
# Check logs for database connection
kubectl logs -n spicedb -l app.kubernetes.io/name=spicedb | grep -i datastore

# Should see successful connection messages
```

### Verify TLS Configuration

```bash
# Check TLS is enabled in environment variables
kubectl exec -n spicedb spicedb-0 -- env | grep TLS

# Verify certificates are mounted
kubectl exec -n spicedb spicedb-0 -- ls -la /etc/spicedb/tls/

# Test TLS endpoint
kubectl get secret -n spicedb spicedb-grpc-tls \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt

grpcurl -cacert ca.crt spicedb.spicedb.svc.cluster.local:50051 list
```

### Load Testing

Perform load testing to validate production readiness:

```bash
# Use ghz or similar gRPC load testing tool
ghz --insecure \
  --proto schema.proto \
  --call authzed.api.v1.PermissionsService/CheckPermission \
  --data '{"resource": {"objectType": "document", "objectId": "1"}, "permission": "read", "subject": {"object": {"objectType": "user", "objectId": "alice"}}}' \
  --duration 60s \
  --concurrency 50 \
  localhost:50051

# Monitor metrics during load test
kubectl port-forward -n spicedb svc/spicedb 9090:9090
# Visit http://localhost:9090/metrics
```

### Monitoring Setup

```bash
# Verify Prometheus is scraping metrics
kubectl port-forward -n spicedb svc/spicedb 9090:9090
curl http://localhost:9090/metrics | grep spicedb_

# If using ServiceMonitor, check it was created
kubectl get servicemonitor -n spicedb
```

### Disaster Recovery Test

Test backup and restore procedures:

```bash
# PostgreSQL backup
pg_dump -h postgres-host -U spicedb -d spicedb > spicedb-backup.sql

# CockroachDB backup
cockroach sql --url="postgresql://root@cockroachdb:26257?sslmode=verify-full" \
  --execute="BACKUP DATABASE spicedb TO 's3://backups/spicedb?AWS_ACCESS_KEY_ID=xxx&AWS_SECRET_ACCESS_KEY=xxx';"

# Test restore on separate environment
```

## Next Steps

After successful deployment:

1. **Configure Monitoring**: Set up Prometheus and Grafana dashboards
2. **Set Up Alerts**: Configure alerting for critical metrics
3. **Configure Backup**: Automate database backups
4. **Document Runbooks**: Create operational runbooks for common scenarios
5. **Plan Disaster Recovery**: Test and document DR procedures
6. **Review Security**: Conduct security review and penetration testing

For troubleshooting common issues, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

For upgrade procedures, see [UPGRADE_GUIDE.md](UPGRADE_GUIDE.md).

For security best practices, see [SECURITY.md](SECURITY.md).
