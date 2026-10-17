.DEFAULT_GOAL := check
.PHONY: format check test benchmark

CHIBI ?= chibi-scheme
EMACS ?= emacs
NIXFMT ?= nixfmt
BENCH_OUTPUT ?= /tmp/lofi-benchmarks
# Benchmark captures retain their recorded source hashes and layout.
SCHEME_SOURCES = '*.scm' '*.sld' ':!:benchmarks/**'

test:
	"$(EMACS)" --quick --batch -l tests/format-scheme.el -f ert-run-tests-batch-and-exit
	"$(CHIBI)" -D snail-tests -I wasm-native/scheme -I wasm-native/tests wasm-native/tests/host.scm
	"$(CHIBI)" -D snail-tests -I bootstrap -I wasm-native/scheme -I tests -I wasm-native/tests tests/lofi/host.scm
	"$(CHIBI)" -D snail-tests -I bootstrap -I wasm-native/scheme -I tests -I wasm-native/tests -I benchmarks tests/lofi-benchmarks.scm
	"$(CHIBI)" -D snail-tests -I bootstrap -I wasm-native/scheme -I tests -I wasm-native/tests -I benchmarks benchmarks/wasm-reference/tests/audits.scm

benchmark:
	"$(CHIBI)" -I bootstrap -I wasm-native/scheme -I benchmarks benchmarks/lofi/runner.scm prepare --output "$(BENCH_OUTPUT)"
	"$(CHIBI)" -I bootstrap -I wasm-native/scheme -I benchmarks benchmarks/lofi/runner.scm validate --output "$(BENCH_OUTPUT)"

format:
	git ls-files -z $(SCHEME_SOURCES) | EMACS="$(EMACS)" xargs -0 ./scripts/format-scheme --write
	$(NIXFMT) shell.nix

check:
	git ls-files -z $(SCHEME_SOURCES) | EMACS="$(EMACS)" xargs -0 ./scripts/format-scheme --check
	awk -v limit=100 -f scripts/check-line-length.awk src/lofi/ir.sld
	$(NIXFMT) --check shell.nix
