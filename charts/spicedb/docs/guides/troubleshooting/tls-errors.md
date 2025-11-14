# TLS Errors

[← Back to Troubleshooting Index](index.md)

This guide covers certificate and TLS-related problems in SpiceDB deployments.

## Certificate Validation Failures

**Symptoms:**

```text
x509: certificate signed by unknown authority
transport: authentication handshake failed
certificate has expired
certificate is not valid for requested name
```

**Diagnosis:**

```bash
# Check if TLS secrets exist
kubectl get secret spicedb-grpc-tls spicedb-http-tls spicedb-dispatch-tls

# Verify certificate contents
kubectl get secret spicedb-grpc-tls -o yaml

# Check certificate validity
kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -text -noout

# Check certificate expiration
kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -dates

# Verify certificate chain
kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl verify -CAfile ca.crt /dev/stdin
```

**Solutions:**

- **Certificate not found**: Ensure TLS secrets are created before deployment:

  ```bash
  # Verify secret exists
  kubectl get secret spicedb-grpc-tls

  # If using cert-manager, check certificate status
  kubectl get certificate spicedb-grpc-tls
  kubectl describe certificate spicedb-grpc-tls

  # Wait for certificate to be ready
  kubectl wait --for=condition=Ready certificate spicedb-grpc-tls --timeout=300s
  ```

- **Certificate signed by unknown authority**: Clients need the CA certificate:

  ```bash
  # Extract CA certificate
  kubectl get secret spicedb-ca-key-pair -o jsonpath='{.data.ca\.crt}' | \
    base64 -d > ca.crt

  # Distribute ca.crt to all clients
  # Clients should use this CA when connecting
  ```

- **Certificate expired**: Renew certificate or enable cert-manager auto-renewal:

  ```bash
  # Check certificate expiration
  kubectl get certificate -o custom-columns=\
  NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter

  # Force renewal with cert-manager
  kubectl delete secret spicedb-grpc-tls
  # cert-manager will automatically recreate it

  # Or manually create new certificate
  ```

- **Certificate hostname mismatch**: Ensure DNS names in certificate match connection hostname:

  ```bash
  # Check DNS names in certificate
  kubectl get secret spicedb-grpc-tls -o jsonpath='{.data.tls\.crt}' | \
    base64 -d | openssl x509 -text -noout | grep -A 2 "Subject Alternative Name"

  # Should include the hostname you're using to connect
  ```

## mTLS Configuration Issues

**Symptoms:**

```text
dispatch: connection refused
dispatch: certificate verification failed
remote error: tls: bad certificate
```

**Diagnosis:**

```bash
# Check if all pods have dispatch certificates
kubectl exec -it spicedb-0 -- ls -la /etc/spicedb/tls/dispatch/

# Verify dispatch secret includes all required files
kubectl get secret spicedb-dispatch-tls -o yaml

# Check for ca.crt, tls.crt, tls.key
kubectl get secret spicedb-dispatch-tls -o jsonpath='{.data.ca\.crt}'
kubectl get secret spicedb-dispatch-tls -o jsonpath='{.data.tls\.crt}'
kubectl get secret spicedb-dispatch-tls -o jsonpath='{.data.tls\.key}'

# View dispatch TLS configuration in environment
kubectl exec spicedb-0 -- env | grep DISPATCH.*TLS
```

**Solutions:**

- **Missing CA certificate**: Ensure dispatch secret includes `ca.crt`:

  ```bash
  # Recreate secret with CA certificate
  kubectl create secret generic spicedb-dispatch-tls \
    --from-file=tls.crt=dispatch.crt \
    --from-file=tls.key=dispatch.key \
    --from-file=ca.crt=ca.crt \
    --dry-run=client -o yaml | kubectl apply -f -
  ```

- **Different CAs**: All pods must use certificates from the same CA:

  ```bash
  # Verify all pods use same CA
  for pod in $(kubectl get pods -l app.kubernetes.io/name=spicedb -o name); do
    echo "Checking $pod"
    kubectl exec $pod -- cat /etc/spicedb/tls/dispatch/ca.crt | openssl x509 -noout -subject
  done
  # All should show same subject
  ```

- **Certificate permissions**: Ensure files have correct permissions:

  ```bash
  kubectl exec spicedb-0 -- ls -la /etc/spicedb/tls/dispatch/
  # Files should be readable by the spicedb user (UID 1000)
  ```

## CockroachDB SSL Errors

**Symptoms:**

```text
pq: SSL is not enabled on the server
x509: certificate is not valid for requested name
connection requires authentication
```

**Diagnosis:**

```bash
# Check SSL mode configuration
helm get values spicedb | grep -A 10 datastore

# Verify SSL certificate paths
kubectl exec spicedb-0 -- env | grep SSL

# Check datastore TLS files exist
kubectl exec spicedb-0 -- ls -la /etc/spicedb/tls/datastore/

# Test CockroachDB connection
kubectl run -it --rm debug --image=cockroachdb/cockroach:latest --restart=Never -- \
  sql --url "postgresql://spicedb:password@cockroachdb:26257/spicedb?sslmode=verify-full&sslcert=/certs/client.spicedb.crt&sslkey=/certs/client.spicedb.key&sslrootcert=/certs/ca.crt"
```

**Solutions:**

- **SSL not enabled error**: Set correct SSL mode:

  ```bash
  helm upgrade spicedb charts/spicedb \
    --set config.datastore.sslMode=verify-full \
    --set config.datastore.sslRootCert=/etc/spicedb/tls/datastore/ca.crt \
    --set config.datastore.sslCert=/etc/spicedb/tls/datastore/tls.crt \
    --set config.datastore.sslKey=/etc/spicedb/tls/datastore/tls.key \
    --reuse-values
  ```

- **Client certificate CN mismatch**: CockroachDB requires CN in format `client.<username>`:

  ```bash
  # Check certificate CN
  kubectl get secret spicedb-datastore-tls -o jsonpath='{.data.tls\.crt}' | \
    base64 -d | openssl x509 -noout -subject

  # Should show: subject=CN = client.spicedb
  ```

- **CA certificate mismatch**: Ensure you have CockroachDB's CA certificate:

  ```bash
  # Get CockroachDB CA certificate
  kubectl get secret cockroachdb-ca -n database -o jsonpath='{.data.ca\.crt}' | \
    base64 -d > cockroachdb-ca.crt

  # Create/update SpiceDB secret
  kubectl create secret generic spicedb-datastore-tls \
    --from-file=ca.crt=cockroachdb-ca.crt \
    --from-file=tls.crt=client.spicedb.crt \
    --from-file=tls.key=client.spicedb.key \
    --dry-run=client -o yaml | kubectl apply -f -
  ```

## See Also

- [Connection Issues](connection-issues.md) - For network connectivity problems
- [Migration Failures](migration-failures.md) - For database connection issues during migrations
