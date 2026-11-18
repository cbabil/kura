# Kura Desktop: the Rust server (kura-desktopd, kura-helper) and the interface
# in web/. See ADR-023 and ADR-024. Needs rustup's stable toolchain,
# cargo-llvm-cov, cargo-deny and cargo-zigbuild (with zig) for dist targets.
SHELL := /bin/bash
CARGO := PATH="$$(dirname "$$(rustup which cargo)"):$$PATH" cargo
# glibc the helper may need at most: Debian 12's, older than trixie's 2.41.
GLIBC := 2.36
# Where the target's libpam.so lives (libpam0g-dev for that architecture).
# Only that file is handed to the linker, so the host's glibc stays out.
PAM_SYSTEM_DIR ?= /usr/lib/$(TRIPLE)-linux-gnu
DEV_LISTEN ?= 127.0.0.1:8443

.PHONY: test test-live test-pam e2e coverage lint format dev web build dist dist-amd64 dist-arm64 clean

test:
	$(CARGO) test --workspace
	$(CARGO) test -p kura-desktopd --features dev-auth

# Linux only: the readers and systemd against this machine.
test-live:
	$(CARGO) test --workspace -- --ignored live

# Linux only: PAM against throwaway users named in KURA_PAM_USER,
# KURA_PAM_EXPIRED_USER and KURA_PAM_PASSWORD (see CI). The test is built as
# the user; only the finished test binary runs as root.
test-pam:
	bin="$$($(CARGO) test -p kura-helper --lib --no-run --message-format=json \
	  | jq -r 'select(.profile.test == true and .executable != null) | .executable')"; \
	sudo --preserve-env=KURA_PAM_USER,KURA_PAM_EXPIRED_USER,KURA_PAM_PASSWORD "$$bin" --ignored pam::

# Linux only: both binaries end to end; KURA_PAM_PASSWORD is E2E_USER's.
e2e: build
	ci/e2e.sh $(E2E_USER)

coverage:
	$(CARGO) llvm-cov --workspace --fail-under-lines 90 --ignore-filename-regex '(main\.rs|/tests/|tests\.rs)'

lint:
	$(CARGO) fmt --all --check
	$(CARGO) clippy --workspace --all-targets -- -D warnings
	$(CARGO) clippy -p kura-desktopd --all-targets --features dev-auth -- -D warnings
	$(CARGO) deny check

format:
	$(CARGO) fmt --all

web:
	$(MAKE) -C web install build

# desktopd with the fake password check over plain HTTP, serving web/dist and
# reading the fixture tree in dev/root (a Mac has no /proc). Sign in with any
# user name and the password "kura".
dev: web
	$(CARGO) run -p kura-desktopd --features dev-auth -- --http --listen $(DEV_LISTEN) --root dev/root --state-dir target/dev-state

build:
	$(CARGO) build --release --workspace

# Linux binaries for the image, with the interface embedded: desktopd static
# (musl), the helper against glibc and libpam (PAM_SYSTEM_DIR is the target's
# libpam directory).
dist-amd64: TRIPLE := x86_64
dist-arm64: TRIPLE := aarch64
dist-amd64 dist-arm64: web
	$(CARGO) zigbuild --release -p kura-desktopd --target $(TRIPLE)-unknown-linux-musl
	mkdir -p target/pam/$(TRIPLE)
	cp -L $(PAM_SYSTEM_DIR)/libpam.so target/pam/$(TRIPLE)/
	RUSTFLAGS="-L $(CURDIR)/target/pam/$(TRIPLE)" $(CARGO) zigbuild --release -p kura-helper --target $(TRIPLE)-unknown-linux-gnu.$(GLIBC)
	mkdir -p dist/$(TRIPLE)
	cp target/$(TRIPLE)-unknown-linux-musl/release/kura-desktopd target/$(TRIPLE)-unknown-linux-gnu/release/kura-helper dist/$(TRIPLE)/

# build.sh calls `make dist ARCH=x86_64|aarch64`.
dist:
	@case "$(ARCH)" in x86_64) $(MAKE) dist-amd64 ;; aarch64) $(MAKE) dist-arm64 ;; \
	  *) echo "ARCH must be x86_64 or aarch64" >&2; exit 1 ;; esac

clean:
	$(CARGO) clean
	rm -rf dist
