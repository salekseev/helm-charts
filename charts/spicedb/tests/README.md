# SpiceDB Helm Chart Tests

This directory contains unit tests for the SpiceDB Helm chart using [helm-unittest](https://github.com/helm-unittest/helm-unittest).

## Prerequisites

```bash
# Install helm-unittest plugin
helm plugin install https://github.com/helm-unittest/helm-unittest.git

# Verify installation
helm unittest --help
```

## Directory Structure

```
tests/
├── unit/               # Unit tests for individual templates
│   ├── deployment_test.yaml
│   ├── service_test.yaml
│   └── helpers_test.yaml
├── integration/        # Integration tests (future)
└── values/            # Values file tests (future)
```

## Running Tests

### Run all tests

```bash
# From the chart directory
cd charts/spicedb
helm unittest .

# With color output
helm unittest --color .
```

### Run specific test file

```bash
helm unittest -f 'tests/unit/deployment_test.yaml' .
```

### Run tests with custom values

```bash
helm unittest -v values-examples/valid.yaml .
```

### Update snapshots

When you intentionally change template output, update snapshots:

```bash
helm unittest --update-snapshot .
```

## Writing Tests

### Basic Test Structure

```yaml
suite: test deployment
templates:
  - deployment.yaml
tests:
  - it: should render a Deployment
    asserts:
      - isKind:
          of: Deployment
```

### Common Assertion Types

#### isKind - Check resource kind

```yaml
- isKind:
    of: Deployment
```

#### equal - Check exact value

```yaml
- equal:
    path: metadata.name
    value: expected-name
```

#### matchRegex - Pattern matching

```yaml
- matchRegex:
    path: spec.template.spec.containers[0].image
    pattern: ^authzed/spicedb:v
```

#### contains - Check array contains item

```yaml
- contains:
    path: spec.template.spec.containers[0].ports
    content:
      name: grpc
      containerPort: 50051
```

#### isNull/isNotNull - Check existence

```yaml
- isNull:
    path: spec.template.spec.nodeSelector
- isNotNull:
    path: metadata.labels
```

#### isNotEmpty - Check non-empty

```yaml
- isNotEmpty:
    path: metadata.labels
```

### Setting Values in Tests

```yaml
- it: should allow custom replica count
  set:
    replicaCount: 3
  asserts:
    - equal:
        path: spec.replicas
        value: 3
```

### Testing Conditional Logic

```yaml
- it: should not render ingress by default
  asserts:
    - hasDocuments:
        count: 0

- it: should render ingress when enabled
  set:
    ingress.enabled: true
  asserts:
    - hasDocuments:
        count: 1
```

### Snapshot Testing

Snapshot tests capture the entire rendered output and detect any changes:

```yaml
- it: should match deployment snapshot
  asserts:
    - matchSnapshot: {}
```

First run creates the snapshot:

```bash
helm unittest --update-snapshot .
```

Subsequent runs compare against the snapshot and fail if different.

## Test Coverage Goals

We aim for high test coverage:

- **Template rendering**: Every template should have at least one test verifying it renders correctly
- **Default values**: Test that templates work with default values
- **Custom values**: Test important value overrides
- **Conditional logic**: Test enabled/disabled features
- **Edge cases**: Test boundary conditions and error cases

## Examples

See the test files in `tests/unit/` for comprehensive examples:

- [deployment_test.yaml](unit/deployment_test.yaml) - Deployment template tests with various configurations
- [service_test.yaml](unit/service_test.yaml) - Service port and type configurations
- [helpers_test.yaml](unit/helpers_test.yaml) - Helper template function tests

## CI/CD Integration

These tests run automatically in GitHub Actions on every push and pull request. See [.github/workflows/ci.yaml](../../.github/workflows/ci.yaml).

## Debugging Failed Tests

### View detailed output

```bash
helm unittest --color --debug .
```

### Test with specific values file

```bash
helm unittest -v values-examples/valid.yaml .
```

### Render templates manually

```bash
helm template . --values values.yaml
```

## Best Practices

1. **Write tests first** - Follow TDD: write test before implementing template
2. **One assertion per test** - Makes failures easier to diagnose
3. **Descriptive test names** - Use clear "it should..." descriptions
4. **Test the contract** - Focus on public API (values) not implementation details
5. **Update snapshots carefully** - Review changes before updating snapshots
6. **Test security** - Verify security contexts, resource limits, etc.

## Resources

- [helm-unittest Documentation](https://github.com/helm-unittest/helm-unittest/blob/main/DOCUMENT.md)
- [Helm Template Functions](https://helm.sh/docs/chart_template_guide/function_list/)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
