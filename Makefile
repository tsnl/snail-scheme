.DEFAULT_GOAL := check
.PHONY: format check fetch test test-browser test-gpu bootstrap unicode-tables generated-unicode site siegework hearsay viewer pages

CHEZ ?= scheme
export CHEZ
NIXFMT ?= nixfmt
MDBOOK ?= mdbook
# Tree-sitter's queries under editors/zed are written in .scm files too.
SCHEME_SOURCES = '*.scm' '*.sld' '*.sls' ':(exclude)editors/zed/languages'

# Downloads the Rust crates in each Cargo.lock, which the tests and every
# build then use offline, and the npm packages package-lock.json pins:
# webgpu, for WebGPU on Node. Run it once in a new checkout or container.
fetch:
	cargo fetch --locked --manifest-path crates/snail-scheme-support/Cargo.toml
	npm ci --no-fund --no-audit

# The compiler's unit tests, on Chez, then every program and check, built
# by the command line (tests/run.mjs): the examples and test programs, both
# games' tests, Siegework headless, the build suites and the formatter's.
# The command line is bootstrapped first.
test:
	./scripts/bootstrap >/dev/null
	"$(CHEZ)" --script host/chez/load.scm "$(CURDIR)" test
	node tests/run.mjs "$(CURDIR)"

# Browser interfaces in headless Chromium, which CI does
# not have; CHROMIUM names the browser.
test-browser:
	node tests/browser/wasm-instance-identity.mjs "$(CURDIR)"
	node tests/browser/ui.mjs "$(CURDIR)"
	node tests/browser/ui-requests.mjs "$(CURDIR)"
	node tests/browser/gpu.mjs "$(CURDIR)"

# The GPU checks on Node, on the GPU Dawn finds (host/native/gpu.mjs),
# which CI does not have.
test-gpu:
	node tests/gpu.mjs "$(CURDIR)"

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
site: siegework hearsay viewer

siegework:
	./snail-scheme build --release --target browser src/apps/siegework/main.scm

hearsay:
	./snail-scheme build --release --target browser src/apps/hearsay/main.scm

viewer:
	./snail-scheme build --release --target browser src/apps/viewer/main.scm

# The GitHub Pages site in build/pages: the book, with Siegework at
# play/siegework/ and the glTF viewer at play/viewer/, which ships no
# scene: its samples are links to where they are published.
# Hearsay stays unpublished: its LPC art must be credited as
# src/lpc/ATTRIBUTION.md describes, and the page doesn't show credits.
pages: siegework viewer
	"$(MDBOOK)" build --dest-dir build/pages
	mkdir -p build/pages/play/siegework build/pages/play/viewer
	cp -R build/src/apps/siegework/main/. build/pages/play/siegework/
	cp -R build/src/apps/viewer/main/. build/pages/play/viewer/
	test -f build/pages/index.html
	test -f build/pages/games/siegework.html
	test -f build/pages/play/siegework/main.wasm
	test -f build/pages/play/viewer/main.wasm
