# SpiceDB Troubleshooting Guide

This guide provides solutions to common issues encountered when deploying and operating SpiceDB.

## Quick Diagnostic Checklist

Before diving into specific issues, run these quick checks:

```bash
# 1. Check overall status
kubectl get all -l app.kubernetes.io/name=spicedb

# 2. Check pod health
kubectl get pods -l app.kubernetes.io/name=spicedb -o wide

# 3. View recent events
kubectl get events --sort-by='.lastTimestamp' | head -20

# 4. Check logs for errors
kubectl logs -l app.kubernetes.io/name=spicedb --tail=50 | grep -i error

# 5. Verify service endpoints
kubectl get endpoints spicedb
```

## Common Issues by Category

### [Migration Failures](migration-failures.md)

Issues with database schema migrations during installation or upgrades:

- Database connection errors
- Permission issues
- Schema conflicts
- Migration job timeouts
- Migration job stuck or cleanup failures

### [TLS Errors](tls-errors.md)

Certificate and TLS-related problems:

- Certificate validation failures
- mTLS configuration issues
- CockroachDB SSL errors
- Certificate expiration and renewal

### [Connection Issues](connection-issues.md)

Network connectivity and service discovery problems:

- Service discovery failures
- Network policy blocking
- Port forwarding issues
- DNS resolution problems

### [Performance Issues](performance-issues.md)

Resource exhaustion and performance problems:

- OOMKilled / memory exhaustion
- CPU throttling
- Database connection pool exhaustion
- Slow dispatch performance

### [Pod Scheduling Problems](pod-scheduling.md)

Issues with pod placement and scheduling:

- Pods stuck in pending state
- Insufficient cluster resources
- Anti-affinity constraints
- Zone distribution issues
- HPA not scaling
- PodDisruptionBudget blocking drains

### [Diagnostic Commands](diagnostic-commands.md)

Useful commands for troubleshooting and debugging:

- General health checks
- Configuration verification
- Logging and debugging
- Database connectivity tests
- Network debugging
- Metrics and performance analysis

## Getting Help

If you're still experiencing issues after trying these troubleshooting steps:

1. **Check existing issues**: Search [SpiceDB GitHub issues](https://github.com/authzed/spicedb/issues)
2. **Gather diagnostics**: Collect the output from the diagnostic commands
3. **Check logs**: Include relevant log excerpts with your issue report
4. **SpiceDB version**: Note the exact SpiceDB version you're using
5. **Environment details**: Include Kubernetes version, cloud provider, etc.
6. **Configuration**: Share relevant parts of your Helm values (redact sensitive data)

Report issues at: <https://github.com/authzed/spicedb/issues>

For questions and discussions: <https://github.com/authzed/spicedb/discussions>
