# SpiceDB Helm Chart Utility Scripts

This directory contains utility scripts for working with the SpiceDB Helm chart.

## Configuration Converters

These scripts help migrate between the SpiceDB Helm chart and the SpiceDB Operator.

### convert-helm-to-operator.sh

Converts Helm `values.yaml` configuration to SpiceDB Operator `SpiceDBCluster` CRD format.

**Usage:**
```bash
# Convert development preset
./convert-helm-to-operator.sh -i ../values-presets/development.yaml

# Convert to file
./convert-helm-to-operator.sh -i ../values.yaml -o spicedb-cluster.yaml

# Test without output
./convert-helm-to-operator.sh -i ../values.yaml --dry-run
```

**Options:**
- `-i, --input FILE` - Input Helm values.yaml file
- `-o, --output FILE` - Output SpiceDBCluster YAML file (default: stdout)
- `--name NAME` - SpiceDBCluster resource name (default: spicedb)
- `--namespace NS` - Kubernetes namespace (default: default)
- `--dry-run` - Validate without producing output
- `-h, --help` - Show help message

**Limitations:**
- NetworkPolicy configurations are not transferred (Helm chart exclusive)
- Ingress configurations are not transferred (not managed by operator)
- ServiceMonitor configurations are not transferred
- PodDisruptionBudget settings handled differently by operator

**See Also:**
- [MIGRATION_HELM_TO_OPERATOR.md](../MIGRATION_HELM_TO_OPERATOR.md) - Full migration guide
- [OPERATOR_COMPARISON.md](../OPERATOR_COMPARISON.md) - Feature comparison

---

### convert-operator-to-helm.sh

Converts SpiceDB Operator `SpiceDBCluster` CRD to Helm `values.yaml` format.

**Usage:**
```bash
# Convert SpiceDBCluster
./convert-operator-to-helm.sh -i spicedb-cluster.yaml

# Convert and save
./convert-operator-to-helm.sh -i spicedb-cluster.yaml -o values.yaml

# Use preset as base
./convert-operator-to-helm.sh -i spicedb-cluster.yaml --preset production-postgres -o values.yaml

# Test without output
./convert-operator-to-helm.sh -i spicedb-cluster.yaml --dry-run
```

**Options:**
- `-i, --input FILE` - Input SpiceDBCluster YAML file (required)
- `-o, --output FILE` - Output values.yaml file (default: stdout)
- `--preset NAME` - Base preset to use (development, production-postgres, production-cockroachdb)
- `--dry-run` - Validate without producing output
- `-h, --help` - Show help message

**Operator-Exclusive Features:**
- `spec.channel` - Operator version update channels (not in Helm, requires manual image.tag updates)
- `spec.patches` - Operator JSON patches (must be manually applied to Helm values)

**Helm Features to Configure Manually:**
- NetworkPolicy - Network isolation (not available in operator)
- Ingress - External access configuration (not managed by operator)
- ServiceMonitor - Prometheus integration (not in operator)

**See Also:**
- [MIGRATION_OPERATOR_TO_HELM.md](../MIGRATION_OPERATOR_TO_HELM.md) - Full migration guide
- [OPERATOR_COMPARISON.md](../OPERATOR_COMPARISON.md) - Feature comparison

---

## Prerequisites

Both scripts require:
- **yq v4+** - YAML processor ([Installation guide](https://github.com/mikefarah/yq#install))
- **bash** - Bash shell (usually pre-installed on Linux/macOS)

Install yq:
```bash
# macOS (Homebrew)
brew install yq

# Linux (binary)
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq

# Verify installation
yq --version
```

---

## Examples

### Example 1: Test Helm → Operator Conversion

```bash
# Validate development preset can be converted
./convert-helm-to-operator.sh -i ../values-presets/development.yaml --dry-run

# Convert and preview
./convert-helm-to-operator.sh -i ../values-presets/development.yaml
```

### Example 2: Convert Production Configuration

```bash
# Convert production PostgreSQL preset to operator format
./convert-helm-to-operator.sh \
  -i ../values-presets/production-postgres.yaml \
  -o /tmp/spicedb-cluster.yaml \
  --name spicedb-production \
  --namespace production

# Review generated file
cat /tmp/spicedb-cluster.yaml

# Apply to cluster (assuming operator is installed)
kubectl apply -f /tmp/spicedb-cluster.yaml
```

### Example 3: Migrate from Operator to Helm

```bash
# Get existing SpiceDBCluster from cluster
kubectl get spicedbcluster spicedb -o yaml > current-cluster.yaml

# Convert to Helm values
./convert-operator-to-helm.sh \
  -i current-cluster.yaml \
  -o my-values.yaml \
  --preset production-postgres

# Review generated values
cat my-values.yaml

# Test Helm chart rendering
helm template test-release .. -f my-values.yaml

# Install with Helm (after removing operator deployment)
helm install spicedb .. -f my-values.yaml
```

### Example 4: Round-Trip Conversion Test

```bash
# Start with Helm values
./convert-helm-to-operator.sh -i ../values.yaml -o cluster.yaml

# Convert back to Helm
./convert-operator-to-helm.sh -i cluster.yaml -o values-roundtrip.yaml

# Compare (core settings should match)
diff ../values.yaml values-roundtrip.yaml
```

---

## Troubleshooting

### yq not found

```
Error: yq is required but not installed.
```

**Solution:** Install yq v4+ following the instructions in Prerequisites section above.

### Invalid YAML input

```
Error: Input file is not valid YAML: values.yaml
```

**Solution:** Validate your YAML file:
```bash
yq eval '.' values.yaml
```

### Conversion warnings

Warnings are normal and indicate features that don't directly map between Helm and Operator. Review warnings and configure missing features manually.

### Generated YAML invalid

If generated YAML is invalid:
1. Check input file is valid
2. Report issue with example input/output to [GitHub Issues](https://github.com/salekseev/helm-charts/issues)

---

## Contributing

Found a bug or want to add a feature? Please [open an issue](https://github.com/salekseev/helm-charts/issues) or submit a pull request.

---

## Related Documentation

- [OPERATOR_COMPARISON.md](../OPERATOR_COMPARISON.md) - Detailed feature comparison
- [MIGRATION_HELM_TO_OPERATOR.md](../MIGRATION_HELM_TO_OPERATOR.md) - Helm → Operator migration guide
- [MIGRATION_OPERATOR_TO_HELM.md](../MIGRATION_OPERATOR_TO_HELM.md) - Operator → Helm migration guide
- [README.md](../README.md) - Main chart documentation
- [PRESET_GUIDE.md](../PRESET_GUIDE.md) - Configuration preset guide
