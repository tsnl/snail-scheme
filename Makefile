.DEFAULT_GOAL := check
.PHONY: format check

SCHEMAT ?= schemat
NIXFMT ?= nixfmt
SCHEME_FILES := 'src/**/*.scm' 'src/**/*.sld' 'tests/**/*.scm'

format:
	$(SCHEMAT) $(SCHEME_FILES)
	$(NIXFMT) shell.nix

check:
	$(SCHEMAT) --check $(SCHEME_FILES)
	$(NIXFMT) --check shell.nix
