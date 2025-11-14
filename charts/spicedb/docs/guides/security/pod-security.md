# Pod Security

This guide covers pod-level security controls, including Pod Security Standards, image security, and resource limits.

## Pod Security Standards

This chart implements the Kubernetes **restricted** Pod Security Standard:

### Pod-Level Security Context

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault
```

### Container-Level Security Context

```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
    - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
```

## What These Settings Provide

- **Non-root execution**: Reduces container breakout risk
- **Read-only filesystem**: Prevents malicious writes
- **Dropped capabilities**: Minimal Linux capabilities
- **Seccomp profile**: Restricts syscalls
- **No privilege escalation**: Prevents gaining root

## Pod Security Admission

Enable Pod Security Admission (PSA) at namespace level:

```yaml
# Enforce restricted profile
apiVersion: v1
kind: Namespace
metadata:
  name: spicedb
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Verification

```bash
# Check namespace labels
kubectl get namespace spicedb -o yaml | grep pod-security

# Try to deploy privileged pod (should be blocked)
kubectl run test --image=nginx --privileged -n spicedb
# Error: pods "test" is forbidden: violates PodSecurity "restricted:latest"
```

## Image Security

### Best Practices for Container Images

#### 1. Use Specific Image Tags

```yaml
image:
  tag: "v1.39.0"  # NOT "latest"
```

**Why?**

- Ensures reproducible deployments
- Prevents unexpected updates
- Allows controlled rollbacks

#### 2. Scan Images for Vulnerabilities

```bash
# Using Trivy
trivy image authzed/spicedb:v1.39.0

# Using Grype
grype authzed/spicedb:v1.39.0

# Using Snyk
snyk container test authzed/spicedb:v1.39.0
```

#### 3. Use Image Pull Secrets for Private Registries

```yaml
imagePullSecrets:
- name: registry-credentials
```

```bash
# Create image pull secret
kubectl create secret docker-registry registry-credentials \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=password \
  --docker-email=user@example.com
```

#### 4. Enable Image Verification

Use cosign to verify image signatures:

```bash
# Verify image signature
cosign verify --key cosign.pub authzed/spicedb:v1.39.0

# Use admission controller to enforce verification
# Example: Kyverno policy
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-spicedb-image
spec:
  validationFailureAction: enforce
  rules:
  - name: verify-signature
    match:
      resources:
        kinds:
        - Pod
    verifyImages:
    - imageReferences:
      - "authzed/spicedb:*"
      attestors:
      - entries:
        - keys:
            publicKeys: |-
              -----BEGIN PUBLIC KEY-----
              ...
              -----END PUBLIC KEY-----
```

### Image Policy Enforcement

#### OPA Gatekeeper Example

```yaml
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: allowedrepos
spec:
  crd:
    spec:
      names:
        kind: AllowedRepos
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package allowedrepos
      violation[{"msg": msg}] {
        container := input.review.object.spec.containers[_]
        not startswith(container.image, "authzed/")
        msg := sprintf("image '%v' not from approved registry", [container.image])
      }

---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: AllowedRepos
metadata:
  name: spicedb-repo-only
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    namespaces: ["spicedb"]
```

#### Kyverno Example

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: allowed-registries
spec:
  validationFailureAction: enforce
  rules:
  - name: validate-registry
    match:
      resources:
        kinds:
        - Pod
        namespaces:
        - spicedb
    validate:
      message: "Images must be from authzed registry"
      pattern:
        spec:
          containers:
          - image: "authzed/*"
```

## Resource Limits

Enforce resource limits to prevent resource exhaustion attacks:

```yaml
resources:
  limits:
    cpu: 2000m
    memory: 4Gi
  requests:
    cpu: 1000m
    memory: 1Gi
```

### Why Resource Limits Matter

- Prevents DoS via resource exhaustion
- Ensures fair resource sharing
- Protects cluster stability
- Required for Guaranteed QoS

### QoS Classes

#### Guaranteed QoS (Recommended for Production)

```yaml
resources:
  limits:
    cpu: 2000m
    memory: 4Gi
  requests:
    cpu: 2000m    # Same as limits
    memory: 4Gi   # Same as limits
```

#### Burstable QoS

```yaml
resources:
  limits:
    cpu: 2000m
    memory: 4Gi
  requests:
    cpu: 1000m    # Less than limits
    memory: 1Gi   # Less than limits
```

### Resource Quotas

Limit total resources in namespace:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: spicedb-quota
  namespace: spicedb
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    persistentvolumeclaims: "5"
```

## AppArmor and SELinux

### AppArmor

```yaml
podAnnotations:
  container.apparmor.security.beta.kubernetes.io/spicedb: runtime/default
```

### SELinux

```yaml
podSecurityContext:
  seLinuxOptions:
    level: "s0:c123,c456"
```

## Runtime Security Monitoring

### Falco Rules

```yaml
# Detect unexpected file writes
- rule: Write below root
  desc: Detect any write below root directory
  condition: >
    container.id != host and
    fd.name startswith "/" and
    evt.type in (write, rename, unlink) and
    container.image.repository = "authzed/spicedb"
  output: >
    File write detected in SpiceDB container
    (user=%user.name command=%proc.cmdline file=%fd.name)
  priority: WARNING

# Detect unexpected network connections
- rule: Unexpected outbound connection
  desc: Detect outbound connection from SpiceDB to unexpected destination
  condition: >
    container.image.repository = "authzed/spicedb" and
    fd.type = ipv4 and
    fd.sip != "0.0.0.0" and
    fd.sport != 0 and
    not fd.dip in (database_ips)
  output: >
    Unexpected outbound connection from SpiceDB
    (connection=%fd.name user=%user.name)
  priority: WARNING
```

### Tetragon Policies

```yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: spicedb-monitoring
spec:
  kprobes:
  - call: "sys_execve"
    syscall: true
    selectors:
    - matchNamespaces:
      - namespace: spicedb
        operator: In
      matchBinaries:
      - operator: "NotIn"
        values:
        - "/usr/local/bin/spicedb"
```

## Pod Disruption Budgets

Ensure availability during maintenance:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: spicedb-pdb
  namespace: spicedb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: spicedb
```

## Additional Security Configurations

### Priority Classes

```yaml
priorityClassName: system-cluster-critical
```

### Topology Spread Constraints

```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: kubernetes.io/hostname
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app.kubernetes.io/name: spicedb
```

### Node Affinity

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: workload-type
          operator: In
          values:
          - secure
```

## Security Best Practices Checklist

- [ ] Pod Security Standards enforced (restricted profile)
- [ ] Non-root containers configured
- [ ] Read-only root filesystem enabled
- [ ] All capabilities dropped
- [ ] Seccomp profile configured
- [ ] Resource limits set
- [ ] Specific image tags used (not latest)
- [ ] Image scanning enabled
- [ ] Image verification configured
- [ ] Pod disruption budgets configured
- [ ] Runtime security monitoring deployed
- [ ] AppArmor/SELinux configured (if available)

## Additional Resources

- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
- [Falco Rules](https://falco.org/docs/rules/)
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/)
- [Kyverno](https://kyverno.io/)
