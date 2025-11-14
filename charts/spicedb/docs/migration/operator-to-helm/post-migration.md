# Post-Migration Enhancements

**Navigation**: [Overview](./index.md) | [Prerequisites](./prerequisites.md) | [Migration Steps](./step-by-step.md) | [Configuration](./configuration-conversion.md) | **Post-Migration** | [Troubleshooting](../../guides/troubleshooting/index.md)

This guide covers enhancements and features you can add after migrating to Helm. These are features that the operator didn't provide.

## 1. Add NetworkPolicy for Security

NetworkPolicy provides network isolation and security controls for your SpiceDB deployment.

### Option A: Create Standalone NetworkPolicy

Create `spicedb-networkpolicy.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: spicedb
  namespace: default
  labels:
    app.kubernetes.io/name: spicedb
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: spicedb
  policyTypes:
  - Ingress
  - Egress

  ingress:
  # Allow from ingress controller
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
    ports:
    - protocol: TCP
      port: 50051  # gRPC
    - protocol: TCP
      port: 8443   # HTTP

  # Allow from Prometheus
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: monitoring
    ports:
    - protocol: TCP
      port: 9090  # Metrics

  # Allow inter-pod dispatch communication
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: spicedb
    ports:
    - protocol: TCP
      port: 50053  # Dispatch

  egress:
  # Allow to PostgreSQL
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: database
    ports:
    - protocol: TCP
      port: 5432  # PostgreSQL (or 26257 for CockroachDB)

  # Allow DNS
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
```

Apply the NetworkPolicy:

```bash
kubectl apply -f spicedb-networkpolicy.yaml

# Verify NetworkPolicy
kubectl get networkpolicy spicedb
kubectl describe networkpolicy spicedb
```

### Option B: Enable in values.yaml

Add to your `values.yaml`:

```yaml
networkPolicy:
  enabled: true
  ingressControllerNamespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: ingress-nginx
  prometheusNamespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: monitoring
  databaseEgress:
    ports:
    - protocol: TCP
      port: 5432
    to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: database
```

Then upgrade:

```bash
helm upgrade spicedb charts/spicedb -f values.yaml
```

## 2. Configure Ingress for External Access

Ingress provides external access to your SpiceDB deployment with TLS termination and path-based routing.

### Option A: Create Standalone Ingress

Create `spicedb-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: spicedb
  namespace: default
  annotations:
    # Automatic TLS with cert-manager
    cert-manager.io/cluster-issuer: letsencrypt-prod

    # NGINX-specific configuration for gRPC
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/grpc-backend: "true"
spec:
  ingressClassName: nginx

  rules:
  # gRPC API endpoint
  - host: api.spicedb.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: spicedb
            port:
              number: 50051

  # Metrics endpoint (separate subdomain)
  - host: metrics.spicedb.example.com
    http:
      paths:
      - path: /metrics
        pathType: Exact
        backend:
          service:
            name: spicedb
            port:
              number: 9090

  tls:
  - secretName: spicedb-api-tls
    hosts:
    - api.spicedb.example.com
  - secretName: spicedb-metrics-tls
    hosts:
    - metrics.spicedb.example.com
```

Apply the Ingress:

```bash
kubectl apply -f spicedb-ingress.yaml

# Verify Ingress
kubectl get ingress spicedb
kubectl describe ingress spicedb

# Test external access
grpcurl -d '{"service":"authzed.api.v1.SchemaService"}' \
  api.spicedb.example.com:443 grpc.health.v1.Health/Check
```

### Option B: Enable in values.yaml

Add to your `values.yaml`:

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/backend-protocol: "GRPC"
  hosts:
  - host: api.spicedb.example.com
    paths:
    - path: /
      pathType: Prefix
      servicePort: grpc
  tls:
  - secretName: spicedb-api-tls
    hosts:
    - api.spicedb.example.com
```

Then upgrade:

```bash
helm upgrade spicedb charts/spicedb -f values.yaml
```

## 3. Add ServiceMonitor for Prometheus

ServiceMonitor enables automatic Prometheus scraping of SpiceDB metrics.

### Option A: Create Standalone ServiceMonitor

Create `spicedb-servicemonitor.yaml`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: spicedb
  namespace: default
  labels:
    app.kubernetes.io/name: spicedb
    prometheus: kube-prometheus  # Match your Prometheus selector
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: spicedb

  endpoints:
  - port: metrics
    interval: 30s
    scrapeTimeout: 10s
    path: /metrics
    scheme: http
```

Apply the ServiceMonitor:

```bash
kubectl apply -f spicedb-servicemonitor.yaml

# Verify ServiceMonitor
kubectl get servicemonitor spicedb

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="spicedb")'
```

### Option B: Enable in values.yaml

Add to your `values.yaml`:

```yaml
monitoring:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
    additionalLabels:
      prometheus: kube-prometheus
```

Then upgrade:

```bash
helm upgrade spicedb charts/spicedb -f values.yaml
```

## 4. Enable HorizontalPodAutoscaler

HorizontalPodAutoscaler automatically scales SpiceDB pods based on CPU/memory utilization.

Add to `values.yaml`:

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80
```

Upgrade and verify:

```bash
helm upgrade spicedb charts/spicedb -f values.yaml

# Verify HPA
kubectl get hpa spicedb
kubectl describe hpa spicedb

# Watch HPA autoscaling
kubectl get hpa spicedb -w
```

## Verification

After adding enhancements, verify everything is working:

```bash
# Check all resources
kubectl get all,networkpolicy,ingress,servicemonitor -l app.kubernetes.io/name=spicedb

# Test connectivity through Ingress (if configured)
grpcurl -d '{"service":"authzed.api.v1.SchemaService"}' \
  api.spicedb.example.com:443 grpc.health.v1.Health/Check

# Verify NetworkPolicy allows expected traffic
kubectl run -it --rm test --image=curlimages/curl -- \
  curl -v http://spicedb:50051

# Check Prometheus metrics (if ServiceMonitor configured)
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="spicedb")'
```

## Next Steps

If you encounter issues:

- **[Review Troubleshooting](../../guides/troubleshooting/index.md)** - Common post-migration issues

**Navigation**: [Overview](./index.md) | [Prerequisites](./prerequisites.md) | [Migration Steps](./step-by-step.md) | [Configuration](./configuration-conversion.md) | **Post-Migration** | [Troubleshooting](../../guides/troubleshooting/index.md)
