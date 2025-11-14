# Connection Issues

[← Back to Troubleshooting Index](index.md)

This guide covers network connectivity and service discovery problems in SpiceDB deployments.

## Service Discovery Problems

**Symptoms:**

```text
connection refused
no such host
dial tcp: lookup spicedb: no such host
```

**Diagnosis:**

```bash
# Check if service exists
kubectl get svc spicedb

# Check service endpoints
kubectl get endpoints spicedb

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup spicedb.default.svc.cluster.local

# Test connectivity
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  nc -zv spicedb 50051
```

**Solutions:**

- **Service doesn't exist**: Verify Helm deployment created service:

  ```bash
  helm list
  kubectl get svc

  # If missing, reinstall chart
  helm upgrade --install spicedb charts/spicedb
  ```

- **No endpoints**: Check if pods are running:

  ```bash
  kubectl get pods -l app.kubernetes.io/name=spicedb

  # If not running, check pod events
  kubectl describe pods -l app.kubernetes.io/name=spicedb
  ```

- **DNS issues**: Verify CoreDNS is working:

  ```bash
  kubectl get pods -n kube-system -l k8s-app=kube-dns
  kubectl logs -n kube-system -l k8s-app=kube-dns
  ```

## Network Policy Blocking

**Symptoms:**

```text
connection timeout
no route to host
connection refused (from specific namespaces)
```

**Diagnosis:**

```bash
# Check if NetworkPolicy is enabled
kubectl get networkpolicy

# Describe NetworkPolicy
kubectl describe networkpolicy spicedb

# Test from different namespaces
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- \
  nc -zv spicedb.default 50051

kubectl run -it --rm debug --image=nicolaka/netshoot -n other-namespace --restart=Never -- \
  nc -zv spicedb.default 50051
```

**Solutions:**

- **NetworkPolicy blocking traffic**: Update NetworkPolicy to allow required traffic:

  ```bash
  # Check actual namespace labels
  kubectl get namespace ingress-nginx --show-labels

  # Update NetworkPolicy to match
  kubectl label namespace ingress-nginx name=ingress-nginx
  ```

- **Disable NetworkPolicy temporarily for testing**:

  ```bash
  helm upgrade spicedb charts/spicedb \
    --set networkPolicy.enabled=false \
    --reuse-values
  ```

- **Test from allowed namespace**:

  ```bash
  # Get allowed namespace from NetworkPolicy
  kubectl get networkpolicy spicedb -o yaml

  # Test from that namespace
  kubectl run -it --rm debug -n <allowed-namespace> \
    --image=nicolaka/netshoot --restart=Never -- \
    nc -zv spicedb.default 50051
  ```

## Port Forwarding Issues

**Symptoms:**

```text
error: timed out waiting for port-forward
unable to listen on port
error forwarding port: listen tcp: address already in use
```

**Solutions:**

```bash
# Check if port is already in use
lsof -i :50051
netstat -an | grep 50051

# Kill process using the port
kill -9 <PID>

# Use different local port
kubectl port-forward svc/spicedb 50052:50051

# Use --address to bind to all interfaces (for remote access)
kubectl port-forward --address 0.0.0.0 svc/spicedb 50051:50051

# Check pod is running before port-forward
kubectl get pods -l app.kubernetes.io/name=spicedb
```

## See Also

- [TLS Errors](tls-errors.md) - For certificate-related connection issues
- [Migration Failures](migration-failures.md) - For database connection problems
- [Diagnostic Commands](diagnostic-commands.md) - For network debugging tools
