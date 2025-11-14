# Network Security

This guide covers network-level security controls for SpiceDB deployments, including NetworkPolicy, service mesh integration, and firewall configuration.

## NetworkPolicy

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

## What NetworkPolicy Provides

- **Namespace isolation**: Only allowed namespaces can access SpiceDB
- **Pod-level access control**: Only specific pods can connect
- **Egress control**: Limit outbound connections
- **Defense in depth**: Network-level security complements application security

## Production NetworkPolicy Example

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

## NetworkPolicy Verification

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

## Service Mesh Integration

For advanced traffic management and security, integrate with a service mesh:

### Istio Example

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

### Service Mesh Benefits

- Automatic mTLS between services
- Fine-grained authorization policies
- Traffic encryption without application changes
- Observability and tracing

### Linkerd Example

```yaml
# Enable mTLS for SpiceDB namespace
apiVersion: v1
kind: Namespace
metadata:
  name: spicedb
  annotations:
    linkerd.io/inject: enabled

---
# Server authorization policy
apiVersion: policy.linkerd.io/v1beta1
kind: Server
metadata:
  name: spicedb-grpc
  namespace: spicedb
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: spicedb
  port: grpc
  proxyProtocol: gRPC

---
# Authorization policy
apiVersion: policy.linkerd.io/v1beta1
kind: ServerAuthorization
metadata:
  name: spicedb-grpc-authz
  namespace: spicedb
spec:
  server:
    name: spicedb-grpc
  client:
    meshTLS:
      serviceAccounts:
      - name: application-sa
        namespace: application
      - name: ingress-nginx
        namespace: ingress-nginx
```

## Firewall and Network Segmentation

### Cloud Provider Security Groups

#### AWS Security Groups

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

  # Allow DNS
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "spicedb-security-group"
  }
}
```

#### GCP Firewall Rules

```hcl
# Allow gRPC from application tier
resource "google_compute_firewall" "spicedb_grpc" {
  name    = "spicedb-grpc-ingress"
  network = var.network_name

  allow {
    protocol = "tcp"
    ports    = ["50051"]
  }

  source_ranges = [var.application_subnet_cidr]
  target_tags   = ["spicedb"]
}

# Allow metrics from monitoring
resource "google_compute_firewall" "spicedb_metrics" {
  name    = "spicedb-metrics-ingress"
  network = var.network_name

  allow {
    protocol = "tcp"
    ports    = ["9090"]
  }

  source_ranges = [var.monitoring_subnet_cidr]
  target_tags   = ["spicedb"]
}

# Allow egress to database
resource "google_compute_firewall" "spicedb_database_egress" {
  name      = "spicedb-database-egress"
  network   = var.network_name
  direction = "EGRESS"

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  destination_ranges = [var.database_subnet_cidr]
  target_tags        = ["spicedb"]
}
```

#### Azure Network Security Groups

```hcl
resource "azurerm_network_security_group" "spicedb" {
  name                = "spicedb-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Allow gRPC from application tier
  security_rule {
    name                       = "AllowgRPC"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "50051"
    source_address_prefix      = var.application_subnet_cidr
    destination_address_prefix = "*"
  }

  # Allow metrics from monitoring
  security_rule {
    name                       = "AllowMetrics"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9090"
    source_address_prefix      = var.monitoring_subnet_cidr
    destination_address_prefix = "*"
  }

  # Allow egress to database
  security_rule {
    name                       = "AllowDatabaseEgress"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "*"
    destination_address_prefix = var.database_subnet_cidr
  }
}
```

## Network Segmentation Best Practices

### 1. Use Private Subnets

Deploy SpiceDB in private subnets without direct internet access:

```yaml
# AWS example
subnets:
  - subnet-private-1a
  - subnet-private-1b
  - subnet-private-1c
```

### 2. Implement Network Tiers

- **Application tier**: Separate subnet for application workloads
- **Database tier**: Isolated subnet for databases
- **Management tier**: Separate subnet for monitoring/operations

### 3. Use VPC Peering or Transit Gateway

For multi-cluster deployments:

- Connect clusters via VPC peering or transit gateway
- Apply firewall rules at peering level
- Limit cross-cluster traffic to required services only

### 4. Enable Flow Logs

Monitor network traffic for security analysis:

```bash
# AWS VPC Flow Logs
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-xxxxx \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs

# GCP VPC Flow Logs (enabled per subnet)
gcloud compute networks subnets update SUBNET_NAME \
  --enable-flow-logs \
  --region=REGION
```

## Advanced Network Security

### DNS Security

Restrict DNS to internal resolvers:

```yaml
# CoreDNS policy
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  spicedb.server: |
    spicedb.svc.cluster.local {
      forward . 10.0.0.10
      cache 30
    }
```

### Private Link / PrivateLink

Use cloud provider private endpoints for database access:

```yaml
# AWS PrivateLink example
config:
  datastoreEngine: postgres
  datastore:
    uri: postgresql://user:pass@vpce-xxxxx.vpce-svc-xxxxx.region.vpce.amazonaws.com:5432/db
```

### Network Policies for Multi-Tenancy

Isolate multiple SpiceDB deployments:

```yaml
# Namespace 1
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: spicedb-tenant1
  namespace: spicedb-tenant1
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: spicedb
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          tenant: tenant1

# Namespace 2
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: spicedb-tenant2
  namespace: spicedb-tenant2
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: spicedb
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          tenant: tenant2
```

## Troubleshooting Network Issues

### Test Network Connectivity

```bash
# Test from within cluster
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  curl -v https://spicedb.spicedb:50051

# Test DNS resolution
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  nslookup spicedb.spicedb.svc.cluster.local

# Test with specific protocol
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  grpcurl -plaintext spicedb.spicedb:50051 list
```

### Debug NetworkPolicy

```bash
# Check if NetworkPolicy is applied
kubectl get networkpolicy -n spicedb -o yaml

# View effective policies
kubectl describe networkpolicy spicedb -n spicedb

# Check pod labels
kubectl get pods -n spicedb --show-labels
```

## Additional Resources

- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Istio Security](https://istio.io/latest/docs/concepts/security/)
- [Linkerd Authorization Policy](https://linkerd.io/2/features/server-policy/)
- [AWS VPC Security](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Security.html)
- [GCP VPC Security](https://cloud.google.com/vpc/docs/vpc)
