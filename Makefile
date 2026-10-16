.DEFAULT_GOAL := check
.PHONY: format check test benchmark

CHIBI ?= chibi-scheme
EMACS ?= emacs
NIXFMT ?= nixfmt
BENCH_OUTPUT ?= /tmp/snail-sfir-benchmarks

test:
	"$(CHIBI)" -D snail-tests -I wasm-native/scheme -I wasm-native/tests wasm-native/tests/host.scm
	"$(CHIBI)" -D snail-tests -I src -I wasm-native/scheme -I tests -I wasm-native/tests tests/sfir/host.scm
	"$(CHIBI)" -D snail-tests -I src -I wasm-native/scheme -I tests -I wasm-native/tests -I benchmarks tests/sfir-benchmarks.scm
	"$(CHIBI)" -D snail-tests -I src -I wasm-native/scheme -I tests -I wasm-native/tests -I benchmarks benchmarks/wasm-reference/tests/audits.scm

benchmark:
	"$(CHIBI)" -I src -I wasm-native/scheme -I benchmarks benchmarks/sfir/runner.scm prepare --output "$(BENCH_OUTPUT)"
	"$(CHIBI)" -I src -I wasm-native/scheme -I benchmarks benchmarks/sfir/runner.scm validate --output "$(BENCH_OUTPUT)"

format:
	EMACS="$(EMACS)" find src lib tests examples wasm-native/scheme wasm-native/tests -type f \( -name '*.scm' -o -name '*.sld' -o -name '*.sfir' \) -exec ./scripts/format-scheme --write {} +
	$(NIXFMT) shell.nix

check:
	EMACS="$(EMACS)" find src lib tests examples wasm-native/scheme wasm-native/tests -type f \( -name '*.scm' -o -name '*.sld' -o -name '*.sfir' \) -exec ./scripts/format-scheme --check {} +
	awk -v limit=100 -f scripts/check-line-length.awk src/snail-scheme/ir.sld
	$(NIXFMT) --check shell.nix
