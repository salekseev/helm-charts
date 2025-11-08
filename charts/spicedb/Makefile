.PHONY: help test-unit test-integration test-local test-all clean

# Variables
KIND_CLUSTER_NAME ?= spicedb-test
HELM_RELEASE_NAME ?= spicedb

help:  ## Display this help message
	@echo "SpiceDB Helm Chart - Available targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Variables:"
	@echo "  KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME)"
	@echo "  HELM_RELEASE_NAME=$(HELM_RELEASE_NAME)"

test-unit:  ## Run Helm unit tests with helm-unittest
	@echo "Running Helm unit tests..."
	@helm unittest .

test-integration:  ## Run integration tests with Kind cluster
	@echo "Running integration tests..."
	@export KIND_CLUSTER_NAME=$(KIND_CLUSTER_NAME) && \
	export HELM_RELEASE_NAME=$(HELM_RELEASE_NAME) && \
	./tests/integration/migration-test.sh

test-local: test-unit  ## Run local tests (unit tests only)
	@echo "Local tests complete!"

test-all: test-unit test-integration  ## Run all tests (unit + integration)
	@echo "All tests complete!"

lint:  ## Run helm lint on chart
	@echo "Running helm lint..."
	@helm lint .

clean:  ## Clean up test artifacts
	@echo "Cleaning up test artifacts..."
	@rm -rf tests/integration/logs
	@kind delete cluster --name $(KIND_CLUSTER_NAME) 2>/dev/null || true
	@echo "Clean complete!"
