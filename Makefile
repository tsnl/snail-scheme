.DEFAULT_GOAL := check
.PHONY: format check test benchmark

CHIBI ?= chibi-scheme
EMACS ?= emacs
NIXFMT ?= nixfmt
BENCH_OUTPUT ?= build/sfir-benchmarks

test:
	"$(CHIBI)" -D snail-tests -I src -I tests tests/sfir/host.scm

benchmark:
	python3 benchmarks/sfir/runner.py prepare --output "$(BENCH_OUTPUT)"
	python3 benchmarks/sfir/runner.py validate --output "$(BENCH_OUTPUT)"

format:
	EMACS="$(EMACS)" find src lib tests examples -type f \( -name '*.scm' -o -name '*.sld' -o -name '*.sfir' \) -exec ./scripts/format-scheme --write {} +
	$(NIXFMT) shell.nix

check:
	EMACS="$(EMACS)" find src lib tests examples -type f \( -name '*.scm' -o -name '*.sld' -o -name '*.sfir' \) -exec ./scripts/format-scheme --check {} +
	awk -v limit=100 -f scripts/check-line-length.awk src/snail-scheme/ir.sld
	$(NIXFMT) --check shell.nix
