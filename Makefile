.DEFAULT_GOAL := check
.PHONY: format check test test-chibi bootstrap site

CHIBI ?= chibi-scheme
# Chibi collects the whole heap whenever it grows, so start it large.
HEAP ?= 2G
EMACS ?= emacs
NIXFMT ?= nixfmt
SCHEME_SOURCES = '*.scm' '*.sld'

# The compiler's unit tests, every test program, and Siegework headless.
test:
	"$(EMACS)" --quick --batch -l tests/format-scheme.el -f ert-run-tests-batch-and-exit
	"$(CHIBI)" -h $(HEAP) -D snail-tests -I host/chibi -I src -I tests tests/run.scm "$(CURDIR)"

# The suite with the compiler's source running on Chibi instead of as Wasm.
test-chibi:
	LOFI_STAGE0=chibi "$(CHIBI)" -h $(HEAP) -D snail-tests -I host/chibi -I src -I tests tests/run.scm "$(CURDIR)"

# Rebuilds the compiler from its source on Chibi, then to a fixpoint.
bootstrap:
	rm -rf build/compiler
	./lofi bootstrap

format:
	git ls-files -z $(SCHEME_SOURCES) | EMACS="$(EMACS)" xargs -0 ./scripts/format-scheme --write
	$(NIXFMT) shell.nix

check:
	git ls-files -z $(SCHEME_SOURCES) | EMACS="$(EMACS)" xargs -0 ./scripts/format-scheme --check
	$(NIXFMT) --check shell.nix

# Siegework as a static site in build/siegework.
site:
	"$(CHIBI)" -h $(HEAP) -I host/chibi -I src scripts/build-app.scm "$(CURDIR)" --release apps/siegework build/siegework
