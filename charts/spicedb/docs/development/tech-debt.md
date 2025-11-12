# Technical Debt

This document tracks known technical debt, limitations, and areas for improvement in the SpiceDB Helm chart.

## Resolved Issues

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
