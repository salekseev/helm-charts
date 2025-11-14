# Migration Troubleshooting

**Navigation**: [Overview](./index.md) | [Prerequisites](./prerequisites.md) | [Migration Steps](./step-by-step.md) | [Configuration](./configuration-conversion.md) | [Post-Migration](./post-migration.md) | **Troubleshooting**

This guide covers migration-specific issues and their solutions.

## Issue: Helm pods crash with "secret not found"

**Symptoms:**

```bash
kubectl get pods -l app.kubernetes.io/name=spicedb
# NAME                       READY   STATUS             RESTARTS   AGE
# spicedb-xxxxx-yyyyy        0/1     CrashLoopBackOff   3          2m
```

**Diagnosis:**

```bash
kubectl logs spicedb-xxxxx-yyyyy

# Error: failed to load secret "spicedb-operator-config": secret not found
```

**Common Causes:**

Secret name in values.yaml doesn't match actual secret

**Resolution:**

```bash
# Check secret exists
kubectl get secret spicedb-operator-config

# If missing, check what secrets exist
kubectl get secrets

# Update values.yaml with correct secret name
# config:
#   existingSecret: <actual-secret-name>

# Upgrade Helm release
helm upgrade spicedb charts/spicedb -f values.yaml
```

## Issue: Helm and operator both trying to manage resources

**Symptoms:**

Pods being created/deleted repeatedly, services changing

**Diagnosis:**

```bash
kubectl get pods -l app.kubernetes.io/name=spicedb -o yaml | grep ownerReferences

# If both Helm and operator owner references exist, conflict
```

**Common Causes:**

SpiceDBCluster wasn't scaled to 0 before Helm install

**Resolution:**

```bash
# Scale SpiceDBCluster to 0
kubectl patch spicedbcluster spicedb --type=merge -p '{"spec":{"replicas":0}}'

# Wait for operator pods to be deleted
kubectl wait --for=delete pod -l app.kubernetes.io/name=spicedb --timeout=60s

# Delete and reinstall Helm release
helm uninstall spicedb
helm install spicedb charts/spicedb -f values.yaml
```

## Issue: NetworkPolicy blocks all traffic

**Symptoms:**

Clients can't connect after creating NetworkPolicy

**Diagnosis:**

```bash
# Check NetworkPolicy exists
kubectl get networkpolicy spicedb -o yaml

# Test connectivity
kubectl run -it --rm test --image=curlimages/curl -- \
  curl -v http://spicedb:50051
```

**Common Causes:**

NetworkPolicy is too restrictive or has wrong selectors

**Resolution:**

```bash
# Delete NetworkPolicy temporarily
kubectl delete networkpolicy spicedb

# Test if connectivity restored
# If yes, NetworkPolicy was the issue

# Recreate with correct configuration
# Ensure podSelector matches Helm pods
kubectl get pods -l app.kubernetes.io/name=spicedb --show-labels
```

## Issue: Ingress returns 404 or 503

**Symptoms:**

External requests fail through Ingress

**Diagnosis:**

```bash
# Check Ingress
kubectl get ingress spicedb -o yaml

# Check Ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100 | grep spicedb

# Check service endpoints
kubectl get endpoints spicedb
```

**Common Causes:**

1. Service name in Ingress doesn't match Helm service
2. Port numbers incorrect
3. Ingress annotations wrong for gRPC

**Resolution:**

```bash
# Verify service name
kubectl get svc -l app.kubernetes.io/name=spicedb

# Update Ingress backend to match
kubectl patch ingress spicedb --type=json -p='[
  {"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "spicedb"}
]'

# Ensure gRPC annotations for NGINX
kubectl annotate ingress spicedb \
  nginx.ingress.kubernetes.io/backend-protocol=GRPC \
  --overwrite
```

## Issue: Metrics not in Prometheus after migration

**Symptoms:**

Prometheus targets show no spicedb metrics

**Diagnosis:**

```bash
# Check ServiceMonitor
kubectl get servicemonitor spicedb

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="spicedb")'

# Manually test metrics endpoint
kubectl port-forward svc/spicedb 9090:9090 &
curl http://localhost:9090/metrics
```

**Common Causes:**

ServiceMonitor not created or has wrong labels

**Resolution:**

