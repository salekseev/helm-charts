# SpiceDB Helm Chart Documentation Location

## Documentation Structure

All user-facing documentation for the SpiceDB Helm chart has been migrated to the **GitHub Wiki**.

### Wiki Location

**Main Wiki:** https://github.com/salekseev/helm-charts/wiki

**SpiceDB Chart Home:** https://github.com/salekseev/helm-charts/wiki/SpiceDB-Home

### Documentation Categories in Wiki

The wiki contains 42+ comprehensive documentation pages organized into:

1. **Getting Started**
   - [Quick Start Guide](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Quick-Start)
   - [Configuration Presets](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Configuration-Presets)

2. **Production Deployment** (6 pages)
   - [Production Guide Index](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Guides-Production-Index)
   - Infrastructure Setup, TLS Certificates, PostgreSQL/CockroachDB deployment, HA configuration

3. **Security** (6 pages)
   - [Security Guide Index](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Guides-Security-Index)
   - TLS Configuration, Authentication, Network Security, Pod Security, Compliance

4. **Troubleshooting** (7 pages)
   - [Troubleshooting Index](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Guides-Troubleshooting-Index)
   - Migration failures, TLS errors, connection issues, performance, pod scheduling, diagnostic commands

5. **Migration Guides** (13 pages)
   - [Operator Comparison](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Migration-Operator-Comparison)
   - Operator to Helm migration (6 pages)
   - Helm to Operator migration (6 pages)

6. **Operations** (2 pages)
   - [Status Monitoring Script](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Operations-Status-Script)
   - [Upgrading Guide](https://github.com/salekseev/helm-charts/wiki/SpiceDB-Guides-Upgrading)

### Navigation

The wiki includes a custom **_Sidebar.md** providing organized navigation for all documentation pages.

### Repository Structure (After Migration)

**What remains in repository:**
- `charts/spicedb/README.md` - Installation overview with links to wiki
- `charts/spicedb/values.yaml` - Complete configuration reference with inline docs
- `charts/spicedb/docs/development/` - Development-specific docs (testing, tech-debt)
- `charts/spicedb/examples/` - Example YAML configurations
- `charts/spicedb/CHANGELOG.md` - Release history

**What was migrated to wiki:**
- Quick start guide
- Configuration presets guide
- Production deployment guides
- Security guides
- Troubleshooting guides
- Migration guides (operator ↔ helm)
- Operations guides (status script, upgrading)

### Key Links for Development

- **Wiki Home:** https://github.com/salekseev/helm-charts/wiki
- **SpiceDB Chart:** https://github.com/salekseev/helm-charts/wiki/SpiceDB-Home
- **Quick Start:** https://github.com/salekseev/helm-charts/wiki/SpiceDB-Quick-Start
- **Repository:** https://github.com/salekseev/helm-charts

### When to Use Wiki vs Repository Docs

**Use Wiki for:**
- User-facing guides and tutorials
- Production deployment instructions
- Security configuration guides
- Troubleshooting common issues
- Migration procedures
- Operational guides

**Use Repository Docs for:**
- Development and testing procedures (`docs/development/`)
- Inline configuration documentation (`values.yaml`)
- Example configurations (`examples/`)
- Release notes and changelogs (`CHANGELOG.md`)
- Code-level documentation

### Benefits of Wiki Structure

1. **Cleaner Repository** - README reduced from 173 to ~140 lines
2. **Better User Experience** - Sidebar navigation, built-in search
3. **Easier Maintenance** - Wiki changes don't require PR reviews
4. **Multi-Chart Ready** - All pages prefixed with "SpiceDB-" for future expansion
5. **No Build/Deploy** - Wiki updates are instant

### Link Format

All wiki links use standard markdown format:
```markdown
[Display Text](Page-Name)
```

Wiki page names use hyphens instead of spaces and no `.md` extension.

### Wiki Repository

The wiki content is also available as a git repository:
```bash
git clone https://github.com/salekseev/helm-charts.wiki.git
```

This allows version control and bulk updates to wiki content.
