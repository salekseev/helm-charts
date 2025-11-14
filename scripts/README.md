# SpiceDB Helm Chart Scripts

This directory contains utility scripts for managing and monitoring SpiceDB deployments.

## status.sh

Check the health and status of a SpiceDB deployment.

### Prerequisites

- `kubectl` command-line tool installed and configured
- `jq` for JSON processing
- Access to the Kubernetes cluster where SpiceDB is deployed

### Usage

```bash
./scripts/status.sh [OPTIONS]
```

### Options

- `-n, --namespace NAMESPACE` - Kubernetes namespace (default: `default`)
- `-r, --release RELEASE` - Helm release name (default: `spicedb`)
- `-f, --format FORMAT` - Output format: `text` or `json` (default: `text`)
- `-h, --help` - Show help message

### Examples

**Check status in default namespace:**

```bash
./scripts/status.sh
```

**Check status in a specific namespace and release:**

```bash
./scripts/status.sh --namespace spicedb-prod --release my-spicedb
```

**Get JSON output for programmatic processing:**

```bash
./scripts/status.sh -n production -r spicedb -f json
```

**Pipe JSON output to jq for filtering:**

```bash
./scripts/status.sh -f json | jq '.deployment.ready'
```

### Output

#### Text Format (default)

```
SpiceDB Status
==============

Namespace: default
Release:   spicedb
Health:    healthy

Deployment:
  Replicas:  3/3 ready, 3 available, 3 updated

Version Information:
  App Version:      v1.30.0
  Chart Version:    1.1.0
  Datastore Engine: postgres
  Migration Hash:   abc123def456...

Pods:
  Total:   3
  Running: 3
  Pending: 0
  Failed:  0

Migration Status:
  Chart Version:    1.1.0
  App Version:      v1.30.0
  Datastore:        postgres
  Target Migration: latest
  Target Phase:     all phases
  Timestamp:        2025-01-15T10:30:00Z
  Config Hash:      abc123def456...
```

#### JSON Format

```json
{
  "namespace": "default",
  "release": "spicedb",
  "health": "healthy",
  "deployment": {
    "replicas": 3,
    "ready": 3,
    "available": 3,
    "updated": 3
  },
  "version": {
    "app": "v1.30.0",
    "chart": "1.1.0",
    "datastoreEngine": "postgres",
    "migrationHash": "abc123def456..."
  },
  "pods": {
    "total": 3,
    "running": 3,
    "pending": 0,
    "failed": 0
  },
  "migration": {
    "chartVersion": "1.1.0",
    "appVersion": "v1.30.0",
    "datastoreEngine": "postgres",
    "targetMigration": "",
    "targetPhase": "",
    "timestamp": "2025-01-15T10:30:00Z",
    "configHash": "abc123def456..."
  }
}
```

### Exit Codes

- `0` - Deployment is healthy or degraded (some replicas ready)
- `1` - Deployment is unhealthy (no replicas ready) or error occurred

### Health States

- **healthy** - All replicas are ready and available
- **degraded** - Some replicas are ready but not all
- **unhealthy** - No replicas are ready

### Troubleshooting

**Error: Deployment not found**

- Verify the namespace and release name are correct
- Check that SpiceDB is installed: `helm list -n <namespace>`

**Error: kubectl is required but not installed**

- Install kubectl: <https://kubernetes.io/docs/tasks/tools/>

**Error: jq is required but not installed**

- Install jq: <https://stedolan.github.io/jq/download/>

**Permission denied errors**

- Ensure your kubeconfig has access to the namespace
- Check RBAC permissions for reading Deployments, ConfigMaps, and Pods
