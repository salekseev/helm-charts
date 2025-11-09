# SpiceDB Helm Chart Examples

This directory contains example values files demonstrating various SpiceDB deployment configurations.

## Ingress Examples

### Multi-Host with Multiple TLS Configurations

**File:** `ingress-multi-host-tls.yaml`

Demonstrates a production-ready setup with:
- Multiple dedicated hosts (API, metrics, dispatch)
- Path-based routing to different service ports
- Separate TLS certificates for different host groups
- cert-manager integration for automated certificate management
- NGINX Ingress Controller with gRPC support

**Use case:** Large-scale deployments requiring separation of concerns, different access controls per service, or compliance requirements for certificate isolation.

```bash
helm install spicedb authzed/spicedb -f examples/ingress-multi-host-tls.yaml
```

### TLS Passthrough (End-to-End Encryption)

**File:** `ingress-tls-passthrough.yaml`

Demonstrates end-to-end encryption where:
- TLS terminates at SpiceDB, not at the ingress controller
- Ingress controller forwards encrypted traffic (no decryption)
- Provides maximum security for regulatory compliance
- Uses NGINX SSL passthrough annotations

**Use case:** Highly regulated environments requiring end-to-end encryption, PCI DSS compliance, or when ingress controller should not have access to decrypted traffic.

```bash
helm install spicedb authzed/spicedb -f examples/ingress-tls-passthrough.yaml
```

**Prerequisites:**
- SpiceDB TLS certificates must be configured (see chart's `tls.*` values)
- NGINX Ingress Controller must have `--enable-ssl-passthrough` flag enabled

### Single Host with Multiple Paths

**File:** `ingress-single-host-multi-path.yaml`

Demonstrates path-based routing on a single hostname:
- All services accessible via different paths on one domain
- Simplified DNS management (single hostname)
- Single TLS certificate for all paths
- Mixed pathType usage (Prefix and Exact)

**Use case:** Development environments, simplified deployments, or cost-conscious setups wanting to minimize DNS entries and certificates.

```bash
helm install spicedb authzed/spicedb -f examples/ingress-single-host-multi-path.yaml
```

### Contour Ingress Controller

**File:** `ingress-contour-grpc.yaml`

Demonstrates Contour-specific configuration:
- H2C (HTTP/2 Cleartext) protocol for gRPC
- Contour annotations for timeout management
- Multi-host setup with separate TLS per host

**Use case:** Clusters using Contour as the ingress controller, especially in VMware Tanzu environments.

```bash
helm install spicedb authzed/spicedb -f examples/ingress-contour-grpc.yaml
```

### Traefik Ingress Controller

**File:** `ingress-traefik-grpc.yaml`

Demonstrates Traefik-specific configuration:
- Traefik entrypoints and router configuration
- H2C scheme for gRPC support
- TLS configuration via Traefik annotations

**Use case:** Clusters using Traefik as the ingress controller.

```bash
helm install spicedb authzed/spicedb -f examples/ingress-traefik-grpc.yaml
```

## Testing Examples

### Validate Template Rendering

Test any example configuration without installing:

```bash
helm template spicedb . -f examples/ingress-multi-host-tls.yaml
```

Show only the ingress resource:

```bash
helm template spicedb . -f examples/ingress-multi-host-tls.yaml --show-only templates/ingress.yaml
```

### Dry Run Install

Simulate installation to verify configuration:

```bash
helm install spicedb authzed/spicedb -f examples/ingress-multi-host-tls.yaml --dry-run --debug
```

## Common Configuration Patterns

### Available Service Ports

SpiceDB exposes multiple ports that can be routed via Ingress:

| Port Name | Port Number | Purpose | Protocol |
|-----------|-------------|---------|----------|
| `grpc` | 50051 | Main gRPC API | gRPC |
| `http` | 8443 | Dashboard, health checks | HTTP |
| `metrics` | 9090 | Prometheus metrics | HTTP |
| `dispatch` | 50053 | Cluster communication | gRPC |

### Path Types

Kubernetes Ingress supports three path types:

- **Prefix**: Matches path prefix (e.g., `/api` matches `/api`, `/api/v1`, `/api/anything`)
- **Exact**: Matches exact path only (e.g., `/metrics` matches only `/metrics`)
- **ImplementationSpecific**: Ingress controller-specific behavior

### TLS Configuration Options

#### 1. TLS Termination at Ingress (Default)

Ingress controller terminates TLS, backends use unencrypted HTTP/gRPC:

```yaml
ingress:
  tls:
    - secretName: spicedb-tls
      hosts:
        - spicedb.example.com
```

#### 2. TLS Passthrough

Ingress controller forwards encrypted traffic, SpiceDB terminates TLS:

```yaml
tls:
  enabled: true
  grpc:
    secretName: spicedb-grpc-tls

ingress:
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "GRPCS"
  tls:
    - hosts:
        - spicedb.example.com
```

#### 3. cert-manager Integration

Automated certificate management with cert-manager:

```yaml
ingress:
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
  tls:
    - secretName: spicedb-tls  # cert-manager creates this
      hosts:
        - spicedb.example.com
```

### Multi-Host vs Single-Host Decision Matrix

| Factor | Multi-Host | Single-Host |
|--------|------------|-------------|
| DNS entries | Multiple | Single |
| TLS certificates | Can be separate | Single cert |
| Access control | Per-host policies | Path-based policies |
| Cost | Higher (multiple certs/DNS) | Lower |
| Complexity | Higher | Lower |
| Use case | Production, compliance | Development, simple setups |

## Prerequisites

### Required

- Kubernetes 1.19+ (networking.k8s.io/v1 API)
- Ingress controller installed (NGINX, Contour, or Traefik)
- DNS records pointing to ingress controller

### Optional

- **cert-manager**: For automated TLS certificate management
- **ExternalDNS**: For automated DNS record management
- **NGINX Ingress Controller with SSL passthrough**: For TLS passthrough examples

### Installing cert-manager

If using cert-manager examples:

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
```

Create a ClusterIssuer:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

## Troubleshooting

### gRPC Endpoints Not Working

Ensure backend protocol annotation is set:

```yaml
annotations:
  nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
  nginx.ingress.kubernetes.io/grpc-backend: "true"
```

### TLS Passthrough Not Working

1. Verify NGINX Ingress Controller has passthrough enabled:
   ```bash
   kubectl get deployment nginx-ingress-controller -o yaml | grep ssl-passthrough
   ```

2. Check if `--enable-ssl-passthrough` flag is present

3. Verify SpiceDB has TLS configured (`tls.grpc.secretName`)

### Certificate Issues with cert-manager

Check certificate status:

```bash
kubectl get certificate
kubectl describe certificate spicedb-tls
```

Check cert-manager logs:

```bash
kubectl logs -n cert-manager -l app=cert-manager
```

### Path Routing Not Working

1. Verify pathType is appropriate for your use case
2. Check ingress controller logs for routing decisions
3. Test with curl:
   ```bash
   curl -v https://spicedb.example.com/metrics
   ```

## Additional Resources

- [SpiceDB Documentation](https://authzed.com/docs)
- [Kubernetes Ingress Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [NGINX Ingress Controller Documentation](https://kubernetes.github.io/ingress-nginx/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Contour Documentation](https://projectcontour.io/docs/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
