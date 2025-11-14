# Infrastructure Setup

This guide covers infrastructure preparation for SpiceDB production deployments, including database provisioning, network configuration, and storage setup.

**Navigation:** [Index](index.md) | [Next: TLS Certificates →](tls-certificates.md)

## Table of Contents

- [Database Provisioning](#database-provisioning)
  - [PostgreSQL Setup](#postgresql-setup)
  - [CockroachDB Setup](#cockroachdb-setup)
- [Network Requirements](#network-requirements)
  - [Network Connectivity](#network-connectivity)
  - [Firewall Rules](#firewall-rules)
  - [DNS Resolution](#dns-resolution)
- [Storage Considerations](#storage-considerations)
  - [Database Storage](#database-storage)
  - [Kubernetes Storage](#kubernetes-storage)

## Database Provisioning

### PostgreSQL Setup

#### 1. Create a Dedicated Database Instance

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

**Cloud Provider Examples:**

**Google Cloud SQL:**

```bash
gcloud sql instances create spicedb-postgres \
  --database-version=POSTGRES_15 \
  --tier=db-custom-2-8192 \
  --region=us-central1 \
  --storage-size=100GB \
  --storage-type=SSD \
  --storage-auto-increase \
  --backup-start-time=03:00 \
  --enable-bin-log \
  --no-assign-ip
```

**Azure Database for PostgreSQL:**

```bash
az postgres flexible-server create \
  --name spicedb-postgres \
  --resource-group spicedb-rg \
  --location eastus \
  --admin-user spicedb \
  --admin-password 'CHANGE_ME_SECURE_PASSWORD' \
  --sku-name Standard_D2s_v3 \
  --tier GeneralPurpose \
  --storage-size 128 \
  --version 15 \
  --high-availability Enabled
```

#### 2. Create the SpiceDB Database

```bash
# Connect to PostgreSQL
psql -h postgres-host.rds.amazonaws.com -U spicedb -d postgres

# Create database
CREATE DATABASE spicedb;

# Grant permissions
GRANT ALL PRIVILEGES ON DATABASE spicedb TO spicedb;
```

#### 3. Enable SSL/TLS (Recommended)

```sql
-- Verify SSL is enabled
SHOW ssl;

-- Should return "on"
```

For managed services, SSL/TLS is typically enabled by default. Verify with:

```bash
# Test SSL connection
psql "postgresql://spicedb:password@host:5432/spicedb?sslmode=require"
```

### CockroachDB Setup

#### 1. Create a CockroachDB Cluster

**Option A: Using CockroachDB Kubernetes Operator**

```bash
# Install CockroachDB Operator
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

**Option B: Using Helm Chart**

```bash
# Add CockroachDB Helm repository
helm repo add cockroachdb https://charts.cockroachdb.com/
helm repo update

# Install CockroachDB
helm install cockroachdb cockroachdb/cockroachdb \
  --namespace database \
  --create-namespace \
  --set statefulset.replicas=3 \
  --set storage.persistentVolume.size=100Gi \
  --set tls.enabled=true
```

**Option C: CockroachDB Cloud (Managed Service)**

```bash
# Create cluster using CockroachDB Cloud Console or CLI
cockroach-cloud cluster create spicedb-cluster \
  --cloud gcp \
  --region us-east1 \
  --nodes 3 \
  --tier standard
```

#### 2. Create the SpiceDB Database and User

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

#### 3. Generate Client Certificates

CockroachDB requires TLS for production deployments. See the [TLS Certificates](tls-certificates.md) guide for detailed certificate generation instructions.

## Network Requirements

### Network Connectivity

Ensure Kubernetes pods can reach the database before deploying SpiceDB.

#### Test PostgreSQL Connectivity

```bash
# Test database connectivity from a pod
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql "postgresql://spicedb:password@postgres-host:5432/spicedb?sslmode=require"

# Should connect successfully and show psql prompt
```

#### Test CockroachDB Connectivity

```bash
# For CockroachDB
kubectl run -it --rm debug --image=cockroachdb/cockroach:latest --restart=Never -- \
  sql --url "postgresql://spicedb:password@cockroachdb-public.database:26257/spicedb?sslmode=verify-full"

# Should connect and show SQL prompt
```

### Firewall Rules

Configure security groups/firewall rules to allow database access from Kubernetes cluster.

#### PostgreSQL Firewall Rules

**AWS Security Group Example:**

```bash
# Allow PostgreSQL access from Kubernetes node CIDR
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 5432 \
  --source-group sg-kubernetes-nodes

# Or use CIDR range
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 5432 \
  --cidr 10.0.0.0/16
```

**GCP Firewall Rule Example:**

```bash
gcloud compute firewall-rules create allow-postgres-from-gke \
  --allow tcp:5432 \
  --source-ranges 10.0.0.0/16 \
  --target-tags postgres-instance
```

**Azure Network Security Group:**

```bash
az network nsg rule create \
  --resource-group spicedb-rg \
  --nsg-name postgres-nsg \
  --name allow-postgres \
  --priority 100 \
  --source-address-prefixes 10.0.0.0/16 \
  --destination-port-ranges 5432 \
  --access Allow \
  --protocol Tcp
```

#### CockroachDB Firewall Rules

- **SQL Port (26257)**: Allow inbound TCP 26257 from Kubernetes node CIDR ranges
- **Admin UI (8080)**: Allow inbound TCP 8080 from admin networks (optional)
- **Inter-node Communication**: Allow TCP 26257 between CockroachDB nodes
- Deny all other inbound traffic

```bash
# Example GCP firewall rule for CockroachDB
gcloud compute firewall-rules create allow-cockroachdb-sql \
  --allow tcp:26257 \
  --source-ranges 10.0.0.0/16 \
  --target-tags cockroachdb
```

### DNS Resolution

Verify DNS resolution works from within the cluster.

#### Test External Database DNS

```bash
# Test DNS resolution for external PostgreSQL
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup postgres-host.rds.amazonaws.com

# Should return IP address
```

#### Test In-Cluster Database DNS

```bash
# For in-cluster database (CockroachDB)
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup cockroachdb-public.database.svc.cluster.local

# Should return service cluster IP
```

#### Common DNS Issues

**Problem**: DNS resolution fails for external databases

**Solution**: Ensure Kubernetes DNS service is working and can resolve external names:

```bash
# Check CoreDNS is running
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup google.com
```

## Storage Considerations

### Database Storage

#### PostgreSQL Storage Best Practices

**Storage Type:**

- Use SSD-backed storage (gp3 on AWS, pd-ssd on GCP, Premium SSD on Azure)
- Provision IOPS based on expected workload (minimum 3000 IOPS)
- Enable automated backups (7-30 day retention recommended)
- Consider read replicas for read-heavy workloads

**Storage Sizing:**

```bash
# AWS RDS storage configuration
--storage-type gp3 \
--allocated-storage 100 \
--iops 3000 \
--storage-throughput 125 \
--max-allocated-storage 1000  # Enable autoscaling
```

**Backup Configuration:**

```bash
# Enable automated backups
--backup-retention-period 7 \
--preferred-backup-window "03:00-04:00" \
--backup-target region
```

#### CockroachDB Storage Best Practices

**Storage Type:**

- Use local SSD storage for best performance
- Provision 2-3x expected data size for compaction overhead
- Enable incremental backups to S3/GCS
- Use separate storage class for production workloads

**Storage Class Example:**

```yaml
# fast-ssd storage class for CockroachDB
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: kubernetes.io/gce-pd
parameters:
  type: pd-ssd
  replication-type: regional-pd
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

**Backup Configuration:**

```sql
-- Configure automatic backups to cloud storage
CREATE SCHEDULE backup_daily
  FOR BACKUP DATABASE spicedb INTO 's3://backups/spicedb?AWS_ACCESS_KEY_ID=xxx&AWS_SECRET_ACCESS_KEY=xxx'
  RECURRING '@daily'
  WITH SCHEDULE OPTIONS first_run = 'now';
```

### Kubernetes Storage

SpiceDB itself is stateless and does not require persistent volumes. However, consider these storage configurations:

#### EmptyDir for Temporary Files

```yaml
# Example in values.yaml
volumes:
- name: tmp
  emptyDir: {}

volumeMounts:
- name: tmp
  mountPath: /tmp
```

#### Ephemeral Volumes (Recommended for Production)

```yaml
# Using ephemeral volumes for /tmp
securityContext:
  readOnlyRootFilesystem: true

volumes:
- name: tmp
  ephemeral:
    volumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

**Note**: Persistent volumes are **NOT** required for SpiceDB pods. All state is stored in the external database.

## Next Steps

After completing infrastructure setup:

1. **Configure TLS Certificates**: Proceed to [TLS Certificates](tls-certificates.md) to secure your deployment
2. **Choose Database Path**: Follow either [PostgreSQL Deployment](postgresql-deployment.md) or [CockroachDB Deployment](cockroachdb-deployment.md)
3. **Enable High Availability**: Configure [High Availability](high-availability.md) features

**Navigation:** [Index](index.md) | [Next: TLS Certificates →](tls-certificates.md)
