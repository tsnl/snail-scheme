.DEFAULT_GOAL := check
.PHONY: format check test benchmark

CHIBI ?= chibi-scheme
EMACS ?= emacs
NIXFMT ?= nixfmt
BENCH_OUTPUT ?= /tmp/lofi-benchmarks

test:
	"$(CHIBI)" -D snail-tests -I wasm-native/scheme -I wasm-native/tests wasm-native/tests/host.scm
	"$(CHIBI)" -D snail-tests -I src -I wasm-native/scheme -I tests -I wasm-native/tests tests/lofi/host.scm
	"$(CHIBI)" -D snail-tests -I src -I wasm-native/scheme -I tests -I wasm-native/tests -I benchmarks tests/lofi-benchmarks.scm
	"$(CHIBI)" -D snail-tests -I src -I wasm-native/scheme -I tests -I wasm-native/tests -I benchmarks benchmarks/wasm-reference/tests/audits.scm

benchmark:
	"$(CHIBI)" -I src -I wasm-native/scheme -I benchmarks benchmarks/lofi/runner.scm prepare --output "$(BENCH_OUTPUT)"
	"$(CHIBI)" -I src -I wasm-native/scheme -I benchmarks benchmarks/lofi/runner.scm validate --output "$(BENCH_OUTPUT)"

format:
	EMACS="$(EMACS)" find src lib tests examples wasm-native/scheme wasm-native/tests -type f \( -name '*.scm' -o -name '*.sld' -o -name '*.lofi' \) -exec ./scripts/format-scheme --write {} +
	$(NIXFMT) shell.nix

check:
	EMACS="$(EMACS)" find src lib tests examples wasm-native/scheme wasm-native/tests -type f \( -name '*.scm' -o -name '*.sld' -o -name '*.lofi' \) -exec ./scripts/format-scheme --check {} +
	awk -v limit=100 -f scripts/check-line-length.awk src/lofi/ir.sld
	$(NIXFMT) --check shell.nix
