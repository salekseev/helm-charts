# Technical Debt

This document tracks known technical debt, limitations, and areas for improvement in the SpiceDB Helm chart.

## Resolved Issues

### Documentation Organization (AI Developer Guide Compliance)
**Status:** ✅ Resolved in v1.1.2
**Issue:** Root-level documentation scattered outside docs/ hierarchy violating AI Developer Guide
**Resolution:** Moved all root documentation to docs/guides/: production.md, security.md, troubleshooting.md, upgrading.md, and CHANGELOG.md
**Impact:** Improved documentation discoverability, consistent hierarchy, cleaner repository root
**Tasks:** Documented in task #79 (template splitting) and #80 (doc splitting) for remaining work

### Default Value Changes for Backward Compatibility
**Status:** ✅ Resolved in v1.1.2
**Issue:** Changed defaults (replicaCount=3, dispatch=true, PDB=true) broke backward compatibility
**Resolution:** Reverted to conservative defaults (replicaCount=1, dispatch=false, PDB=false)
**Impact:** Production defaults now opt-in via presets, maintaining 100% backward compatibility

### Migration Hook Secret References
**Status:** ✅ Resolved in v1.1.2
**Issue:** Migration hooks failed when autogenerateSecret=false without existingSecret
**Resolution:** Added conditional rendering: hooks only render when secret is available
**Impact:** Prevents CreateContainerConfigError failures, all 113 migration tests pass

## Active Issues

### Template File Length Violations (AI Developer Guide)
**Priority:** Medium
**Issue:** templates/_helpers.tpl exceeds AI Developer Guide 500-line recommendation at 638 lines (128% over limit)
**Root Cause:** Single file contains all helper functions including 280-line deployment template
**Impact:** Difficult to navigate, hard to maintain, violates "short and simple" principle
**Proposed Solution:**
- Split into focused helper files by concern:
  - `_helpers.tpl` - Core naming helpers (~100 lines)
  - `_helpers-deployment.tpl` - Deployment base template (~280 lines)
  - `_helpers-labels.tpl` - Labels and selectors (~50 lines)
  - `_helpers-datastore.tpl` - Datastore connection helpers (~80 lines)
  - `_helpers-tls.tpl` - TLS configuration (~100 lines)
  - `_helpers-operator.tpl` - Operator compatibility (~80 lines)
  - `_helpers-patches.tpl` - Patch validation (~60 lines)
- Run full test suite after split to verify no regressions

**Effort Estimate:** 2-3 hours
**Dependencies:** None
**Tracked in:** Task #79

### Documentation File Length Violations (AI Developer Guide)
**Priority:** Low
**Issue:** Migration documentation files exceed 500-line AI Developer Guide recommendation
**Files:**
- `docs/migration/helm-to-operator.md` - 1,455 lines (291% over limit)
- `docs/migration/operator-to-helm.md` - 1,395 lines (279% over limit)
**Impact:** Difficult to navigate, overwhelming for users, violates "short and simple" principle
**Proposed Solution:**
- Split each into subdirectories:
  - `overview.md` - Introduction and decision guide (~200 lines)
  - `preparation.md` - Prerequisites and planning (~300 lines)
  - `execution.md` - Step-by-step migration (~400 lines)
  - `validation.md` - Testing and verification (~200 lines)
- Create index file with table of contents
- Update cross-references

**Effort Estimate:** 1-2 hours
**Dependencies:** None
**Tracked in:** Task #80

### Integration Test Coverage with Live Databases
**Priority:** Medium
**Issue:** Migration jobs require actual database connections for full end-to-end testing
**Current Workaround:** Using dry-run validation, template rendering tests, and comprehensive unit tests (310+ tests)
**Impact:** Cannot fully test migration job execution in CI without database infrastructure
**Proposed Solution:**
- Add PostgreSQL and CockroachDB containers to CI workflow
- Create integration test suite that deploys databases in Kind cluster
- Test actual migration execution with database schema changes

**Effort Estimate:** 2-3 days
**Dependencies:** None

### Operator-to-Helm Migration Integration Test Coverage
**Priority:** Medium
**Issue:** No automated integration tests for migration from spicedb-operator to Helm chart
**Current State:**
- Comprehensive documentation exists (`docs/migration/operator-to-helm.md` - 35KB)
- Integration tests only cover Helm-to-Helm upgrade scenarios
- Manual verification required for operator migrations
**Impact:** Cannot automatically validate operator-to-helm migration procedures work correctly
**Proposed Solution:**
- Create integration test that deploys SpiceDB using the operator
- Test migration procedure documented in operator-to-helm.md
- Verify configuration conversion (operator CR → Helm values)
- Test resource ownership transfer
- Validate data persistence during migration
- Add to CI workflow for regression prevention

**Effort Estimate:** 3-4 days
**Dependencies:** Requires spicedb-operator test deployment infrastructure

### Pre-existing Unit Test Failures
**Priority:** Low
**Issue:** 4 tests failing in deployment-annotations, deployment, and patches test suites
**Root Cause:** Test expectations not updated after chart version bump and feature changes
**Failing Tests:**
  - `test deployment operator annotations` - Expected chart version mismatch
  - `test deployment` - Replica count expectation needs update
  - `test patches strategic merge system` - Snapshot update needed

**Impact:** Does not affect functionality, migration hooks work correctly (113/113 tests pass)
**Next Steps:**
1. Review test expectations and snapshots
2. Update to match current chart version and defaults
3. Regenerate snapshots if needed

**Effort Estimate:** 1-2 hours

### Documentation Website
**Priority:** Low
**Issue:** Documentation is in markdown files, could benefit from a documentation website
**Current State:** Well-organized markdown docs in `docs/` directory
**Proposed Solution:** Generate documentation website using MkDocs or Nextra
**Benefits:**
- Better navigation and search
- Version-specific documentation
- Better mobile experience

**Effort Estimate:** 1-2 days
**Dependencies:** None

## Potential Improvements

### Automated Release Process
**Priority:** Medium
**Idea:** Implement automated releases with changelog generation
**Benefits:**
- Consistent release process
- Automated version bumping
- Generated changelogs
- Automated GitHub releases

**Tools to Consider:**
- release-please for automated releases
- semantic-release for version management
- GitHub Actions for automation

**Effort Estimate:** 1 day

### Helm Chart Best Practices Validation
**Priority:** Low
**Idea:** Add helm chart testing beyond ct lint
**Potential Tools:**
- Polaris for Kubernetes best practices
- Checkov for security scanning
- Helm Chart Testing guidelines compliance

**Effort Estimate:** 2-3 hours

### Values Schema Validation Enhancement
**Priority:** Low
**Issue:** values.schema.json could be more comprehensive
**Improvements:**
- Add examples to schema
- More granular validation rules
- Better error messages for invalid configurations

**Effort Estimate:** 1 day

## Non-Issues (Not Technical Debt)

### Memory Datastore Warning
**Status:** Intentional Design
**Reason:** Memory datastore is for development only, warning is appropriate
**No Action Needed:** Users should use PostgreSQL/CockroachDB for production

### Hook Weight Dependencies
**Status:** Working as Designed
**Reason:** Secret has weight -1, migration has weight 0, ensures proper ordering
**No Action Needed:** Hook ordering is correct and tested

---

**Last Updated:** 2025-11-12
**Maintainer:** @salekseev

## Contributing

Found technical debt or areas for improvement? Please:
1. Open an issue describing the problem and proposed solution
2. Add it to this document via pull request
3. Include priority assessment and effort estimate
