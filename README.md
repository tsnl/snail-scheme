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

`snail-scheme-tests` runs the CLI tests and the parser suite in
`src/snail-scheme/parser-tests.scm`. The parser library includes this file so
tests can exercise private parsers without exporting them individually.

The reader handles proper and dotted lists, quote abbreviations, booleans,
characters, strings, numbers, identifiers, and line, nested block, and datum
comments. Number forms and precision follow the host Scheme's `string->number`.
Quoted identifiers (`|...|`), string line continuations, vectors, bytevectors,
datum labels, and case directives are still pending. The input stream remains
backed by a character list.
