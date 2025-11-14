# CockroachDB Deployment

This guide provides step-by-step instructions for deploying SpiceDB with CockroachDB in production.

**Navigation:** [← PostgreSQL Deployment](postgresql-deployment.md) | [Index](index.md) | [Next: High Availability →](high-availability.md)

## Table of Contents

- [Prerequisites](#prerequisites)
- [Step 1: Create Namespace](#step-1-create-namespace)
- [Step 2: Setup CockroachDB](#step-2-setup-cockroachdb)
- [Step 3: Generate Client Certificates](#step-3-generate-client-certificates)
- [Step 4: Configure SpiceDB TLS Certificates](#step-4-configure-spicedb-tls-certificates)
- [Step 5: Create Values File](#step-5-create-values-file)
- [Step 6: Deploy Chart](#step-6-deploy-chart)
- [Step 7: Verify Deployment](#step-7-verify-deployment)
- [Step 8: Test TLS Connectivity](#step-8-test-tls-connectivity)
- [Complete Example](#complete-example)

## Prerequisites

Before deploying SpiceDB with CockroachDB, ensure you have:

- Completed [Infrastructure Setup](infrastructure.md) for CockroachDB provisioning
- Configured [TLS Certificates](tls-certificates.md) (required for CockroachDB production)
- CockroachDB 22.1+ cluster running and accessible from Kubernetes cluster
- CockroachDB client certificates for SpiceDB user

**Important**: CockroachDB requires TLS for production deployments. This is not optional.

## Step 1: Create Namespace

```bash
# Create dedicated namespace for SpiceDB
kubectl create namespace spicedb

# Set as default namespace
kubectl config set-context --current --namespace=spicedb

# Verify namespace was created
kubectl get namespace spicedb
```

## Step 2: Setup CockroachDB

Follow the [Database Provisioning](infrastructure.md#cockroachdb-setup) section to create a CockroachDB cluster if you haven't already.

**Quick checklist**:

- [ ] CockroachDB cluster running with 3+ nodes
- [ ] TLS enabled on CockroachDB cluster
- [ ] Database `spicedb` created
- [ ] User `spicedb` created with appropriate permissions
- [ ] Network connectivity verified from Kubernetes cluster

**Verify CockroachDB is ready**:

```bash
# Connect to CockroachDB and verify setup
kubectl exec -it cockroachdb-0 -n database -- \
  ./cockroach sql --certs-dir=/cockroach/cockroach-certs

# Run verification commands:
# SHOW DATABASES;  -- Should include 'spicedb'
# SHOW USERS;      -- Should include 'spicedb'
```

## Step 3: Generate Client Certificates

CockroachDB requires TLS client certificates for authentication. Generate certificates for the SpiceDB user.

### Option A: Using cert-manager

Use cert-manager to automatically generate and manage CockroachDB client certificates.

**Create Certificate Resource**:

```yaml
# cockroachdb-client-cert.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: spicedb-cockroachdb-client
  namespace: spicedb
spec:
  # IMPORTANT: CN must be client.spicedb for CockroachDB
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
    # Reference to CockroachDB CA issuer
    name: cockroachdb-ca-issuer
    kind: Issuer
  duration: 2160h  # 90 days
  renewBefore: 720h  # Renew 30 days before expiry
```

Apply and wait for certificate:

```bash
kubectl apply -f cockroachdb-client-cert.yaml

# Wait for certificate to be ready
kubectl wait --for=condition=Ready certificate spicedb-cockroachdb-client --timeout=60s

# Verify secret was created
kubectl get secret spicedb-datastore-tls -n spicedb
```

**Note**: You must have a CockroachDB CA issuer configured. If you deployed CockroachDB with the operator, this should already exist in the `database` namespace.

### Option B: Manual Generation

Use CockroachDB's built-in certificate generation tool.

```bash
# Get CockroachDB CA certificate and key
kubectl get secret cockroachdb-ca -n database \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
kubectl get secret cockroachdb-ca -n database \
  -o jsonpath='{.data.ca\.key}' | base64 -d > ca.key

# Generate client certificate using CockroachDB tool
# Note: CN must be client.spicedb
cockroach cert create-client spicedb \
  --certs-dir=certs \
  --ca-key=ca.key

# Verify certificate was created
ls -la certs/client.spicedb.*

# Create Kubernetes secret
kubectl create secret generic spicedb-datastore-tls \
  --from-file=tls.crt=certs/client.spicedb.crt \
  --from-file=tls.key=certs/client.spicedb.key \
  --from-file=ca.crt=ca.crt \
  --namespace=spicedb

# Cleanup local files
rm ca.key  # Keep CA key secure!
```

### Verify Client Certificate

```bash
# Check certificate CN
kubectl get secret spicedb-datastore-tls -n spicedb \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | grep "Subject:"

# Should show: Subject: CN=client.spicedb
```

## Step 4: Configure SpiceDB TLS Certificates

Generate TLS certificates for SpiceDB endpoints (gRPC, HTTP, dispatch) as described in the [TLS Certificates](tls-certificates.md) guide.

**Verify all TLS secrets exist**:

```bash
# Check all required secrets
kubectl get secrets -n spicedb | grep spicedb-.*-tls

# Should show:
# - spicedb-grpc-tls
# - spicedb-http-tls
# - spicedb-dispatch-tls (optional, for dispatch cluster)
# - spicedb-datastore-tls (CockroachDB client cert)
```

## Step 5: Create Values File

Create a comprehensive values file for CockroachDB deployment.

```yaml
# production-cockroachdb-values.yaml
replicaCount: 5

image:
  repository: authzed/spicedb
  tag: "v1.39.0"
  pullPolicy: IfNotPresent

# TLS configuration for all endpoints
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
  # CockroachDB datastore engine
  datastoreEngine: cockroachdb

  # Logging configuration
  logLevel: info

  # Database connection configuration
  datastore:
    hostname: cockroachdb-public.database.svc.cluster.local
    port: 26257
    username: spicedb
    password: "CHANGE_ME_SECURE_PASSWORD"
    database: spicedb

    # TLS configuration (required for CockroachDB)
    sslMode: verify-full
    sslRootCert: /etc/spicedb/tls/datastore/ca.crt
    sslCert: /etc/spicedb/tls/datastore/tls.crt
    sslKey: /etc/spicedb/tls/datastore/tls.key

# Resource requests and limits
resources:
  requests:
    cpu: 1000m
    memory: 1Gi
  limits:
    cpu: 4000m
    memory: 4Gi

# Pod disruption budget for high availability
podDisruptionBudget:
  enabled: true
  minAvailable: 3  # Require at least 3 pods available

# Anti-affinity to spread pods across nodes
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

# Enable automatic database migrations
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
```

### Alternative: Using External Secrets for Password

Instead of hardcoding the password, use External Secrets Operator:

```yaml
# production-cockroachdb-values.yaml (with External Secrets)
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

  # Reference to external secret for database password
  existingSecret: spicedb-database

  logLevel: info

  datastore:
    hostname: cockroachdb-public.database.svc.cluster.local
    port: 26257
    username: spicedb
    database: spicedb
    sslMode: verify-full
    sslRootCert: /etc/spicedb/tls/datastore/ca.crt
    sslCert: /etc/spicedb/tls/datastore/tls.crt
    sslKey: /etc/spicedb/tls/datastore/tls.key

# ... rest of configuration
```

## Step 6: Deploy Chart

Deploy SpiceDB using Helm:

```bash
# Install SpiceDB with CockroachDB
helm install spicedb charts/spicedb \
  --namespace=spicedb \
  --values=production-cockroachdb-values.yaml \
  --wait \
  --timeout=10m

# Watch the deployment
kubectl get pods -n spicedb --watch
```

**What happens during deployment**:

1. Helm creates all Kubernetes resources
2. TLS certificates are mounted into pods
3. Migration job runs to initialize CockroachDB schema
4. SpiceDB pods start after migrations complete
5. Dispatch cluster forms between pods (if enabled)

## Step 7: Verify Deployment

Verify all components are running correctly.

### Check All Components

```bash
# Check all resources
kubectl get all -n spicedb

# Should show:
# - Deployment with 5/5 replicas ready
# - Service with endpoints
# - Migration job completed
```

### Verify TLS Certificates are Mounted

```bash
# Check TLS certificates are mounted in pods
kubectl exec -n spicedb spicedb-0 -- ls -la /etc/spicedb/tls/

# Should show directories:
# - grpc/
# - http/
# - dispatch/
# - datastore/
```

### Check Datastore Connection

```bash
# Check logs for successful database connection
kubectl logs -n spicedb -l app.kubernetes.io/name=spicedb | grep -i "datastore.*connected"

# Should see log entries indicating successful connection
```

### Verify Migration Completed

```bash
# Check migration job status
kubectl get jobs -n spicedb -l app.kubernetes.io/component=migration

# Should show Completions: 1/1

# View migration logs
kubectl logs -n spicedb -l app.kubernetes.io/component=migration

# Should see "migrations completed successfully"
```

### Check Pod Health

```bash
# Check all pods are running and ready
kubectl get pods -n spicedb -l app.kubernetes.io/name=spicedb -o wide

# Verify pods are distributed across nodes
# Check all pods show READY 1/1
```

## Step 8: Test TLS Connectivity

Test SpiceDB endpoints with TLS enabled.

### Extract CA Certificate

```bash
# Get CA certificate for client testing
kubectl get secret -n spicedb spicedb-grpc-tls \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt

# Or if using separate CA secret
kubectl get secret -n spicedb spicedb-ca-key-pair \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > ca.crt
```

### Test gRPC with TLS

```bash
# Port-forward gRPC endpoint
kubectl port-forward -n spicedb svc/spicedb 50051:50051

# In another terminal, test with grpcurl using TLS
grpcurl -cacert ca.crt localhost:50051 list

# Should return list of services:
# - authzed.api.v1.PermissionsService
# - authzed.api.v1.SchemaService
# - authzed.api.v1.WatchService
```

### Test HTTP with TLS

```bash
# Port-forward HTTP endpoint
kubectl port-forward -n spicedb svc/spicedb 8443:8443

# In another terminal, test metrics endpoint
curl --cacert ca.crt https://localhost:8443/metrics

# Should return Prometheus metrics
```

### Verify Dispatch Cluster

If dispatch cluster is enabled with mTLS:

```bash
# Check endpoints are discovered
kubectl get endpoints spicedb -n spicedb

# Verify dispatch port is listening on all pods
for pod in $(kubectl get pods -n spicedb -l app.kubernetes.io/name=spicedb -o name); do
  echo "Checking $pod"
  kubectl exec -n spicedb $pod -- netstat -tlnp | grep 50053
done

# Check logs for dispatch cluster formation
kubectl logs -n spicedb -l app.kubernetes.io/name=spicedb | grep -i dispatch
```

## Complete Example

For a complete production-ready CockroachDB configuration with full TLS, see [examples/production-cockroachdb-tls.yaml](../../examples/production-cockroachdb-tls.yaml).

**Features included in complete example**:

- CockroachDB datastore engine
- Full TLS for all endpoints (gRPC, HTTP, dispatch, datastore)
- Client certificate authentication for CockroachDB
- High availability with 5 replicas
- Pod disruption budget (minimum 3 available)
- Anti-affinity rules (required scheduling)
- Resource requests and limits
- Automatic database migrations
- Dispatch cluster with mTLS
- Prometheus metrics and ServiceMonitor

## Troubleshooting

### Client Certificate Authentication Fails

**Problem**: Logs show "authentication failed" or "certificate verification failed"

**Solution**:

```bash
# Verify certificate CN is correct
kubectl get secret spicedb-datastore-tls -n spicedb \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | grep "Subject:"

# CN must be: client.spicedb

# Verify CA matches CockroachDB CA
kubectl get secret spicedb-datastore-tls -n spicedb \
  -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -text -noout | grep "Subject:"

# Should match CockroachDB's CA certificate
```

### TLS Handshake Failures

**Problem**: Logs show "TLS handshake failed" or "certificate verify failed"

**Solution**:

```bash
# Check all TLS certificates are valid
for cert in spicedb-grpc-tls spicedb-http-tls spicedb-dispatch-tls spicedb-datastore-tls; do
  echo "Checking $cert:"
  kubectl get secret -n spicedb $cert \
    -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | grep -A2 "Validity"
done

# Verify certificates haven't expired
# Verify DNS names in SAN match service endpoints
```

### Pods Cannot Connect to CockroachDB

**Problem**: Logs show "connection refused" or "context deadline exceeded"

**Solution**:

```bash
# Test connectivity from pod to CockroachDB
kubectl exec -n spicedb spicedb-0 -- \
  nc -zv cockroachdb-public.database.svc.cluster.local 26257

# Should show: succeeded!

# Verify DNS resolution
kubectl exec -n spicedb spicedb-0 -- \
  nslookup cockroachdb-public.database.svc.cluster.local

# Check firewall rules allow traffic from spicedb namespace to database namespace
```

### Migration Job Fails with CockroachDB

**Problem**: Migration job fails to complete

**Solution**:

```bash
# Check migration job logs
kubectl logs -n spicedb -l app.kubernetes.io/component=migration

# Common issues:
# - Client certificate not valid: Verify CN is client.spicedb
# - CA certificate mismatch: Ensure CA matches CockroachDB's CA
# - Database permissions: Ensure spicedb user has CREATE/ALTER permissions
# - CockroachDB not ready: Wait for all CockroachDB nodes to be running
```

## Next Steps

After successful CockroachDB deployment:

1. **Configure High Availability**: Review and optimize [High Availability](high-availability.md) settings
2. **Set Up Monitoring**: Configure Prometheus and Grafana for CockroachDB and SpiceDB metrics
3. **Configure Backups**: Set up automated CockroachDB backups to cloud storage
4. **Load Testing**: Perform load testing to validate distributed performance
5. **Security Review**: Review TLS configuration and certificate rotation policies

**Navigation:** [← PostgreSQL Deployment](postgresql-deployment.md) | [Index](index.md) | [Next: High Availability →](high-availability.md)
