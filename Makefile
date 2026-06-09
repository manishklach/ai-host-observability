PREFIX ?= /opt/ai-host-observability
SYSTEMD_DIR ?= /etc/systemd/system

.PHONY: test test-bats lint smoke install uninstall format check-deps validate-prometheus validate-grafana triage-smoke

check-deps:
	@echo "Checking required dependencies..."
	@missing=0; \
	for cmd in bash node_exporter journalctl ethtool; do \
		if ! command -v "$$cmd" >/dev/null 2>&1; then \
			echo "  MISSING: $$cmd"; \
			missing=1; \
		else \
			echo "  FOUND: $$cmd"; \
		fi; \
	done; \
	for opt in nvidia-smi rocm-smi intel_gpu_top; do \
		if command -v "$$opt" >/dev/null 2>&1; then \
			echo "  FOUND (optional): $$opt"; \
		else \
			echo "  NOT FOUND (optional): $$opt"; \
		fi; \
	done; \
	if mountpoint -q /sys/kernel/debug 2>/dev/null; then \
		echo "  FOUND: debugfs mounted at /sys/kernel/debug"; \
	else \
		echo "  NOT FOUND: debugfs not mounted (fw_pages_total unavailable)"; \
	fi; \
	if [[ -f /sys/fs/cgroup/memory.current ]]; then \
		echo "  FOUND: cgroup v2 memory controller"; \
	elif [[ -f /sys/fs/cgroup/memory/memory.usage_in_bytes ]]; then \
		echo "  FOUND: cgroup v1 memory controller"; \
	else \
		echo "  NOT FOUND: cgroup memory controller"; \
	fi; \
	exit $$missing

test: lint
	@if ! command -v bats >/dev/null 2>&1; then \
		echo "bats is required for make test. Install bats, or run make lint and make smoke."; \
		exit 1; \
	fi
	$(MAKE) test-bats

test-bats:
	bats tests/

lint:
	find scripts tests -name '*.sh' -print0 | xargs -0 -n1 bash -n
	@if command -v shellcheck >/dev/null 2>&1; then \
		SHELLCHECK_OPTS='-x -e SC2249,SC2250,SC2310,SC2312' shellcheck scripts/*.sh tests/helpers.bash tests/*.bats; \
	else \
		echo "Skipping shellcheck: not installed"; \
	fi
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -d scripts/ tests/; \
	else \
		echo "Skipping shfmt: not installed"; \
	fi

smoke:
	OUT_DIR=/tmp/ai-host-observability-prom bash scripts/collect-all.sh

validate-prometheus:
	@if command -v promtool >/dev/null 2>&1; then \
		promtool check rules prometheus/alerts.yml; \
		promtool check rules prometheus/rules.yml; \
		promtool check rules prometheus/recording-rules.yml; \
	else \
		echo "Skipping Prometheus validation: promtool not installed"; \
	fi

validate-grafana:
	@if command -v jq >/dev/null 2>&1; then \
		jq empty grafana/*.json; \
	else \
		echo "Skipping Grafana validation: jq not installed"; \
	fi

triage-smoke:
	OUT_DIR=tests/fixtures/prom/memory_pressure bash scripts/ai-host-triage.sh

install:
	mkdir -p $(PREFIX)
	cp -R README.md CHANGELOG.md CONTRIBUTING.md SECURITY.md LICENSE TESTING.md KERNEL_DEBUGGING.md RELEASE.md Makefile docs examples grafana prometheus scripts deploy $(PREFIX)/
	@if mkdir -p $(SYSTEMD_DIR) 2>/dev/null && [ -w "$(SYSTEMD_DIR)" ]; then \
		install -m 0644 deploy/systemd/ai-host-observability.service $(SYSTEMD_DIR)/; \
		install -m 0644 deploy/systemd/ai-host-observability.timer $(SYSTEMD_DIR)/; \
	else \
		echo "Skipping systemd unit install to $(SYSTEMD_DIR)"; \
	fi

uninstall:
	rm -rf $(PREFIX)
	rm -f $(SYSTEMD_DIR)/ai-host-observability.service $(SYSTEMD_DIR)/ai-host-observability.timer

format:
	if command -v shfmt >/dev/null 2>&1; then find scripts tests -name '*.sh' -print0 | xargs -0 shfmt -w; fi
	if command -v jq >/dev/null 2>&1; then tmp=$$(mktemp); jq . grafana/ai-host-overview.json > "$$tmp" && mv "$$tmp" grafana/ai-host-overview.json; fi
