.DEFAULT_GOAL := check
.PHONY: format check test

CHIBI ?= chibi-scheme
EMACS ?= emacs
NIXFMT ?= nixfmt
SCHEME_SOURCES = '*.scm' '*.sld'

test:
	"$(EMACS)" --quick --batch -l tests/format-scheme.el -f ert-run-tests-batch-and-exit
	"$(CHIBI)" -D snail-tests -I bootstrap -I tests tests/lofi/host.scm

format:
	git ls-files -z $(SCHEME_SOURCES) | EMACS="$(EMACS)" xargs -0 ./scripts/format-scheme --write
	$(NIXFMT) shell.nix

check:
	git ls-files -z $(SCHEME_SOURCES) | EMACS="$(EMACS)" xargs -0 ./scripts/format-scheme --check
	awk -v limit=100 -f scripts/check-line-length.awk src/lofi/compiler/ir.sld
	$(NIXFMT) --check shell.nix
