# `snail-scheme`

> 🚧 Rewrite WIP, for latest mature implementation see
> branch [`v3`](https://github.com/tsnl/snail-scheme/tree/v3).

A small, portable, easy to understand Scheme implementation.

```bash
nix-shell
./snail-scheme INPUT -o OUTPUT
make test
```

Use `nix-shell` (or direnv) to load the development tools. Run `make format`
to indent the Scheme sources and tests with Emacs's `scheme-mode` and format
`shell.nix` with nixfmt.
Run `make check` to verify formatting without changing files; it exits with a
nonzero status when formatting is needed. Plain `make` also runs this check.

Scheme indentation uses spaces and preserves existing line breaks. Use `;;` for
comments on their own lines and `;` for trailing comments, following Emacs's Lisp
indentation conventions. `scripts/format-scheme` runs Emacs in batch mode without
loading personal configuration; set `EMACS` to use another executable. With no
arguments it reads stdin and writes stdout, as used by the project's Zed settings.
Use `--write FILE ...` to format files or `--check FILE ...` to check them.

`./snail-scheme` is a Bash launcher for `src/snail-scheme/main.scm`. It locates
the source directory relative to the launcher and preserves the caller's working
directory and arguments. Set `CHIBI` to use a different Chibi executable with
the launcher or `make test`.

The libraries in `src/snail-scheme/` separate source locations (`source.sld`),
the character reader (`reader.sld`), general parser combinators (`parser.sld`),
and syntax records and parsing (`syntax.sld`). `pmap` transforms parser values;
ordinary Scheme `map` operates on lists. CLI argument parsing lives in `cli.sld`.

`string->reader` and `list->reader` take a filename followed by their contents;
`file->reader` loads a file by path. Pass the resulting reader to `parse-file`.
Source locations and parse errors retain the reader's filename. The launcher
currently parses its input file and prints the syntax records.

`make test` runs `tests/snail-scheme/test.scm`, which loads the CLI, reader,
parser, and syntax test libraries from the same directory. Test helpers also
live there; production libraries do not load test code.

The syntax parser handles proper and dotted lists, quote abbreviations, booleans,
characters, strings, numbers, identifiers, and line, nested block, and datum
comments. Number forms and precision follow the host Scheme's `string->number`.
Quoted identifiers (`|...|`), string line continuations, vectors, bytevectors,
datum labels, and case directives are still pending. The input stream remains
backed by a character list.
