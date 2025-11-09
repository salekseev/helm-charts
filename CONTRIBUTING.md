# Contributing to Helm Charts

Thank you for your interest in contributing! This document outlines the development workflow and best practices for all charts in this repository.

## Development Environment Setup

### Prerequisites

1. **Helm 3.14.0+**

   ```bash
   # Install Helm
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
   helm version
   ```

2. **helm-unittest plugin**

   ```bash
   helm plugin install https://github.com/helm-unittest/helm-unittest.git
   helm unittest --help
   ```

3. **Conftest v0.45.0+** (for policy validation)

   ```bash
   # Linux
   wget https://github.com/open-policy-agent/conftest/releases/download/v0.56.0/conftest_0.56.0_Linux_x86_64.tar.gz
   tar xzf conftest_0.56.0_Linux_x86_64.tar.gz
   sudo mv conftest /usr/local/bin/

   # macOS
   brew install conftest

   # Verify
   conftest --version
   ```

4. **pre-commit** (optional but recommended)

   ```bash
   # Using pip
   pip install pre-commit

   # Using brew (macOS)
   brew install pre-commit

   # Install hooks
   pre-commit install
   ```

5. **Kubernetes cluster** (for integration testing)

   - [Minikube](https://minikube.sigs.k8s.io/docs/start/)
   - [kind](https://kind.sigs.k8s.io/docs/user/quick-start/)
   - [Docker Desktop](https://www.docker.com/products/docker-desktop)

## Test-Driven Development (TDD) Workflow

We follow a strict TDD workflow to ensure high quality and maintainability.

### 1. Write Test First

Before implementing or modifying any template, write a test that defines the expected behavior.

```bash
# Create or modify a test file in the chart directory
vim charts/<chart-name>/tests/unit/<template>_test.yaml
```

Example test:

```yaml
suite: test deployment
templates:
  - deployment.yaml
tests:
  - it: should set resource limits when provided
    set:
      resources.limits.cpu: 1000m
      resources.limits.memory: 2Gi
    asserts:
      - equal:
          path: spec.template.spec.containers[0].resources.limits.cpu
          value: 1000m
```

### 2. Run Tests (They Should Fail)

```bash
cd charts/<chart-name>
helm unittest .
```

The test should fail because the template doesn't exist or doesn't implement the feature yet.

### 3. Implement the Template

Create or modify the template to satisfy the test.

```bash
vim charts/<chart-name>/templates/<template>.yaml
```

### 4. Run Tests Again (They Should Pass)

```bash
helm unittest .
```

### 5. Verify Lint and Policy Checks

```bash
# Lint the chart
helm lint . --strict

# Validate against security policies
helm template . --values values.yaml | conftest test -p policies/ -
```

### 6. Commit Both Test and Implementation

```bash
git add tests/unit/deployment_test.yaml
git add templates/deployment.yaml
git commit -m "feat: add resource limits support to deployment"
```

## Development Workflow Commands

### Running Tests

```bash
# All tests
helm unittest charts/<chart-name>

# Specific test file
helm unittest -f 'tests/unit/deployment_test.yaml' charts/<chart-name>

# With color output
helm unittest --color charts/<chart-name>

# Update snapshots after intentional changes
helm unittest --update-snapshot charts/<chart-name>

# With custom values
helm unittest -v values-examples/valid.yaml charts/<chart-name>
```

### Linting

```bash
# Lint chart
helm lint charts/<chart-name> --strict

# Validate values against schema
helm lint charts/<chart-name> --values charts/<chart-name>/values-examples/valid.yaml --strict
```

### Policy Validation

```bash
# Test compliant manifest
conftest test -p charts/<chart-name>/policies/ charts/<chart-name>/policies/examples/compliant-deployment.yaml

# Test rendered chart
helm template charts/<chart-name> | conftest test -p charts/<chart-name>/policies/ -

# Test with custom values
helm template charts/<chart-name> --values charts/<chart-name>/values-examples/valid.yaml | conftest test -p charts/<chart-name>/policies/ -
```

### Local Testing

```bash
# Render templates locally
helm template my-release charts/<chart-name>

# Render with custom values
helm template my-release charts/<chart-name> --values charts/<chart-name>/values-examples/valid.yaml

# Install on local cluster
helm install <release-name> charts/<chart-name>

# Upgrade
helm upgrade <release-name> charts/<chart-name>

# Uninstall
helm uninstall <release-name>
```

## Pre-commit Hooks

Pre-commit hooks automatically run tests before allowing commits. This ensures code quality and prevents broken commits.

### Installing Pre-commit Hooks

```bash
# Install pre-commit tool
pip install pre-commit

# Install hooks in repository
pre-commit install

# Run manually on all files
pre-commit run --all-files
```

### What Gets Checked

- Trailing whitespace removal
- End of file fixing
- YAML syntax validation
- Helm chart linting
- Helm unit tests
- Security policy validation

### Bypassing Hooks (Not Recommended)

```bash
# Only in exceptional cases
git commit --no-verify -m "message"
```

## Code Style and Best Practices

### Template Best Practices

1. **Use Helper Templates**: Define common patterns in `_helpers.tpl`
   ```yaml
   {{- define "mychart.labels" -}}
   app.kubernetes.io/name: {{ include "mychart.name" . }}
   {{- end }}
   ```

2. **Make Everything Configurable**: Use values.yaml for all configuration
   ```yaml
   replicas: {{ .Values.replicaCount }}
   ```

3. **Provide Sensible Defaults**: Ensure chart works with minimal configuration
   ```yaml
   # values.yaml
   replicaCount: 1
   ```

4. **Use Conditional Logic Sparingly**: Keep templates readable
   ```yaml
   {{- if .Values.ingress.enabled }}
   # ingress config
   {{- end }}
   ```

5. **Follow Kubernetes Best Practices**: Security contexts, resource limits, probes
   ```yaml
   securityContext:
     runAsNonRoot: true
     readOnlyRootFilesystem: true
   ```

### Test Best Practices

1. **One Concept Per Test**: Each test should verify one specific behavior
2. **Descriptive Names**: Use clear "it should..." descriptions
3. **Test Defaults First**: Verify chart works with default values
4. **Test Overrides**: Verify custom values work correctly
5. **Test Edge Cases**: Boundary conditions and error cases
6. **Use Snapshots Wisely**: Good for detecting unintended changes

### Documentation Best Practices

1. **Update README**: Keep configuration table current
2. **Comment Complex Logic**: Explain why, not what
3. **Provide Examples**: Include example values files
4. **Document Breaking Changes**: In CHANGELOG.md

## CI/CD Pipeline

All pull requests must pass the CI/CD pipeline:

1. **Lint**: Helm lint with strict mode
2. **Unit Tests**: All helm-unittest tests must pass
3. **Policy Validation**: Conftest security policies must pass
4. **Chart Testing**: Install test on kind cluster

See [.github/workflows/ci.yaml](.github/workflows/ci.yaml) for details.

## Submitting Changes

### Pull Request Process

1. **Fork the repository**
2. **Create a feature branch**
   ```bash
   git checkout -b feature/my-feature
   ```

3. **Follow TDD workflow** (write test, implement, verify)

4. **Ensure all tests pass**
   ```bash
   helm unittest charts/<chart-name>
   helm lint charts/<chart-name> --strict
   helm template charts/<chart-name> | conftest test -p charts/<chart-name>/policies/ -
   ```

5. **Commit with meaningful messages**
   ```bash
   git commit -m "feat: add support for custom TLS certificates"
   ```

6. **Push to your fork**
   ```bash
   git push origin feature/my-feature
   ```

7. **Create Pull Request** against `main` branch

### Commit Message Format

We use [Conventional Commits](https://www.conventionalcommits.org/) for automated versioning and changelog generation. The commit format directly controls how the chart version is bumped.

#### Commit Types and Versioning

- `feat:` New feature (triggers **MINOR** version bump: 1.0.0 -> 1.1.0)
- `fix:` Bug fix (triggers **PATCH** version bump: 1.0.0 -> 1.0.1)
- `docs:` Documentation changes (no version bump)
- `test:` Test changes (no version bump)
- `refactor:` Code refactoring (no version bump)
- `chore:` Maintenance tasks (no version bump)

#### Breaking Changes

For breaking changes that require a **MAJOR** version bump (1.0.0 -> 2.0.0):

```
feat!: change default datastore from memory to postgres

BREAKING CHANGE: The default datastore is now PostgreSQL instead of in-memory.
Users must provide PostgreSQL connection details or explicitly set
datastore.engine to "memory" to maintain previous behavior.
```

Or use the `BREAKING CHANGE:` footer:

```
feat: migrate to new Helm chart API version

BREAKING CHANGE: Chart now requires Helm 3.14.0 or later.
```

#### Examples

```
feat: add PostgreSQL datastore support
fix: correct service port configuration
docs: update README with TLS examples
test: add tests for migration hooks
chore: update dependencies

feat!: remove deprecated values.legacy configuration

BREAKING CHANGE: The values.legacy section has been removed.
Use values.config instead.
```

#### Automated Release Process

Our release process is fully automated using [Release Please](https://github.com/googleapis/release-please):

1. **On every commit to `master`**:
   - Release Please analyzes commit messages
   - Creates or updates a release PR with:
     - Updated version in chart's `Chart.yaml`
     - Generated changelog in chart's `CHANGELOG.md`

2. **When the release PR is merged**:
   - A GitHub release is created
   - Chart package is published
   - Version tags are created (without `v` prefix for Helm compatibility)

3. **No manual version updates needed**:
   - Never manually edit the version in `Chart.yaml`
   - Never manually edit `CHANGELOG.md`
   - Release Please handles all version management

This ensures consistent, predictable releases based on semantic versioning.

## Getting Help

- **Issues**: [GitHub Issues](https://github.com/salekseev/helm-charts/issues)
- **Discussions**: [GitHub Discussions](https://github.com/salekseev/helm-charts/discussions)

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
