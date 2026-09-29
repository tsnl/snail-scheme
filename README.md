# `snail-scheme`

> 🚧 Rewrite WIP, for latest mature implementation see
> branch [`v3`](https://github.com/tsnl/snail-scheme/tree/v3).

A small, portable, easy to understand Scheme implementation.

```bash
alias snail-scheme='chibi-scheme -I src -rmain src/snail-scheme/snail-scheme.scm'
alias snail-scheme-tests='chibi-scheme -I src -rtest src/snail-scheme/snail-scheme.scm'
snail-scheme INPUT -o OUTPUT
```

Use `nix-shell` (or direnv) to load the development tools. Run `make format`
to format the Scheme sources and tests with Schemat and `shell.nix` with nixfmt.
Run `make check` to verify formatting without changing files; it exits with a
nonzero status when formatting is needed. Plain `make` also runs this check.
