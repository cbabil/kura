# Kura Desktop interface (bun, Vite, React, MUI). See ADR-023.
# `make dev` runs it against the in-browser mock API; `make build` writes dist/
# for kura-desktopd to embed.
SHELL := /bin/bash
BUN := source ~/source/reactvenv/bin/activate 2>/dev/null; bun

.PHONY: install dev build test coverage e2e lint format clean

install:
	$(BUN) install

dev:
	VITE_MOCK=1 $(BUN) x vite

build:
	$(BUN) run build

test:
	$(BUN) run test

coverage:
	$(BUN) run coverage

e2e:
	$(BUN) run e2e

lint:
	$(BUN) run lint

format:
	$(BUN) run format

clean:
	rm -rf dist dist-mock coverage playwright-report test-results
