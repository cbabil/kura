# Kura — the checks CI runs, runnable before a push. `make check` is what
# .github/workflows/ci.yml runs (lint and test), so the two cannot differ.

SHELL := /bin/bash
LINT_FILES := packages/os-security/src/os-security packages/os-security/src/lib/*.sh \
	packages/os-config/src/os-config \
	packages/os-desktop/src/os-settings packages/os-desktop/src/os-apps \
	scripts/common/*.sh scripts/common/kura-issue scripts/common/migrations/*.sh \
	scripts/packaging/*.sh scripts/release/*.sh \
	scripts/pc-installer/*.sh scripts/pc-installer/init scripts/pc-installer/udhcpc.script \
	scripts/rpi5/*.sh scripts/x86_64/*.sh tests/boot/*.sh

.PHONY: check lint test build clean

check: lint test ## everything CI's lint and test jobs run

lint: ## shellcheck, with CI's own settings
	shellcheck --severity=warning $(LINT_FILES)

test: ## the shell tests
	bats tests/shell/*.bats

build: ## build every image (Debian or Ubuntu only)
	./build.sh build all

clean: ## remove build output
	./build.sh clean

catalog-check: ## the App Catalog's pinned images exist (asks their registries; needs docker and a network)
	@failed=0; for file in packages/os-desktop/catalog/*/compose.yaml; do \
		image="$$(sed -n 's/^    image: //p' "$$file")"; \
		if docker manifest inspect "$$image" >/dev/null 2>&1; then echo "ok      $$image"; else echo "MISSING $$image"; failed=1; fi; \
	done; exit $$failed
