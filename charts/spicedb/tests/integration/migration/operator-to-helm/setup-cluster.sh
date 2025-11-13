#!/bin/bash
# setup-cluster.sh - Set up test infrastructure for operator-to-helm migration tests
# Creates kind cluster, installs operator, deploys PostgreSQL, and prepares test environment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CLUSTER_NAME="${KIND_CLUSTER_NAME:-spicedb-migration-test}"
export NAMESPACE="spicedb-migration-test"
OPERATOR_VERSION="${SPICEDB_OPERATOR_VERSION:-v1.30.0}"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[SETUP]${NC} $1"; }
log_error() { echo -e "${RED}[SETUP ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[SETUP WARN]${NC} $1"; }
log_debug() { echo -e "${BLUE}[SETUP DEBUG]${NC} $1"; }
log_section() { echo -e "${CYAN}[====]${NC} $1 ${CYAN}[====]${NC}"; }

# Cleanup on exit
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Setup failed with exit code $exit_code"
        log_info "Run ./cleanup-cluster.sh to clean up resources"
    fi
}
trap cleanup_on_error EXIT

# Check prerequisites
check_prerequisites() {
    log_section "Checking Prerequisites"

    local missing=0

    if ! command -v kind >/dev/null 2>&1; then
        log_error "kind not found. Install from: https://kind.sigs.k8s.io/"
        ((missing++))
    else
        log_debug "kind: $(kind version 2>&1 | head -1)"
    fi

    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl not found"
        ((missing++))
    else
        log_debug "kubectl: $(kubectl version --client --short 2>&1 | head -1)"
    fi

    if ! command -v helm >/dev/null 2>&1; then
        log_error "helm not found"
        ((missing++))
    else
        log_debug "helm: $(helm version --short)"
    fi

    if ! command -v docker >/dev/null 2>&1; then
        log_error "docker not found"
        ((missing++))
    else
        log_debug "docker: $(docker version --format '{{.Client.Version}}' 2>/dev/null || echo 'unknown')"
    fi

    if [ $missing -gt 0 ]; then
        log_error "$missing required tool(s) missing"
        exit 1
    fi

    log_info "All prerequisites satisfied"
}

# Create kind cluster
create_kind_cluster() {
    log_section "Creating Kind Cluster"

    # Check if cluster already exists
    if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
        log_warn "Cluster $CLUSTER_NAME already exists"
        read -p "Delete and recreate? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deleting existing cluster..."
            kind delete cluster --name "$CLUSTER_NAME"
        else
            log_info "Using existing cluster"
            kubectl config use-context "kind-${CLUSTER_NAME}" || true
            return 0
        fi
    fi

    log_info "Creating kind cluster: $CLUSTER_NAME"
    kind create cluster \
        --name "$CLUSTER_NAME" \
        --config "$SCRIPT_DIR/kind-config.yaml" \
        --wait 120s

    # Set kubectl context
    kubectl config use-context "kind-${CLUSTER_NAME}"

    log_info "Waiting for cluster to be ready..."
    kubectl wait --for=condition=Ready nodes --all --timeout=120s

    log_info "Kind cluster created successfully"
}

# Install cert-manager (required by SpiceDB operator)
install_cert_manager() {
    log_section "Installing cert-manager"

    # Check if already installed
    if kubectl get namespace cert-manager >/dev/null 2>&1; then
        log_info "cert-manager already installed"
        return 0
    fi

    log_info "Installing cert-manager..."

    # Install cert-manager CRDs and controller
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

    log_info "Waiting for cert-manager to be ready..."
    kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=300s

    log_info "cert-manager installed successfully"
}

# Install SpiceDB operator
install_spicedb_operator() {
    log_section "Installing SpiceDB Operator"

    # Check if already installed
    if kubectl get crd spicedbclusters.authzed.com >/dev/null 2>&1; then
        log_info "SpiceDB operator CRDs already installed"

        # Check if controller is running
        if kubectl get pods -n spicedb-operator-system -l control-plane=controller-manager --no-headers 2>/dev/null | grep -q Running; then
            log_info "SpiceDB operator controller already running"
            return 0
        fi
    fi

    log_info "Installing SpiceDB operator (version: $OPERATOR_VERSION)..."

    # Install operator from GitHub releases
    # Note: Using latest if version not specified
    if [ "$OPERATOR_VERSION" = "latest" ]; then
        OPERATOR_URL="https://github.com/authzed/spicedb-operator/releases/latest/download/bundle.yaml"
    else
        OPERATOR_URL="https://github.com/authzed/spicedb-operator/releases/download/${OPERATOR_VERSION}/bundle.yaml"
    fi

    log_debug "Operator URL: $OPERATOR_URL"

    kubectl apply -f "$OPERATOR_URL" || {
        log_error "Failed to install operator from $OPERATOR_URL"
        log_info "Falling back to latest release..."
        kubectl apply -f https://github.com/authzed/spicedb-operator/releases/latest/download/bundle.yaml
    }

    log_info "Waiting for operator controller to be ready..."
    kubectl wait --for=condition=Available deployment \
        -n spicedb-operator-system \
        spicedb-operator-controller-manager \
        --timeout=300s || {
        log_warn "Operator deployment wait timed out, checking status..."
        kubectl get pods -n spicedb-operator-system
    }

    # Verify CRDs installed
    log_debug "Verifying CRDs..."
    kubectl get crd spicedbclusters.authzed.com >/dev/null || {
        log_error "SpiceDBCluster CRD not found"
        return 1
    }

    log_info "SpiceDB operator installed successfully"
}

