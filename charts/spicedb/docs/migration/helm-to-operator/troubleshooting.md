# Migration Troubleshooting

This document provides solutions for common issues encountered during migration
from Helm to SpiceDB Operator.

## Navigation

- [Overview](./index.md)
- [Prerequisites](./prerequisites.md)
- [Step-by-Step Migration](./step-by-step.md)
- [Configuration Conversion](./configuration-conversion.md)
- [Post-Migration Validation](./post-migration.md)
- **Troubleshooting** (this page)

## Issue: SpiceDBCluster stuck in "Pending" status

### Symptoms

```bash
kubectl get spicedbcluster spicedb
# NAME      READY   STATUS    AGE
# spicedb   False   Pending   5m
```

### Diagnosis

```bash
# Check operator logs
kubectl logs -n spicedb-operator-system -l control-plane=controller-manager --tail=100

# Check SpiceDBCluster events
kubectl describe spicedbcluster spicedb
```

### Common Causes

#### 1. Invalid secret reference

Secret doesn't exist or has wrong keys.

```bash
# Verify secret exists
kubectl get secret spicedb-operator-config

# Check secret has required keys
kubectl get secret spicedb-operator-config -o jsonpath='{.data}' | jq 'keys'
# Expected: ["datastore-uri", "preshared-key"]
```

**Resolution:**

```bash
# Create correct secret
kubectl create secret generic spicedb-operator-config \
  --from-literal=preshared-key="your-key-here" \
  --from-literal=datastore-uri="postgresql://..." \
  --dry-run=client -o yaml | kubectl apply -f -
```

#### 2. Invalid version

Version doesn't exist or is incompatible.

```bash
# Check available versions at https://github.com/authzed/spicedb/releases
# Update spec.version to valid version
```

**Resolution:**

Update `spec.version` in your SpiceDBCluster manifest to a valid version.

#### 3. Database connection failure

Can't connect to datastore.

```bash
# Test database connection from cluster
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql "$DATASTORE_URI"
```

**Resolution:**

Fix database connectivity issues (network, credentials, etc.) and operator will
retry automatically.

## Issue: Pods crash-looping after migration

### Symptoms

```bash
kubectl get pods -l app.kubernetes.io/name=spicedb
# NAME        READY   STATUS             RESTARTS   AGE
# spicedb-0   0/1     CrashLoopBackOff   5          5m
```

### Diagnosis

```bash
# Check pod logs
kubectl logs spicedb-0 --previous

# Check pod events
kubectl describe pod spicedb-0
```

### Common Causes

#### 1. Missing secret

Preshared key or datastore URI not found.

```bash
# Check logs for error like:
# "failed to load secret"

# Verify secret exists and is referenced correctly
kubectl get secret spicedb-operator-config
```

**Resolution:**

Ensure the secret exists and contains the required keys:

```bash
kubectl create secret generic spicedb-operator-config \
  --from-literal=preshared-key="your-key" \
  --from-literal=datastore-uri="postgresql://..." \
  --dry-run=client -o yaml | kubectl apply -f -
```

#### 2. Database migration failure

Migration failed during startup.

```bash
# Check logs for migration errors
kubectl logs spicedb-0 | grep -i migration

# Manually run migration to see error
kubectl run -it --rm spicedb-migrate \
  --image=authzed/spicedb:v1.35.0 \
  --restart=Never -- \
  migrate head --datastore-engine postgres --datastore-conn-uri "$DATASTORE_URI"
```

**Resolution:**

Fix database schema issues or permissions, then delete pod to restart.

#### 3. TLS certificate issues

Invalid or missing TLS certificates.

```bash
# Check TLS secret exists
kubectl get secret spicedb-grpc-tls

# Verify certificate is valid
kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

**Resolution:**

Ensure TLS secret exists and contains valid certificates:

```bash
# Check required keys
kubectl get secret spicedb-grpc-tls -o jsonpath='{.data}' | jq 'keys'
# Expected: ["tls.crt", "tls.key", "ca.crt"]
```

## Issue: Service ports don't match

### Symptoms

Clients can't connect using same port as before migration.

### Diagnosis

```bash
# Check operator-created service
kubectl get svc spicedb -o yaml

# Compare to Helm service backup
diff <(kubectl get svc spicedb -o yaml) service-backup.yaml
```

### Common Causes

Operator creates service with standard ports that may differ from Helm
customization.

### Resolution

**Option 1:** Update client configuration to use new ports

**Option 2:** Patch service to use original ports

```bash
kubectl patch svc spicedb --type=json -p='[
  {"op": "replace", "path": "/spec/ports/0/port", "value": 50051}
]'
```

**Option 3:** Create a separate service with original ports

```yaml
apiVersion: v1
kind: Service
metadata:
  name: spicedb-custom
spec:
  selector:
    app.kubernetes.io/name: spicedb
  ports:
  - name: grpc
    port: 50051  # Your custom port
    targetPort: 50051
