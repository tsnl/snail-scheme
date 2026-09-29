.DEFAULT_GOAL := check
.PHONY: format check test

CHIBI ?= chibi-scheme
EMACS ?= emacs
NIXFMT ?= nixfmt

test:
	"$(CHIBI)" -I src -I tests tests/snail-scheme/test.scm

format:
	EMACS="$(EMACS)" find src tests -type f \( -name '*.scm' -o -name '*.sld' \) -exec ./scripts/format-scheme --write {} +
	$(NIXFMT) shell.nix

check:
	EMACS="$(EMACS)" find src tests -type f \( -name '*.scm' -o -name '*.sld' \) -exec ./scripts/format-scheme --check {} +
	$(NIXFMT) --check shell.nix
