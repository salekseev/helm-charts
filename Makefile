.PHONY: help list-charts test-all clean

# Discover all charts in charts/ directory
CHARTS := $(wildcard charts/*)
CHART_NAMES := $(notdir $(CHARTS))

help:  ## Display this help message
	@echo "Helm Charts Repository - Available targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Available charts:"
	@for chart in $(CHART_NAMES); do \
		echo "  - $$chart"; \
	done
	@echo ""
	@echo "Per-chart targets:"
	@echo "  make <chart>-test-unit         - Run unit tests for specific chart"
	@echo "  make <chart>-test-integration  - Run integration tests for specific chart"
	@echo "  make <chart>-test-all          - Run all tests for specific chart"
	@echo "  make <chart>-lint              - Lint specific chart"
	@echo "  make <chart>-clean             - Clean specific chart artifacts"

list-charts:  ## List all available charts
	@echo "Available charts:"
	@for chart in $(CHART_NAMES); do \
		echo "  - $$chart"; \
	done

test-all:  ## Run all tests for all charts
	@for chart in $(CHART_NAMES); do \
		echo ""; \
		echo "==> Testing chart: $$chart"; \
		if [ -f "charts/$$chart/Makefile" ]; then \
			$(MAKE) -C "charts/$$chart" test-all || exit 1; \
		else \
			echo "No Makefile found for $$chart, skipping..."; \
		fi; \
	done

clean:  ## Clean all chart artifacts
	@for chart in $(CHART_NAMES); do \
		if [ -f "charts/$$chart/Makefile" ]; then \
			echo "Cleaning $$chart..."; \
			$(MAKE) -C "charts/$$chart" clean; \
		fi; \
	done

# Dynamic per-chart targets
define CHART_TARGETS
$(1)-test-unit:
	@echo "Running unit tests for $(1)..."
	@if [ -f "charts/$(1)/Makefile" ]; then \
		$(MAKE) -C "charts/$(1)" test-unit; \
	else \
		echo "No Makefile found for $(1)"; \
		exit 1; \
	fi

$(1)-test-integration:
	@echo "Running integration tests for $(1)..."
	@if [ -f "charts/$(1)/Makefile" ]; then \
		$(MAKE) -C "charts/$(1)" test-integration; \
	else \
		echo "No Makefile found for $(1)"; \
		exit 1; \
	fi

$(1)-test-all:
	@echo "Running all tests for $(1)..."
	@if [ -f "charts/$(1)/Makefile" ]; then \
		$(MAKE) -C "charts/$(1)" test-all; \
	else \
		echo "No Makefile found for $(1)"; \
		exit 1; \
	fi

$(1)-lint:
	@echo "Linting $(1)..."
	@if [ -f "charts/$(1)/Makefile" ]; then \
		$(MAKE) -C "charts/$(1)" lint; \
	else \
		helm lint "charts/$(1)"; \
	fi

$(1)-clean:
	@echo "Cleaning $(1)..."
	@if [ -f "charts/$(1)/Makefile" ]; then \
		$(MAKE) -C "charts/$(1)" clean; \
	fi

.PHONY: $(1)-test-unit $(1)-test-integration $(1)-test-all $(1)-lint $(1)-clean
endef

# Generate targets for each chart
$(foreach chart,$(CHART_NAMES),$(eval $(call CHART_TARGETS,$(chart))))