```

## Issue: NetworkPolicy blocks traffic after migration

### Symptoms

Clients can't connect even though pods are ready.

### Diagnosis

```bash
# Check if NetworkPolicy exists
kubectl get networkpolicy spicedb

# Test connectivity
kubectl run -it --rm test --image=curlimages/curl -- \
  curl -v --max-time 5 http://spicedb:50051
```

### Common Causes

NetworkPolicy from Helm may not match operator-created pod labels.

### Resolution

```bash
# Check pod labels created by operator
kubectl get pods -l app.kubernetes.io/name=spicedb --show-labels

# Update NetworkPolicy podSelector to match
kubectl edit networkpolicy spicedb

# Or recreate NetworkPolicy with correct labels
```

Ensure your NetworkPolicy `podSelector` matches the operator's pod labels:

```yaml
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: spicedb
```

## Issue: Ingress returns 503 after migration

### Symptoms

External clients get 503 Service Unavailable.

### Diagnosis

```bash
# Check Ingress configuration
kubectl get ingress spicedb -o yaml

# Check Ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100 | grep spicedb

# Check service endpoints
kubectl get endpoints spicedb
```

### Common Causes

1. Ingress backend points to wrong service
2. Service selector doesn't match operator pods
3. Ingress annotation incompatible with operator service

### Resolution

```bash
# Verify Ingress backend
kubectl get ingress spicedb -o jsonpath='{.spec.rules[0].http.paths[0].backend}'

# Should point to operator-created service
# Update if incorrect:
kubectl patch ingress spicedb --type=json -p='[
  {"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "spicedb"}
]'

# Verify service has endpoints
kubectl get endpoints spicedb
```

## Issue: Metrics not appearing in Prometheus

### Symptoms

Prometheus doesn't scrape SpiceDB metrics.

### Diagnosis

```bash
# Check ServiceMonitor
kubectl get servicemonitor spicedb

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-k8s 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="spicedb")'

# Check if manual curl works
kubectl port-forward pod/spicedb-0 9090:9090 &
curl http://localhost:9090/metrics
```

### Common Causes

1. ServiceMonitor selector doesn't match service labels
2. Service doesn't have metrics port
3. Prometheus serviceMonitorSelector doesn't match ServiceMonitor labels

### Resolution

```bash
# Check service labels
kubectl get svc spicedb --show-labels

# Update ServiceMonitor selector to match
kubectl edit servicemonitor spicedb

# Add labels to ServiceMonitor if needed
kubectl label servicemonitor spicedb prometheus=kube-prometheus
```

Ensure your ServiceMonitor matches the service:

```yaml
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: spicedb  # Must match service labels
```

## FAQ

### Can I migrate without downtime?

**No** - Brief downtime (2-5 minutes) is unavoidable. Both Helm and Operator
manage the same deployment, and running both simultaneously causes conflicts.

For zero-downtime migration, you would need:

1. Blue-green deployment (separate databases)
2. Dual-write to both deployments
3. Cutover traffic
4. This is complex and not recommended for most use cases

### Will I lose data during migration?

**No** - The migration doesn't touch your database. Both Helm and Operator
connect to the same PostgreSQL/CockroachDB database.

**However**, always backup before migrating as a safety precaution.

### Can I use both Helm and Operator in the same cluster?

**Yes**, but not for the same SpiceDB instance. You can have:

- Helm-managed SpiceDB in namespace `production`
- Operator-managed SpiceDB in namespace `staging`

But you cannot have both managing the same deployment simultaneously.

### What happens to my TLS certificates?

**They are reused** - The operator references the same secret names. Your
existing TLS secrets (`spicedb-grpc-tls`, etc.) continue to work.

Note: Operator uses a single secret for both gRPC and HTTP TLS, while Helm
allows separate secrets.

### Can I migrate back to Helm later?

**Yes** - The migration is reversible. See
[MIGRATION_OPERATOR_TO_HELM.md](../MIGRATION_OPERATOR_TO_HELM.md) for the
reverse migration guide.

### How do I disable automatic updates?

Set `channel: manual` in SpiceDBCluster:

```yaml
spec:
  version: "v1.35.0"
  channel: manual  # Only suggests updates, doesn't apply them
```

Then manually update `spec.version` when ready to upgrade.

## Getting Help

If you encounter issues not covered here:

- **Operator Issues**: <https://github.com/authzed/spicedb-operator/issues>
- **Helm Chart Issues**: <https://github.com/salekseev/helm-charts/issues>
- **SpiceDB Discord**: <https://authzed.com/discord>
- **Migration Help**: Open issue with [migration] tag

## Additional Resources

- [Step-by-Step Migration](./step-by-step.md)
- [Post-Migration Validation](./post-migration.md)
- [Configuration Conversion](./configuration-conversion.md)
- [SpiceDB Operator Documentation](https://github.com/authzed/spicedb-operator/tree/main/docs)
