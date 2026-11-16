.DEFAULT_GOAL := check
.PHONY: format check fetch test test-wasmtime test-browser bootstrap unicode-tables generated-unicode site siegework hearsay pages

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

# The compiler's unit tests, on Chez, then every program and check, built
# by the command line (tests/run.mjs): the examples and test programs, both
# games' tests, Siegework headless, the build suites and the formatter's.
# The command line is bootstrapped first.
test:
	./scripts/bootstrap >/dev/null
	"$(CHEZ)" --script host/chez/load.scm "$(CURDIR)" test
	node tests/run.mjs "$(CURDIR)"

# The suite with each program built for wasmtime and run on the native
# executable, plus the check that the command line emits the same text on
# both engines.
test-wasmtime:
	SNAIL_ENGINE=wasmtime $(MAKE) test

# Browser interfaces in headless Chromium, which CI does
# not have; CHROMIUM names the browser.
test-browser:
	node tests/browser/wasm-instance-identity.mjs "$(CURDIR)"
	node tests/browser/ui.mjs "$(CURDIR)"
	node tests/browser/ui-requests.mjs "$(CURDIR)"

# Rebuilds the command line from the compiler's source on Chez, then to a
# fixpoint.
bootstrap:
	rm -rf build/bootstrap
	./scripts/bootstrap

format:
	git ls-files -z $(SCHEME_SOURCES) | xargs -0 ./scripts/format-scheme --write
	$(NIXFMT) shell.nix

check:
	git ls-files -z $(SCHEME_SOURCES) | xargs -0 ./scripts/format-scheme --check
	$(NIXFMT) --check shell.nix
	$(MAKE) generated-unicode
	cmp build/unicode.sld src/snail/shell/text/unicode.sld

# (snail shell text)'s tables, generated from Rust's Unicode properties
# into build/unicode.sld, which `check` compares with the checked-in copy.
unicode-tables: generated-unicode
	cp build/unicode.sld src/snail/shell/text/unicode.sld

generated-unicode:
	mkdir -p build
	cargo run -q --offline --manifest-path crates/snail-scheme-support/Cargo.toml \
	  --example unicode-tables > build/unicode-tables.sld
	./snail-scheme format < build/unicode-tables.sld > build/unicode.sld

# Each application is a script, src/apps/NAME/main.scm, built into
# build/src/apps/NAME/main.
site: siegework hearsay

siegework:
	./snail-scheme build --release --target browser src/apps/siegework/main.scm

hearsay:
	./snail-scheme build --release --target browser src/apps/hearsay/main.scm

# The GitHub Pages site in build/pages: the book, with Siegework at
# play/siegework/. Hearsay stays unpublished: its LPC art must be credited
# as src/lpc/ATTRIBUTION.md describes, and the page doesn't show credits.
pages: siegework
	"$(MDBOOK)" build --dest-dir build/pages
	mkdir -p build/pages/play/siegework
	cp -R build/src/apps/siegework/main/. build/pages/play/siegework/
	test -f build/pages/index.html
	test -f build/pages/games/siegework.html
	test -f build/pages/play/siegework/main.wasm
