# Subtask 5.6: Update Datastore Connection Strings for TLS Support

## Summary of Changes

Successfully updated the SpiceDB Helm chart to support TLS for datastore connections using the new `tls.datastore` configuration.

### Files Modified

1. **charts/spicedb/templates/_helpers.tpl**
   - Updated `spicedb.datastoreConnectionString` helper function
   - Added support for `tls.datastore.secretName` and `tls.datastore.caPath`
   - When `tls.enabled=true` and `tls.datastore.secretName` is set, the helper:
     - Sets `sslMode` to `verify-full`
     - Uses `tls.datastore.caPath` for the CA certificate path
     - Overrides legacy `config.datastore.sslMode` and `config.datastore.sslRootCert` settings

2. **charts/spicedb/templates/hooks/migration-job.yaml**
   - Added datastore TLS volume mount for migration jobs
   - Ensures migrations can connect to TLS-enabled databases
   - Mounts the same certificate secret as the main deployment

## How SSL Parameters Are Appended

The connection string helper follows this logic:

1. **Base Connection String**: Always starts with `postgresql://user:pass@host:port/database?sslmode=MODE`
2. **SSL Mode Selection**:
   - If `tls.datastore.secretName` is set: uses `verify-full`
   - Otherwise: uses `config.datastore.sslMode` (default: `disable`)
3. **SSL Parameters**: Appended using `&` separator:
   - `sslrootcert`: CA certificate path (URL-encoded)
   - `sslcert`: Client certificate path (URL-encoded) - optional
   - `sslkey`: Client key path (URL-encoded) - optional

### Configuration Precedence

When both old and new TLS configurations exist:
- `tls.datastore` takes precedence over `config.datastore.ssl*`
- This allows seamless migration from legacy to new configuration

## Examples of Generated Connection Strings

### Test 1: Basic PostgreSQL without TLS
```
postgresql://spicedb:testpass@localhost:5432/spicedb?sslmode=disable
```

### Test 2: PostgreSQL with Legacy SSL Config
```yaml
config:
  datastore:
    sslMode: verify-full
    sslRootCert: /certs/ca.crt
```
```
postgresql://spicedb:testpass@localhost:5432/spicedb?sslmode=verify-full&sslrootcert=%2Fcerts%2Fca.crt
```

### Test 3: PostgreSQL with New tls.datastore Config
```yaml
tls:
  enabled: true
  datastore:
    secretName: postgres-tls
    caPath: /etc/spicedb/tls/datastore/ca.crt
```
```
postgresql://spicedb:testpass@localhost:5432/spicedb?sslmode=verify-full&sslrootcert=%2Fetc%2Fspicedb%2Ftls%2Fdatastore%2Fca.crt
```

### Test 4: Both Configs (tls.datastore Takes Precedence)
```yaml
config:
  datastore:
    sslMode: disable  # Overridden
    sslRootCert: /old/path/ca.crt  # Overridden
tls:
  enabled: true
  datastore:
    secretName: postgres-tls
    caPath: /etc/spicedb/tls/datastore/ca.crt
```
```
postgresql://spicedb:testpass@localhost:5432/spicedb?sslmode=verify-full&sslrootcert=%2Fetc%2Fspicedb%2Ftls%2Fdatastore%2Fca.crt
```

### Test 5: CockroachDB with TLS
```yaml
config:
  datastoreEngine: cockroachdb
  datastore:
    port: 26257
tls:
  enabled: true
  datastore:
    secretName: cockroach-tls
    caPath: /etc/spicedb/tls/datastore/ca.crt
```
```
postgresql://spicedb:testpass@localhost:26257/spicedb?sslmode=verify-full&sslrootcert=%2Fetc%2Fspicedb%2Ftls%2Fdatastore%2Fca.crt
```

### Test 6: PostgreSQL with Client Certificates (Legacy)
```yaml
config:
  datastore:
    sslMode: verify-full
    sslRootCert: /certs/ca.crt
    sslCert: /certs/client.crt
    sslKey: /certs/client.key
```
```
postgresql://spicedb:testpass@localhost:5432/spicedb?sslmode=verify-full&sslrootcert=%2Fcerts%2Fca.crt&sslcert=%2Fcerts%2Fclient.crt&sslkey=%2Fcerts%2Fclient.key
```

## Verification Results

### Helm Template Tests
All tests passed successfully:

1. **Connection String Generation**: ✅
   - Basic PostgreSQL without TLS
   - PostgreSQL with legacy SSL config
   - PostgreSQL with new tls.datastore config
   - Both configs together (precedence working)
   - CockroachDB with TLS
   - Client certificates support

2. **Volume Mounts**: ✅
   - Deployment has datastore TLS volume mount
   - Migration job has datastore TLS volume mount
   - Both mount to `/etc/spicedb/tls/datastore`
   - Secret name correctly references `tls.datastore.secretName`

3. **URL Encoding**: ✅
   - Paths are properly URL-encoded (e.g., `/` becomes `%2F`)
   - Decodes correctly in PostgreSQL connection libraries

### Integration Points

1. **Secret Template** (`templates/secret.yaml`):
   - Uses the `spicedb.datastoreConnectionString` helper
   - Generates connection string with TLS parameters
   - Base64 encodes for Kubernetes Secret

2. **Deployment** (`templates/deployment.yaml`):
   - References the secret for `SPICEDB_DATASTORE_CONN_URI`
   - Mounts TLS certificates when `tls.datastore.secretName` is set
   - Volume mount at `/etc/spicedb/tls/datastore`

3. **Migration Job** (`templates/hooks/migration-job.yaml`):
   - References the same secret as deployment
   - Now includes TLS volume mount (newly added)
   - Ensures migrations work with TLS-enabled databases

## Testing Commands

```bash
# Test basic connection string generation
helm template test ./charts/spicedb \
  --set config.datastoreEngine=postgres \
  --set config.datastore.password=testpass

# Test with TLS enabled
helm template test ./charts/spicedb \
  --set config.datastoreEngine=postgres \
  --set config.datastore.password=testpass \
  --set tls.enabled=true \
  --set tls.datastore.secretName=postgres-ca-cert \
  --set tls.datastore.caPath=/etc/spicedb/tls/datastore/ca.crt

# Decode connection string from output
helm template test ./charts/spicedb [...] | \
  grep "datastore-uri:" | head -1 | \
  awk '{print $2}' | tr -d '"' | base64 -d
```

## Notes

- The connection string format is compatible with both PostgreSQL and CockroachDB
- URL encoding is handled by the `urlquery` function in the template
- The `?` vs `&` parameter separator is correctly handled (always starts with `?` for sslmode)
- The implementation is backward compatible with existing deployments using legacy SSL config
- No breaking changes to existing functionality
