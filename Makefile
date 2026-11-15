.DEFAULT_GOAL := check
.PHONY: format check fetch test test-wasmtime test-chez test-browser bootstrap watch site siegework hearsay pages

CHEZ ?= scheme
export CHEZ
NIXFMT ?= nixfmt
MDBOOK ?= mdbook
# Tree-sitter's queries under editors/zed are written in .scm files too.
SCHEME_SOURCES = '*.scm' '*.sld' '*.sls' ':(exclude)editors/zed/languages'

# Downloads the Rust crates in each Cargo.lock, which the tests and every
# build then use offline. Run it once in a new checkout or container.
fetch:
	cargo fetch --locked --manifest-path crates/snail-scheme-support/Cargo.toml
	cargo fetch --locked --manifest-path crates/snail/Cargo.toml

# The formatter's tests, the compiler's unit tests, the examples and test
# programs, both games' tests, Siegework headless, and the development service.
# Build shared tools before the service tests' startup deadlines begin.
test:
	./scripts/snail-tool watch-tools >/dev/null
	"$(CHEZ)" --script host/chez/load.scm "$(CURDIR)" test

# The suite with every compile on the native executable's wasmtime instead of
# Node, plus the check that both engines emit the same text.
test-wasmtime:
	SNAIL_ENGINE=wasmtime $(MAKE) test

# The suite with the compiler's source running on Chez instead of as Wasm.
test-chez:
	SNAIL_STAGE0=chez ./scripts/snail-tool watch-tools >/dev/null
	SNAIL_STAGE0=chez "$(CHEZ)" --script host/chez/load.scm "$(CURDIR)" test

# Live reload and browser interfaces in headless Chromium, which CI does
# not have; CHROMIUM names the browser.
test-browser:
	node tests/browser/reload.mjs "$(CURDIR)"
	node tests/browser/wasm-instance-identity.mjs "$(CURDIR)"
	node tests/browser/ui.mjs "$(CURDIR)"
	node tests/browser/ui-reload.mjs "$(CURDIR)"
	node tests/browser/ui-requests.mjs "$(CURDIR)"

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

# The development service for the whole repository: each browser target
# at http://127.0.0.1:8000/NAME/, relinked as its sources change.
watch:
	./snail-scheme watch .

# The root project names each application, with output in build/NAME.
site: siegework hearsay

siegework:
	./snail-scheme build --release . siegework

hearsay:
	./snail-scheme build --release . hearsay

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
