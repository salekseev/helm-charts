# SpiceDB Helm Chart Scripts

Utility scripts for managing and monitoring SpiceDB deployments.

## status.sh

Check the health and status of a SpiceDB deployment.

### Quick Usage

```bash
# Check default namespace and release
./status.sh

# Check specific namespace and release
./status.sh --namespace spicedb-prod --release spicedb

# JSON output for automation
./status.sh -n production -r spicedb -f json
```

## Documentation

For complete documentation, see [Status Monitoring](../docs/operations/status-script.md).

---

For other operational guides, see the [Operations Documentation](../docs/operations/).
