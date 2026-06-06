PREFIX ?= /opt/ai-host-observability
SYSTEMD_DIR ?= /etc/systemd/system

.PHONY: test lint smoke install uninstall format

test:
	bash tests/test_exporters.sh
	bash tests/test_collect_all.sh

lint:
	find scripts tests -name '*.sh' -print0 | xargs -0 -n1 bash -n
	if command -v shellcheck >/dev/null 2>&1; then find scripts tests -name '*.sh' -print0 | xargs -0 shellcheck; fi

smoke:
	OUT_DIR=/tmp/ai-host-observability-prom bash scripts/collect-all.sh

install:
	mkdir -p $(PREFIX)
	cp -R README.md CHANGELOG.md CONTRIBUTING.md SECURITY.md LICENSE TESTING.md KERNEL_DEBUGGING.md docs grafana prometheus scripts deploy $(PREFIX)/
	install -m 0644 deploy/systemd/ai-host-observability.service $(SYSTEMD_DIR)/
	install -m 0644 deploy/systemd/ai-host-observability.timer $(SYSTEMD_DIR)/

uninstall:
	rm -rf $(PREFIX)
	rm -f $(SYSTEMD_DIR)/ai-host-observability.service $(SYSTEMD_DIR)/ai-host-observability.timer

format:
	if command -v shfmt >/dev/null 2>&1; then find scripts tests -name '*.sh' -print0 | xargs -0 shfmt -w; fi
	if command -v jq >/dev/null 2>&1; then tmp=$$(mktemp); jq . grafana/ai-host-overview.json > "$$tmp" && mv "$$tmp" grafana/ai-host-overview.json; fi

