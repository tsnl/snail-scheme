.DEFAULT_GOAL := check
.PHONY: format check test

CHIBI ?= chibi-scheme
SCHEMAT ?= schemat
NIXFMT ?= nixfmt

test:
	"$(CHIBI)" -I src -I tests tests/snail-scheme/test.scm

format:
	find src tests -type f \( -name '*.scm' -o -name '*.sld' \) -exec $(SCHEMAT) {} +
	$(NIXFMT) shell.nix

check:
	find src tests -type f \( -name '*.scm' -o -name '*.sld' \) -exec $(SCHEMAT) --check {} +
	$(NIXFMT) --check shell.nix