# Deploy PostgreSQL backend
deploy_postgresql() {
    log_section "Deploying PostgreSQL"

    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_info "Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE"
    fi

    log_info "Deploying PostgreSQL StatefulSet..."

    # Deploy PostgreSQL using bitnami chart
    if ! helm repo list | grep -q bitnami; then
        log_debug "Adding bitnami Helm repository..."
        helm repo add bitnami https://charts.bitnami.com/bitnami
    fi

    helm repo update bitnami >/dev/null 2>&1

    # Check if already deployed
    if helm list -n "$NAMESPACE" | grep -q "^postgresql"; then
        log_info "PostgreSQL already deployed"
    else
        log_info "Installing PostgreSQL via Helm..."
        helm install postgresql bitnami/postgresql \
            --namespace "$NAMESPACE" \
            --set auth.username=spicedb \
            --set auth.password=testpassword123 \
            --set auth.database=spicedb \
            --set primary.persistence.enabled=true \
            --set primary.persistence.size=1Gi \
            --wait --timeout=5m
    fi

    log_info "Waiting for PostgreSQL to be ready..."
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=postgresql \
        -n "$NAMESPACE" \
        --timeout=300s

    # Verify PostgreSQL connectivity
    log_info "Verifying PostgreSQL connectivity..."
    local max_attempts=10
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if kubectl exec -n "$NAMESPACE" postgresql-0 -- \
            psql -U spicedb -d spicedb -c "SELECT 1" >/dev/null 2>&1; then
            log_info "PostgreSQL is ready and accepting connections"
            break
        fi

        log_debug "Attempt $attempt/$max_attempts to connect to PostgreSQL..."
        sleep 3
        ((attempt++))
    done

    if [ $attempt -gt $max_attempts ]; then
        log_error "Failed to connect to PostgreSQL after $max_attempts attempts"
        return 1
    fi

    log_info "PostgreSQL deployed successfully"
}

# Create test namespace and RBAC
setup_test_namespace() {
    log_section "Setting up Test Namespace"

    # Create namespace
    if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_info "Namespace $NAMESPACE already exists"
    else
        log_info "Creating namespace: $NAMESPACE"
        kubectl create namespace "$NAMESPACE"
    fi

    # Label namespace
    log_debug "Labeling namespace..."
    kubectl label namespace "$NAMESPACE" \
        migration-test=true \
        app=spicedb \
        --overwrite

    # Create ServiceAccount for tests
    log_debug "Creating ServiceAccount for tests..."
    kubectl apply -n "$NAMESPACE" -f - <<EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: spicedb-migration-test
  namespace: $NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: spicedb-migration-test
  namespace: $NAMESPACE
rules:
  - apiGroups: [""]
    resources: ["pods", "services", "secrets", "configmaps"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  - apiGroups: ["authzed.com"]
    resources: ["spicedbclusters"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: spicedb-migration-test
  namespace: $NAMESPACE
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: spicedb-migration-test
subjects:
  - kind: ServiceAccount
    name: spicedb-migration-test
    namespace: $NAMESPACE
EOF

    log_info "Test namespace and RBAC configured"
}

# Create test secrets
create_test_secrets() {
    log_section "Creating Test Secrets"

    log_info "Applying test secrets..."
    kubectl apply -f "$SCRIPT_DIR/fixtures/test-secrets.yaml"

    # Verify secrets created
    log_debug "Verifying secrets..."
    for secret in spicedb-operator-config postgres-uri spicedb-grpc-tls spicedb-dispatch-tls; do
        if kubectl get secret "$secret" -n "$NAMESPACE" >/dev/null 2>&1; then
            log_debug "Secret $secret: created"
        else
            log_warn "Secret $secret: not found"
        fi
    done

    log_info "Test secrets created"
}

# Main setup function
main() {
    log_section "SpiceDB Operator to Helm Migration - Test Infrastructure Setup"
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Namespace: $NAMESPACE"
    log_info "Operator Version: $OPERATOR_VERSION"
    echo ""

    check_prerequisites
    create_kind_cluster
    install_cert_manager
    install_spicedb_operator
    deploy_postgresql
    setup_test_namespace
    create_test_secrets

    log_section "Setup Complete"
    log_info "Cluster $CLUSTER_NAME is ready for migration testing"
    echo ""
    log_info "Cluster info:"
    kubectl cluster-info
    echo ""
    log_info "Resources in $NAMESPACE:"
    kubectl get all -n "$NAMESPACE"
    echo ""
    log_info "Next steps:"
    log_info "  1. Run basic migration test: ./test-basic-migration.sh"
    log_info "  2. Run all tests: ./run-all-tests.sh"
    log_info "  3. Cleanup when done: ./cleanup-cluster.sh"
}

main "$@"
