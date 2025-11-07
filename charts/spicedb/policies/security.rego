# OPA Security Policies for SpiceDB Helm Chart
# These policies enforce Kubernetes security best practices

package main

import rego.v1

# Deny privileged containers
deny contains msg if {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	container.securityContext.privileged == true
	msg := sprintf("Container '%s' is running in privileged mode which is not allowed", [container.name])
}

# Deny use of latest image tag
deny contains msg if {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	endswith(container.image, ":latest")
	msg := sprintf("Container '%s' uses 'latest' tag which is not allowed for production", [container.name])
}

# Deny use of no image tag
deny contains msg if {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	not contains(container.image, ":")
	msg := sprintf("Container '%s' has no tag specified, explicit tags are required", [container.name])
}

# Deny missing resource limits
deny contains msg if {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	not container.resources.limits
	msg := sprintf("Container '%s' has no resource limits defined", [container.name])
}

# Deny missing resource requests
deny contains msg if {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	not container.resources.requests
	msg := sprintf("Container '%s' has no resource requests defined", [container.name])
}

# Warn on missing liveness probe
warn contains msg if {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	not container.livenessProbe
	msg := sprintf("Container '%s' should have a livenessProbe defined", [container.name])
}

# Warn on missing readiness probe
warn contains msg if {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	not container.readinessProbe
	msg := sprintf("Container '%s' should have a readinessProbe defined", [container.name])
}

# Warn on missing recommended labels
warn contains msg if {
	input.kind == "Deployment"
	not input.metadata.labels["app.kubernetes.io/name"]
	msg := "Deployment should have 'app.kubernetes.io/name' label"
}

warn contains msg if {
	input.kind == "Deployment"
	not input.metadata.labels["app.kubernetes.io/version"]
	msg := "Deployment should have 'app.kubernetes.io/version' label"
}

warn contains msg if {
	input.kind == "Deployment"
	not input.metadata.labels["app.kubernetes.io/managed-by"]
	msg := "Deployment should have 'app.kubernetes.io/managed-by' label"
}

# Deny containers running as root
deny contains msg if {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	not input.spec.template.spec.securityContext.runAsNonRoot
	not container.securityContext.runAsNonRoot
	msg := sprintf("Container '%s' should explicitly set runAsNonRoot: true", [container.name])
}

# Deny containers with writable root filesystem
deny contains msg if {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	not container.securityContext.readOnlyRootFilesystem
	msg := sprintf("Container '%s' should have readOnlyRootFilesystem: true for security", [container.name])
}

# Warn on host network usage
warn contains msg if {
	input.kind == "Deployment"
	input.spec.template.spec.hostNetwork == true
	msg := "Deployment uses hostNetwork which may have security implications"
}

# Warn on host PID namespace
warn contains msg if {
	input.kind == "Deployment"
	input.spec.template.spec.hostPID == true
	msg := "Deployment uses hostPID which may have security implications"
}

# Deny capabilities that shouldn't be added
deny contains msg if {
	input.kind == "Deployment"
	some container in input.spec.template.spec.containers
	some capability in container.securityContext.capabilities.add
	dangerous_capabilities := {"SYS_ADMIN", "NET_ADMIN", "SYS_PTRACE", "SYS_MODULE"}
	dangerous_capabilities[capability]
	msg := sprintf("Container '%s' adds dangerous capability '%s'", [container.name, capability])
}
