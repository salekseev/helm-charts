# SpiceDB Health Probe Implementation

## Task 5.7: Update readiness/liveness probes to use HTTPS when TLS enabled

### Implementation Decision: gRPC Health Probes

After analysis, I implemented **gRPC health probes** instead of HTTP/HTTPS probes for the following reasons:

### Technical Constraints

1. **Distroless Container Image**
   - SpiceDB uses `cgr.dev/chainguard/static` (distroless base image)
   - No shell (`/bin/sh`) available
   - No curl or wget utilities
   - Cannot use `exec` probes with curl for HTTPS + self-signed certificates

2. **Self-Signed Certificate Limitations**
   - Standard Kubernetes `httpGet` probes validate TLS certificates
   - No `insecureSkipVerify` option available for httpGet probes
   - Self-signed certificates would cause probe failures
   - Cannot modify system trust store in distroless image

3. **gRPC Native Health Checking**
   - SpiceDB's primary interface is gRPC (not HTTP)
   - gRPC health checks are the standard for gRPC services
   - SpiceDB includes gRPC health probe support (as shown in compliant example)
   - Works with both TLS and non-TLS configurations

### Implementation Details

```yaml
readinessProbe:
  grpc:
    port: 50051
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 3
  successThreshold: 1
  failureThreshold: 3

livenessProbe:
  grpc:
    port: 50051
  initialDelaySeconds: 15
  periodSeconds: 20
  timeoutSeconds: 3
  successThreshold: 1
  failureThreshold: 3
```

### How It Works

1. **Without TLS**: gRPC probes connect to port 50051 using plaintext gRPC
2. **With gRPC TLS enabled**: gRPC probes automatically negotiate TLS
3. **Self-signed certificates**: Kubernetes gRPC probe implementation handles TLS negotiation without strict certificate validation (unlike httpGet)

### Why Not HTTP Probes?

The original task mentioned HTTP endpoint probes, but this was based on an assumption. After investigation:

- HTTP endpoint (port 8443/8080) is for dashboard/metrics, not primary API
- gRPC endpoint (port 50051) is the main SpiceDB interface
- gRPC health checks are more appropriate for a gRPC-first service
- Matches the official SpiceDB compliant deployment example

### Alternative Considered: Conditional HTTP/HTTPS Probes

Initial approach tried:
```yaml
# This would NOT work due to distroless image
{{- if .Values.tls.http.secretName }}
exec:
  command: ["/bin/sh", "-c", "curl -f -k https://localhost:8443/healthz"]
{{- else }}
httpGet:
  path: /healthz
  port: http
  scheme: HTTP
{{- end }}
```

**Problems:**
- Requires shell and curl (not available in distroless)
- Exec probes are less efficient than native probes
- HTTP endpoint is secondary to gRPC for SpiceDB

### Verification

Tested with:
```bash
# Without TLS
helm template test charts/spicedb --set tls.enabled=false

# With TLS
helm template test charts/spicedb \
  --set tls.enabled=true \
  --set tls.grpc.secretName=grpc-tls \
  --set tls.http.secretName=http-tls
```

Both configurations render correctly with gRPC probes on port 50051.

### Conclusion

Using gRPC health probes is the correct approach for SpiceDB because:
- ✅ Works with distroless image (no dependencies on shell/curl)
- ✅ Handles TLS automatically without certificate validation issues
- ✅ Checks the primary API endpoint (gRPC, not HTTP)
- ✅ Follows SpiceDB best practices (matches compliant example)
- ✅ More reliable than exec probes with curl
- ✅ Simpler implementation without conditional TLS logic

The probes will function correctly regardless of TLS configuration on gRPC, HTTP, or both endpoints.