```bash
# Add ServiceMonitor to values.yaml
# monitoring:
#   serviceMonitor:
#     enabled: true
#     additionalLabels:
#       prometheus: kube-prometheus

# Upgrade Helm release
helm upgrade spicedb charts/spicedb -f values.yaml

# Verify ServiceMonitor created
kubectl get servicemonitor spicedb
```

## Issue: Database connection failures

**Symptoms:**

Pods fail to connect to database

**Diagnosis:**

```bash
# Check pod logs
kubectl logs -l app.kubernetes.io/name=spicedb --tail=50

# Look for database connection errors
# Error: failed to connect to database
```

**Common Causes:**

1. Database URI incorrect in secret
2. Database not accessible from new pods
3. NetworkPolicy blocking database access

**Resolution:**

```bash
# Verify database URI in secret
kubectl get secret spicedb-operator-config -o jsonpath='{.data.datastore-uri}' | base64 -d

# Test database connectivity from pod
kubectl run -it --rm db-test --image=postgres:15 --restart=Never -- \
  psql "$DATASTORE_URI" -c "SELECT 1;"

# If NetworkPolicy is blocking, add egress rule for database
# See post-migration.md for NetworkPolicy configuration
```

## Issue: TLS certificate errors

**Symptoms:**

TLS handshake failures in logs

**Diagnosis:**

```bash
# Check pod logs
kubectl logs -l app.kubernetes.io/name=spicedb | grep -i tls

# Check TLS secret exists
kubectl get secret spicedb-grpc-tls
```

**Common Causes:**

1. TLS secret not found
2. Wrong secret name in values.yaml
3. Certificate expired or invalid

**Resolution:**

```bash
# Verify TLS secret has correct keys
kubectl get secret spicedb-grpc-tls -o jsonpath='{.data}' | jq 'keys'

# Expected keys: ["tls.crt", "tls.key", "ca.crt"]

# Update values.yaml with correct secret name
# tls:
#   enabled: true
#   grpc:
#     secretName: spicedb-grpc-tls

# Upgrade Helm release
helm upgrade spicedb charts/spicedb -f values.yaml
```

## Issue: Migration job doesn't complete

**Symptoms:**

Migration job stays in Running state indefinitely

**Diagnosis:**

```bash
# Check migration job
kubectl get job -l app.kubernetes.io/name=spicedb

# Check migration pod logs
kubectl logs -l app.kubernetes.io/name=spicedb,job-name=spicedb-migration
```

**Common Causes:**

1. Database not accessible
2. Schema migration failing
3. Job timeout too short

**Resolution:**

```bash
# Delete failed migration job
kubectl delete job -l app.kubernetes.io/name=spicedb

# Increase migration timeout in values.yaml
# migrations:
#   enabled: true
#   activeDeadlineSeconds: 600

# Upgrade Helm release
helm upgrade spicedb charts/spicedb -f values.yaml
```

## General Debugging Steps

### Check Pod Status

```bash
# Get pod details
kubectl get pods -l app.kubernetes.io/name=spicedb -o wide

# Describe pod for events
kubectl describe pod -l app.kubernetes.io/name=spicedb

# Check logs
kubectl logs -l app.kubernetes.io/name=spicedb --tail=100 --all-containers=true
```

### Verify Helm Release

```bash
# Check Helm status
helm status spicedb

# Get Helm values
helm get values spicedb

# List Helm resources
helm get manifest spicedb | kubectl get -f -
```

### Check Resource Events

```bash
# Get recent events
kubectl get events --sort-by='.lastTimestamp' | grep spicedb

# Watch events in real-time
kubectl get events -w | grep spicedb
```

## Need More Help?

If these solutions don't resolve your issue:

1. **Review Migration Steps**: [Step-by-Step Guide](./step-by-step.md)
2. **Check Configuration**: [Configuration Conversion](./configuration-conversion.md)
3. **Get Support**:
   - GitHub Issues: <https://github.com/salekseev/helm-charts/issues>
   - SpiceDB Discord: <https://authzed.com/discord>

**Navigation**: [Overview](./index.md) | [Prerequisites](./prerequisites.md) | [Migration Steps](./step-by-step.md) | [Configuration](./configuration-conversion.md) | [Post-Migration](./post-migration.md) | **Troubleshooting**
