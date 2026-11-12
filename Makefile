.DEFAULT_GOAL := check
.PHONY: format check fetch test test-wasmtime test-chez test-browser bootstrap ide site siegework hearsay pages

CHEZ ?= scheme
export CHEZ
NIXFMT ?= nixfmt
MDBOOK ?= mdbook
SCHEME_SOURCES = '*.scm' '*.sld' '*.sls'

# Downloads the Rust crates in each Cargo.lock, which the tests and every
# build then use offline. Run it once in a new checkout or container.
fetch:
	cargo fetch --locked --manifest-path crates/snail-core-support/Cargo.toml
	cargo fetch --locked --manifest-path crates/snail/Cargo.toml

# The formatter's tests, the compiler's unit tests, the examples and test
# programs, both games' tests, Siegework headless, and the development service.
# Build shared tools before the service tests' startup deadlines begin.
test:
	./scripts/snail-tool dev-tools >/dev/null
	"$(CHEZ)" --script host/chez/load.scm "$(CURDIR)" test

# The suite with every compile on the native executable's wasmtime instead of
# Node, plus the check that both engines emit the same text.
test-wasmtime:
	SNAIL_ENGINE=wasmtime $(MAKE) test

# The suite with the compiler's source running on Chez instead of as Wasm.
test-chez:
	SNAIL_STAGE0=chez ./scripts/snail-tool dev-tools >/dev/null
	SNAIL_STAGE0=chez "$(CHEZ)" --script host/chez/load.scm "$(CURDIR)" test

# Live reload and the browser IDE in headless Chromium, which CI does not
# have; CHROMIUM names the browser.
test-browser:
	node tests/browser/wasm-replacement.mjs "$(CURDIR)"
	node tests/browser/reload.mjs "$(CURDIR)"
	node tests/browser/ide.mjs "$(CURDIR)"
	node tests/browser/ide-highlights.mjs "$(CURDIR)"
	node tests/browser/ide-palette.mjs "$(CURDIR)"
	node tests/browser/ide-tabs.mjs "$(CURDIR)"
	node tests/browser/ide-search.mjs "$(CURDIR)"
	node tests/browser/ide-create.mjs "$(CURDIR)"
	node tests/browser/ide-installable.mjs "$(CURDIR)"
	node tests/browser/ide-install.mjs "$(CURDIR)"
	node tests/browser/ide-runs.mjs "$(CURDIR)"
	node tests/browser/ide-refresh.mjs "$(CURDIR)"
	node tests/browser/ui.mjs "$(CURDIR)"
	node tests/browser/ui-reload.mjs "$(CURDIR)"
	node tests/browser/ui-futures.mjs "$(CURDIR)"

# Rebuilds the compiler from its source on Chez, then to a fixpoint.
bootstrap:
	rm -rf build/compiler
	./scripts/snail-tool bootstrap

format:
	git ls-files -z $(SCHEME_SOURCES) | xargs -0 ./scripts/format-scheme --write
	$(NIXFMT) shell.nix

check:
	git ls-files -z $(SCHEME_SOURCES) | xargs -0 ./scripts/format-scheme --check
	$(NIXFMT) --check shell.nix

# The native project service and browser editor for the whole repository.
ide:
	./snail dev .

# The root project names each application, with output in build/NAME.
site: siegework hearsay

siegework:
	./snail build --release . siegework

hearsay:
	./snail build --release . hearsay

# The GitHub Pages site in build/pages: the book, with Siegework at
# play/siegework/. Hearsay stays unpublished: its LPC art must be credited
# as src/lpc/ATTRIBUTION.md describes, and the page doesn't show credits.
pages: siegework
	"$(MDBOOK)" build --dest-dir build/pages
	mkdir -p build/pages/play/siegework
	cp -R build/siegework/. build/pages/play/siegework/
	test -f build/pages/index.html
	test -f build/pages/games/siegework.html
	test -f build/pages/play/siegework/program.wasm
