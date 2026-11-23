.DEFAULT_GOAL := check
.PHONY: format check fetch test test-browser test-gpu bootstrap unicode-tables generated-unicode site siegework hearsay viewer splats last-mile pages

CHEZ ?= scheme
export CHEZ
NIXFMT ?= nixfmt
MDBOOK ?= mdbook
# Tree-sitter's queries under editors/zed are written in .scm files too.
SCHEME_SOURCES = '*.scm' '*.sld' '*.sls' ':(exclude)editors/zed/languages'

# Downloads the Rust crates in each Cargo.lock, which the tests and every
# build then use offline, and the npm packages package-lock.json pins:
# webgpu, for WebGPU on Node, and @napi-rs/canvas, which decodes its
# images. Run it once in a new checkout or container.
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
	node tests/browser/last-mile.mjs "$(CURDIR)"

# The GPU checks on Node, on the GPU Dawn finds (host/native/gpu.mjs), or
# on the CPU through lavapipe where there is none, as in CI (shell.nix).
test-gpu:
	node tests/gpu.mjs "$(CURDIR)"

# Rebuilds the command line from the compiler's source on Chez, then to a
# fixpoint.
bootstrap:
	rm -rf build/bootstrap
	./scripts/bootstrap

format:
	git ls-files -z $(SCHEME_SOURCES) | xargs -0 ./scripts/format-scheme --write
	$(NIXFMT) shell.nix benches/*/*.nix

check:
	git ls-files -z $(SCHEME_SOURCES) | xargs -0 ./scripts/format-scheme --check
	$(NIXFMT) --check shell.nix benches/*/*.nix
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
site: siegework hearsay viewer splats last-mile

siegework:
	./snail-scheme build --release --target browser src/apps/siegework/main.scm

last-mile:
	./snail-scheme build --release --target browser src/apps/last-mile/main.scm

hearsay:
	./snail-scheme build --release --target browser src/apps/hearsay/main.scm

viewer:
	./snail-scheme build --release --target browser src/apps/viewer/main.scm

splats:
	./snail-scheme build --release --target browser src/apps/splats/main.scm

# The GitHub Pages site in build/pages: the book, with each published
# application at play/NAME/. The glTF viewer and Splats ship no scene:
# the viewer's samples are links to where they are published, and Splats
# opens on procedural rings until given a trained scene's files. Hearsay
# carries its LPC art's credits, read from the packs when it is built,
# and shows them from its menu.
# Train stays unpublished: its page trains on a dataset served beside it.
PAGES_APPS = siegework viewer splats hearsay last-mile

pages: $(PAGES_APPS)
	"$(MDBOOK)" build --dest-dir build/pages
	for app in $(PAGES_APPS); do \
	  mkdir -p build/pages/play/$$app && \
	  cp -R build/src/apps/$$app/main/. build/pages/play/$$app/ && \
	  test -f build/pages/play/$$app/main.wasm || exit 1; \
	done
	test -f build/pages/index.html
	test -f build/pages/games/siegework.html
