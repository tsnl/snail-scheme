.DEFAULT_GOAL := check
.PHONY: format check test

CHIBI ?= chibi-scheme
EMACS ?= emacs
NIXFMT ?= nixfmt

test:
	"$(CHIBI)" -D snail-tests -I src -I tests tests/snail-scheme/test.scm

format:
	EMACS="$(EMACS)" find src tests -type f \( -name '*.scm' -o -name '*.sld' \) -exec ./scripts/format-scheme --write {} +
	$(NIXFMT) shell.nix

check:
	EMACS="$(EMACS)" find src tests -type f \( -name '*.scm' -o -name '*.sld' \) -exec ./scripts/format-scheme --check {} +
	awk -v limit=100 -f scripts/check-line-length.awk \
		src/snail-scheme/expand.sld src/snail-scheme/ir.sld
	$(NIXFMT) --check shell.nix
