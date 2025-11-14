# Pod Scheduling Problems

[← Back to Troubleshooting Index](index.md)

This guide covers issues with pod placement, scheduling, and high availability in SpiceDB deployments.

## Pods Stuck in Pending

**Symptoms:**

```text
Status: Pending
0/3 nodes are available
```

**Diagnosis:**

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=spicedb

# Describe pod for details
kubectl describe pods -l app.kubernetes.io/name=spicedb

# Common reasons shown in events:
# - Insufficient CPU/memory
# - No nodes matching nodeSelector
# - Taints not tolerated
# - Anti-affinity constraints
```

**Solutions:**

- **Insufficient resources**:

  ```bash
  # Check node resources
  kubectl describe nodes

  # Reduce resource requests
  helm upgrade spicedb charts/spicedb \
    --set resources.requests.cpu=500m \
    --set resources.requests.memory=512Mi \
    --reuse-values
  ```

- **Anti-affinity constraints too strict**:

  ```bash
  # Change from required to preferred anti-affinity
  helm upgrade spicedb charts/spicedb \
    --set 'affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].weight=100' \
    --reuse-values

  # Or disable anti-affinity temporarily
  helm upgrade spicedb charts/spicedb \
    --set affinity=null \
    --reuse-values
  ```

- **NodeSelector/Taints mismatch**:

  ```bash
  # Check node labels
  kubectl get nodes --show-labels

  # Remove nodeSelector
  helm upgrade spicedb charts/spicedb \
    --set nodeSelector=null \
    --reuse-values

  # Or add tolerations
  helm upgrade spicedb charts/spicedb \
    --set 'tolerations[0].key=dedicated' \
    --set 'tolerations[0].operator=Equal' \
    --set 'tolerations[0].value=spicedb' \
    --set 'tolerations[0].effect=NoSchedule' \
    --reuse-values
  ```

## Pods Not Distributed Across Zones

**Symptoms:**

- All pods running in single availability zone
- No geographic redundancy

**Diagnosis:**

```bash
# Check pod distribution across zones
kubectl get pods -l app.kubernetes.io/name=spicedb \
  -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,ZONE:.metadata.labels.topology\\.kubernetes\\.io/zone

# Check topology spread constraints
helm get values spicedb | grep -A 10 topologySpreadConstraints
```

**Solutions:**

```bash
# Add topology spread constraints
helm upgrade spicedb charts/spicedb \
  --set 'topologySpreadConstraints[0].maxSkew=1' \
  --set 'topologySpreadConstraints[0].topologyKey=topology.kubernetes.io/zone' \
  --set 'topologySpreadConstraints[0].whenUnsatisfiable=ScheduleAnyway' \
  --reuse-values

# Use DoNotSchedule for hard requirement
# --set 'topologySpreadConstraints[0].whenUnsatisfiable=DoNotSchedule'
```

## HPA Not Scaling

**Symptoms:**

- HPA shows "unknown" for metrics
- Pods not scaling despite high CPU/memory
- `kubectl get hpa` shows `<unknown>` for TARGETS

**Diagnosis:**

```bash
# Check HPA status
kubectl get hpa spicedb
kubectl describe hpa spicedb

# Check if metrics-server is running
kubectl get apiservice v1beta1.metrics.k8s.io

# Check if metrics are available
kubectl top pods -l app.kubernetes.io/name=spicedb

# Check metrics-server logs
kubectl logs -n kube-system -l k8s-app=metrics-server
```

**Solutions:**

- **Install metrics-server if missing**:

  ```bash
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

  # For clusters with self-signed certs, add --kubelet-insecure-tls
  ```

- **Verify resource requests are set** (HPA requires them):

  ```bash
  helm get values spicedb | grep -A 5 resources

  # Ensure requests are specified
  helm upgrade spicedb charts/spicedb \
    --set resources.requests.cpu=1000m \
    --set resources.requests.memory=1Gi \
    --reuse-values
  ```

- **Check HPA configuration**:

  ```bash
  # View HPA details
  kubectl get hpa spicedb -o yaml

  # Verify targetCPUUtilizationPercentage is reasonable
  helm upgrade spicedb charts/spicedb \
    --set autoscaling.targetCPUUtilizationPercentage=80 \
    --reuse-values
  ```

## PDB Blocking Drains

**Symptoms:**

```text
Cannot evict pod: pod disruption budget "spicedb" violation
error when evicting pod: "spicedb-xxx"
```

**Diagnosis:**

```bash
# Check PDB status
kubectl get pdb spicedb
kubectl describe pdb spicedb

# Check current availability
kubectl get pdb spicedb -o yaml
```

**Solutions:**

- **Temporarily increase replicas**:

  ```bash
  # Increase replicas to allow more disruptions
  helm upgrade spicedb charts/spicedb \
    --set replicaCount=5 \
    --reuse-values

  # Wait for new pods to be ready
  kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=spicedb

  # Now drain should work
  kubectl drain <node-name> --ignore-daemonsets
  ```

- **Adjust PDB settings**:

  ```bash
  # Increase maxUnavailable
  helm upgrade spicedb charts/spicedb \
    --set podDisruptionBudget.maxUnavailable=2 \
    --reuse-values
  ```

- **Temporarily disable PDB for emergency maintenance**:

  ```bash
  # Delete PDB (will be recreated on next helm upgrade)
  kubectl delete pdb spicedb

  # Drain node
  kubectl drain <node-name> --ignore-daemonsets
  ```

## See Also

- [Performance Issues](performance-issues.md) - For resource exhaustion problems
- [Connection Issues](connection-issues.md) - For service availability issues
