# PostgreSQL Deployment

This guide provides step-by-step instructions for deploying SpiceDB with PostgreSQL in production.

**Navigation:** [← TLS Certificates](tls-certificates.md) | [Index](index.md) | [Next: High Availability →](high-availability.md)

## Table of Contents

- [Prerequisites](#prerequisites)
- [Step 1: Create Namespace](#step-1-create-namespace)
- [Step 2: Setup Database](#step-2-setup-database)
- [Step 3: Configure Credentials](#step-3-configure-credentials)
- [Step 4: Enable TLS](#step-4-enable-tls)
- [Step 5: Configure Migrations](#step-5-configure-migrations)
- [Step 6: Deploy Chart](#step-6-deploy-chart)
- [Step 7: Verify Deployment](#step-7-verify-deployment)
- [Step 8: Test Connectivity](#step-8-test-connectivity)
- [Complete Example](#complete-example)

## Prerequisites

Before deploying SpiceDB with PostgreSQL, ensure you have:

- Completed [Infrastructure Setup](infrastructure.md) for PostgreSQL provisioning
- (Optional) Configured [TLS Certificates](tls-certificates.md) for secure communications
- PostgreSQL 13+ instance running and accessible from Kubernetes cluster
- Database credentials with appropriate permissions

## Step 1: Create Namespace

```bash
# Create dedicated namespace for SpiceDB
kubectl create namespace spicedb

# Set as default namespace for convenience
kubectl config set-context --current --namespace=spicedb

# Verify namespace was created
kubectl get namespace spicedb
```

## Step 2: Setup Database

Follow the [Database Provisioning](infrastructure.md#postgresql-setup) section to create a PostgreSQL instance if you haven't already.

**Quick checklist**:

- [ ] PostgreSQL instance created and running
- [ ] Database `spicedb` created
- [ ] User `spicedb` created with appropriate permissions
- [ ] Network connectivity verified from Kubernetes cluster
- [ ] SSL/TLS enabled on PostgreSQL (recommended)

**Verify database is ready**:

```bash
# Test connection from a temporary pod
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql "postgresql://spicedb:password@postgres-host:5432/spicedb?sslmode=require" \
  -c "SELECT version();"

# Should display PostgreSQL version
```

## Step 3: Configure Credentials

Choose one of the following methods to provide database credentials.

### Option A: Using Kubernetes Secrets

Create a secret with the database connection string:

```bash
# Create secret with database credentials
kubectl create secret generic spicedb-database \
  --from-literal=datastore-uri='postgresql://spicedb:SECURE_PASSWORD@postgres.example.com:5432/spicedb?sslmode=require' \
  --namespace=spicedb

# Verify secret was created
kubectl get secret spicedb-database -n spicedb
```

**Connection String Format**:

```text
postgresql://[username]:[password]@[hostname]:[port]/[database]?[parameters]
```

**Common SSL Modes**:

- `sslmode=disable` - No SSL (not recommended for production)
- `sslmode=require` - Require SSL but don't verify certificate
- `sslmode=verify-ca` - Verify server certificate with CA
- `sslmode=verify-full` - Verify server certificate and hostname (most secure)

### Option B: Using External Secrets Operator

Use External Secrets Operator to sync credentials from external secret management systems.

**Install External Secrets Operator** (if not already installed):

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets \
  external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace
```

**Configure Secret Store** (AWS Secrets Manager example):

```yaml
# secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: spicedb
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
```

**Create External Secret**:

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

Apply the configuration:

```bash
kubectl apply -f secret-store.yaml
kubectl apply -f external-secret.yaml

# Verify external secret synced successfully
kubectl get externalsecret spicedb-database -n spicedb
kubectl get secret spicedb-database -n spicedb
```

See [examples/postgres-external-secrets.yaml](../../examples/postgres-external-secrets.yaml) for complete configuration.

## Step 4: Enable TLS

If using TLS for SpiceDB endpoints (recommended for production), ensure certificates are created.

### With cert-manager

If you've configured cert-manager in the [TLS Certificates](tls-certificates.md) guide:

```bash
# Verify certificates are ready
kubectl get certificate -n spicedb

# Should show certificates in Ready state:
# - spicedb-grpc-tls
# - spicedb-http-tls
# - spicedb-dispatch-tls (optional, for dispatch cluster)
```

### Without TLS

For basic deployment without TLS (development/testing only):

- Skip TLS configuration in values file
- Ensure you comment out or remove `tls:` section in values

**Note**: TLS is strongly recommended for production environments.

## Step 5: Configure Migrations

Create a values file for the deployment with migration configuration.

```yaml
# production-postgres-values.yaml
replicaCount: 3

image:
  repository: authzed/spicedb
  tag: "v1.39.0"
  pullPolicy: IfNotPresent

config:
  # PostgreSQL datastore engine
  datastoreEngine: postgres

  # Reference to database credentials secret
  existingSecret: spicedb-database

  # Logging configuration
  logLevel: info

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

# Resource requests and limits
resources:
  requests:
    cpu: 1000m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 2Gi

# Pod disruption budget for high availability
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1

# Service configuration
service:
  type: ClusterIP
  grpcPort: 50051
  httpPort: 8443

# Optional: Enable TLS
# Uncomment if using cert-manager or manual certificates
# tls:
#   enabled: true
#   grpc:
#     secretName: spicedb-grpc-tls
#   http:
#     secretName: spicedb-http-tls
```

### With TLS Enabled

If you've configured TLS certificates:

```yaml
# production-postgres-values.yaml (with TLS)
replicaCount: 3

image:
  repository: authzed/spicedb
  tag: "v1.39.0"

# TLS configuration
tls:
  enabled: true
  grpc:
    secretName: spicedb-grpc-tls
  http:
    secretName: spicedb-http-tls
  # Optional: Enable dispatch cluster with mTLS
  # dispatch:
  #   secretName: spicedb-dispatch-tls

config:
  datastoreEngine: postgres
  existingSecret: spicedb-database
  logLevel: info

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
```

## Step 6: Deploy Chart

Deploy SpiceDB using Helm:

```bash
# Add Helm repository (once chart is published)
# helm repo add spicedb https://example.com/charts
# helm repo update

# Install SpiceDB from local chart
helm install spicedb charts/spicedb \
  --namespace=spicedb \
  --values=production-postgres-values.yaml \
  --wait \
  --timeout=10m

# Watch the deployment
kubectl get pods -n spicedb --watch
```

**What happens during deployment**:

1. Helm creates all Kubernetes resources
2. Migration job runs to initialize database schema
3. SpiceDB pods start after migration completes
4. Service and endpoints become available

## Step 7: Verify Deployment

Verify all components are running correctly.

### Check Migration Job

```bash
# Check migration job completed successfully
kubectl get jobs -n spicedb -l app.kubernetes.io/component=migration

# View migration logs
kubectl logs -n spicedb -l app.kubernetes.io/component=migration

# Should see "migrations completed successfully"
```

### Check SpiceDB Pods

```bash
# Check SpiceDB pods are running
kubectl get pods -n spicedb -l app.kubernetes.io/name=spicedb

# Should show all pods in Running state with 1/1 ready

# Check pod logs
kubectl logs -n spicedb -l app.kubernetes.io/name=spicedb --tail=50

# Look for:
# - "datastore connected"
# - "grpc server listening on :50051"
# - No error messages
```

### Check Services

```bash
# Verify service is available
kubectl get svc -n spicedb

# Check endpoints have pod IPs
kubectl get endpoints -n spicedb

# Describe service for details
kubectl describe svc spicedb -n spicedb
```

## Step 8: Test Connectivity

Test that SpiceDB is accessible and responding to requests.

### Port-Forward and Test gRPC

```bash
# Port-forward to test gRPC connection
kubectl port-forward -n spicedb svc/spicedb 50051:50051
```

In another terminal:

```bash
# Install grpcurl if not already installed
# brew install grpcurl  # macOS
# apt-get install grpcurl  # Ubuntu/Debian

# Test with grpcurl (without TLS)
grpcurl -plaintext localhost:50051 list

# Should return list of services including:
# - authzed.api.v1.PermissionsService
# - authzed.api.v1.SchemaService
# - authzed.api.v1.WatchService
# - grpc.health.v1.Health
```

### Test with TLS

If TLS is enabled:

```bash
# Extract CA certificate
kubectl get secret -n spicedb spicedb-grpc-tls \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt

# Test with TLS
grpcurl -cacert ca.crt localhost:50051 list
```

### Test Health Check

```bash
# Test health endpoint
grpcurl -plaintext localhost:50051 grpc.health.v1.Health/Check

# Should return: { "status": "SERVING" }
```

### Test HTTP Metrics

```bash
# Port-forward HTTP port
kubectl port-forward -n spicedb svc/spicedb 8443:8443

# In another terminal, check metrics endpoint
curl http://localhost:8443/metrics

# Should return Prometheus metrics
```

## Complete Example

For a complete production-ready PostgreSQL configuration with all features enabled, see [examples/production-postgres.yaml](../../examples/production-postgres.yaml).

**Features included in complete example**:

- PostgreSQL datastore engine
- Automatic database migrations
- TLS for all endpoints (gRPC, HTTP, dispatch)
- External Secrets Operator integration
- High availability with 3 replicas
- Pod disruption budget
- Resource requests and limits
- Horizontal pod autoscaling
- Anti-affinity rules
- Topology spread constraints
- Prometheus metrics and ServiceMonitor

## Troubleshooting

### Migration Job Fails

**Problem**: Migration job fails to complete

**Solution**:

```bash
# Check migration job logs
kubectl logs -n spicedb -l app.kubernetes.io/component=migration

# Common issues:
# - Database connectivity: Verify network access and credentials
# - Database permissions: Ensure user has CREATE/ALTER permissions
# - Existing schema: Check if database already has incompatible schema
```

### Pods Not Starting

**Problem**: SpiceDB pods stuck in CrashLoopBackOff

**Solution**:

```bash
# Check pod logs
kubectl logs -n spicedb <pod-name>

# Common issues:
# - Secret not found: Verify spicedb-database secret exists
# - Invalid datastore URI: Check connection string format
# - TLS certificates missing: Verify certificate secrets exist
```

### Cannot Connect to Database

**Problem**: Logs show "failed to connect to datastore"

**Solution**:

```bash
# Verify database connectivity from pod
kubectl exec -n spicedb <pod-name> -- \
  psql "postgresql://spicedb:password@host:5432/spicedb?sslmode=require" \
  -c "SELECT 1;"

# Check:
# - Network connectivity (firewall rules, security groups)
# - DNS resolution (hostname resolves correctly)
# - Credentials (username/password correct)
# - SSL configuration (sslmode matches server config)
```

## Next Steps

After successful PostgreSQL deployment:

1. **Configure High Availability**: Enable [High Availability](high-availability.md) features for production
2. **Set Up Monitoring**: Configure Prometheus and Grafana dashboards
3. **Configure Backups**: Set up automated PostgreSQL backups
4. **Load Testing**: Perform load testing to validate performance
5. **Security Review**: Review and harden security configuration

**Navigation:** [← TLS Certificates](tls-certificates.md) | [Index](index.md) | [Next: High Availability →](high-availability.md)
