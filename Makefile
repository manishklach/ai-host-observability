PREFIX ?= /opt/ai-host-observability
SYSTEMD_DIR ?= /etc/systemd/system

.PHONY: test test-bats lint smoke install uninstall format

test:
	@if ! command -v bats >/dev/null 2>&1; then \
		echo "bats is required for make test. Install bats, or run make lint and make smoke."; \
		exit 1; \
	fi
	$(MAKE) test-bats

test-bats:
	bats tests/

lint:
	find scripts tests -name '*.sh' -print0 | xargs -0 -n1 bash -n
	if command -v shellcheck >/dev/null 2>&1; then find scripts tests -name '*.sh' -print0 | xargs -0 shellcheck; fi

smoke:
	OUT_DIR=/tmp/ai-host-observability-prom bash scripts/collect-all.sh

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
