.DEFAULT_GOAL := check
.PHONY: format check fetch test test-chibi test-browser bootstrap ide site siegework hearsay pages

CHIBI ?= chibi-scheme
# Chibi collects the whole heap whenever it grows, so start it large.
HEAP ?= 2G
EMACS ?= emacs
NIXFMT ?= nixfmt
MDBOOK ?= mdbook
SCHEME_SOURCES = '*.scm' '*.sld'

# Downloads the Rust crates in each Cargo.lock, which the tests and every
# build then use offline. Run it once in a new checkout or container.
fetch:
	cargo fetch --locked --manifest-path src/runtime/Cargo.toml
	cargo fetch --locked --manifest-path src/assembler/Cargo.toml

# The formatter's tests, the compiler's unit tests, the examples and test
# programs, both games' tests, Siegework headless, and the development loop.
test:
	"$(EMACS)" --quick --batch -l tests/format-scheme.el -f ert-run-tests-batch-and-exit
	"$(CHIBI)" -h $(HEAP) -D snail-tests -I host/chibi -I src -I tests tests/run.scm "$(CURDIR)"

# The suite with the compiler's source running on Chibi instead of as Wasm.
test-chibi:
	LOFI_STAGE0=chibi "$(CHIBI)" -h $(HEAP) -D snail-tests -I host/chibi -I src -I tests tests/run.scm "$(CURDIR)"

# Live reload and the browser IDE in headless Chromium, which CI does not
# have; CHROMIUM names the browser.
test-browser:
	node tests/browser/reload.mjs "$(CURDIR)"
	node tests/browser/ide.mjs "$(CURDIR)"

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

# The browser editor opening Siegework as a project in build/ide.
ide:
	"$(CHIBI)" -h $(HEAP) -I host/chibi -I src scripts/build-ide.scm "$(CURDIR)" apps/siegework build/ide

# Siegework and Hearsay's prototypes as static sites in build/siegework and
# build/hearsay.
site: siegework hearsay

siegework:
	"$(CHIBI)" -h $(HEAP) -I host/chibi -I src scripts/build-app.scm "$(CURDIR)" --release apps/siegework build/siegework

hearsay:
	"$(CHIBI)" -h $(HEAP) -I host/chibi -I src scripts/build-app.scm "$(CURDIR)" --release apps/hearsay build/hearsay

# The GitHub Pages site in build/pages: the book, with Siegework at
# play/siegework/. Hearsay stays unpublished: its LPC art must be credited
# as lib/lpc/ATTRIBUTION.md describes, and the page doesn't show credits.
pages: siegework
	"$(MDBOOK)" build --dest-dir build/pages
	mkdir -p build/pages/play
	cp -R build/siegework build/pages/play/siegework
	test -f build/pages/index.html
	test -f build/pages/games/siegework.html
	test -f build/pages/play/siegework/app.wasm
