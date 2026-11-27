.DEFAULT_GOAL := check
.PHONY: format check check-scheme test test-browser test-gpu bootstrap unicode-tables generated-unicode site last-mile siegework hearsay viewer splats furnace iygtw iygtw-art pages

CHEZ ?= scheme
export CHEZ
NIXFMT ?= nixfmt
MDBOOK ?= mdbook
# Tree-sitter's queries under editors/zed are written in .scm files too.
SCHEME_SOURCES = '*.scm' '*.sld' '*.sls' ':(exclude)editors/zed/languages'

# The compiler's unit tests, on Chez, then every program and check, built
# by the command line (tests/run.mjs): the examples and test programs, both
# games' tests, Siegework headless, the build suites and the formatter's.
# The command line is bootstrapped first.
test: check-scheme
	./scripts/bootstrap >/dev/null
	"$(CHEZ)" --script host/chez/load.scm "$(CURDIR)" test
	node tests/run.mjs "$(CURDIR)"

# Browser interfaces in headless Chromium: the shell's on Linux, or the
# browser CHROMIUM names. CI does not run them.
test-browser:
	node tests/browser/wasm-instance-identity.mjs "$(CURDIR)"
	node tests/browser/ui.mjs "$(CURDIR)"
	node tests/browser/ui-requests.mjs "$(CURDIR)"
	node tests/browser/gpu.mjs "$(CURDIR)"
	node tests/browser/furnace.mjs "$(CURDIR)"
	node tests/browser/static-resources.mjs "$(CURDIR)"
	node tests/browser/scene-recording.mjs "$(CURDIR)"
	node tests/browser/orthographic.mjs "$(CURDIR)"
	node tests/browser/last-mile.mjs "$(CURDIR)"
	node tests/browser/iygtw.mjs "$(CURDIR)"

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

check-scheme:
	git ls-files -z $(SCHEME_SOURCES) | xargs -0 ./scripts/format-scheme --check

check: check-scheme
	$(NIXFMT) --check shell.nix benches/*/*.nix
	$(MAKE) generated-unicode
	cmp build/unicode.sld src/snail/shell/text/unicode.sld

# (snail shell text)'s tables, generated from Rust's Unicode properties
# into build/unicode.sld, which `check` compares with the checked-in copy.
unicode-tables: generated-unicode
	cp build/unicode.sld src/snail/shell/text/unicode.sld

generated-unicode:
	mkdir -p build
	cargo run -q --manifest-path crates/snail-scheme-support/Cargo.toml \
	  --example unicode-tables > build/unicode-tables.sld
	./snail-scheme format < build/unicode-tables.sld > build/unicode.sld

# Each application is a script, src/apps/NAME/main.scm, built into
# build/src/apps/NAME/main.
site: last-mile siegework hearsay viewer splats iygtw furnace

BLENDER ?= blender

iygtw-art:
	$(BLENDER) --background -noaudio --factory-startup --python-exit-code 1 --python src/blender/export_village.py

iygtw:
	./snail-scheme build --release --target browser src/apps/iygtw/main.scm

last-mile:
	./snail-scheme build --release --target browser src/apps/last-mile/main.scm

siegework:
	./snail-scheme build --release --target browser src/apps/siegework/main.scm

hearsay:
	./snail-scheme build --release --target browser src/apps/hearsay/main.scm

viewer:
	./snail-scheme build --release --target browser src/apps/viewer/main.scm

furnace:
	./snail-scheme build --release --target browser src/apps/furnace/main.scm

splats:
	./snail-scheme build --release --target browser src/apps/splats/main.scm

# The public site in build/pages contains the book and each published
# application at play/NAME/. The glTF viewer and Splats ship no scene:
# the viewer's samples are links to where they are published, and Splats
# opens on procedural rings until given a trained scene's files. Hearsay
# carries its LPC art's credits, read from the packs when it is built,
# and shows them from its menu.
# Train stays unpublished: its page trains on a dataset served beside it.
PAGES_APPS = last-mile siegework viewer splats hearsay iygtw furnace

pages: $(PAGES_APPS)
	$(RM) -r build/pages-input
	"$(MDBOOK)" build --dest-dir build/pages-input
	cp host/cloudflare/_redirects build/pages-input/_redirects
	for app in $(PAGES_APPS); do \
	  mkdir -p build/pages-input/play/$$app && \
	  cp -R build/src/apps/$$app/main/. build/pages-input/play/$$app/ && \
	  test -f build/pages-input/play/$$app/main.wasm || exit 1; \
	done
	python3 host/cloudflare/pack.py build/pages-input build/pages
	test -f build/pages/index.html
	test -f build/pages/games/siegework.html
