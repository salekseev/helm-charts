# CI/CD Workflows

This directory contains GitHub Actions workflows for continuous integration and deployment.

## Workflows

### ci-unit.yaml - Unit Tests & Validation (Required)

**Triggers:**
- Push to `main` or `master` branches
- Pull requests to `main` or `master` branches

**Jobs:**
1. **Lint** - Helm chart linting with strict mode
2. **Unit Tests** - helm-unittest test execution
3. **Preset Validation** - Validate all configuration presets
   - Lint all presets with `helm lint --strict`
   - Validate template rendering with `helm template --validate`
   - Schema validation against values.schema.json
   - Test value overrides
4. **Policy Validation** - Conftest security policy validation
5. **Chart Testing** - ct lint and ct install on kind cluster

**Duration:** ~2-5 minutes
**Status:** Required for PR merge

### ci-integration.yaml - Integration Tests (Optional)

**Triggers:**
- Push to `main` or `master` branches (always runs)
- Pull requests when `run-integration-tests` label is added
- Manual workflow dispatch

**Jobs:**
1. **Integration Tests** - Deploy chart and run integration tests across K8s versions
   - Kubernetes v1.28.0
   - Kubernetes v1.29.0
   - Kubernetes v1.30.0
2. **Integration Tests (Skipped)** - Informational job when tests don't run on PRs

**Duration:** ~30-54 minutes (3 versions in parallel)
**Status:** Optional for PR merge

### publish-chart.yaml - Chart Publishing

**Triggers:**
- GitHub releases (type: published)

**Jobs:**
1. **Publish** - Package and publish chart to OCI registry (ghcr.io)

**Duration:** ~2-3 minutes
**Status:** Automatic on release

### release-please.yaml - Release Management

**Triggers:**
- Push to `master` branch

**Jobs:**
1. **Release Please** - Automated release PR creation and management

**Duration:** ~1 minute
**Status:** Automatic

### ci-upgrade.yaml - Upgrade Testing (Optional)

**Triggers:**
- Schedule: Weekly on Mondays at 6 AM UTC
- Push to `main` or `master` branches
- Pull requests when `test-upgrade` label is added
- Manual workflow dispatch

**Jobs:**
1. **Upgrade Test** - Test chart upgrades from previous versions
   - Install previous version (2.0.0, 2.0.1)
   - Upgrade to current version
   - Verify migration validation
   - Test pod health and readiness
   - Verify rollback capability
   - Test across Kubernetes v1.28.0 and v1.30.0
2. **Upgrade Tests (Skipped)** - Informational job when tests don't run on PRs

**Duration:** ~15-20 minutes per version (parallel execution)
**Status:** Optional for PR merge, runs weekly on schedule

## Required Checks for Branch Protection

Configure these required status checks in GitHub repository settings:

- ✅ Lint Helm Chart
- ✅ Run Unit Tests
- ✅ Validate Configuration Presets
- ✅ Validate Security Policies
- ✅ Chart Testing

Do **NOT** require "Integration Tests" or "Upgrade Testing" - they're optional and controlled by labels/schedule.

## Labels

### run-integration-tests

Apply this label to a PR to trigger integration tests. The label can be added:

```bash
# Via GitHub CLI
gh pr edit <PR-NUMBER> --add-label "run-integration-tests"

# Via GitHub web UI
# Navigate to PR → Labels → Select "run-integration-tests"
```

### test-upgrade

Apply this label to a PR to trigger upgrade testing. The label can be added:

```bash
# Via GitHub CLI
gh pr edit <PR-NUMBER> --add-label "test-upgrade"

# Via GitHub web UI
# Navigate to PR → Labels → Select "test-upgrade"
```

Upgrade tests verify that the chart can be successfully upgraded from previous versions and that rollback works correctly.

## Workflow Modifications

When modifying workflows:

1. Test changes on a feature branch first
2. Verify workflow syntax with `yamllint`
3. Check workflow runs in the Actions tab
4. Update this README if behavior changes

## Cost Optimization

The split workflow design optimizes CI costs:

- **Before:** Every PR runs 30-54 min integration tests = ~2-3 hours/day
- **After:** Only labeled PRs run integration tests (~30%) = ~40 min/day
- **Savings:** ~60-70% reduction in integration test time

Integration tests still run on every push to `master` to ensure quality.
