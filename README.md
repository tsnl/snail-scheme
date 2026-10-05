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
Character predicates live in `common.sld`. Syntax rules compose parsers directly,
with `capture` returning the text consumed by a rule. Direct reader access stays
in the parser primitives. `symbol-or-number` reads a complete bare spelling and
classifies it with literal predicates, so `12abc` and `hello#t` are rejected as
whole spellings. The dotted-tail rule uses a local boundary assertion after `.`
to require a delimiter or EOF, then delegates the tail to `expr`.

`string->reader` and `list->reader` take a filename followed by their contents;
`file->reader` loads a file by path. Pass the resulting reader to `parse-file`.
Source locations and parse errors retain the reader's filename. The launcher
currently parses its input file and prints the syntax records.

`make test` runs `tests/snail-scheme/test.scm`, which loads the CLI, reader,
parser, and syntax test libraries from the same directory. Test helpers also
live there; production libraries do not load test code.

`syntax-pattern` builds an ordered dispatcher from host Scheme patterns and
callbacks. It matches the whole input form; list literal identifiers explicitly
to dispatch on a head, or use `_` to ignore it:

```scheme
(define dispatch
  (syntax-pattern '... '(define)
    (list
      (cons '(define name value)
        (lambda (matched)
          (map match-group-data (match-result-groups matched)))))))

(dispatch (car (parse-file (string->reader "example.scm" "(define x 42)"))))
```

The result has separate success and callback-return fields, so returning `#f`
still selects an arm. No match returns failure with an empty return field.
Callbacks receive one `match-result`; groups appear in pattern traversal order.
A singleton group's data is the original syntax object. Repeated groups contain
lists nested once per ellipsis, preserving empty and ragged repetitions.
Synthesized list tails reuse the containing list's location and original children.
`pattern?` validates a datum, optionally taking an ellipsis symbol and literal list;
`match-syntax-pattern-arm` exposes matching without dispatch. Patterns support
unique variables, wildcards, constants, dotted lists, vectors, custom ellipses,
and one repeated segment per sequence level. Bytevectors match as constants.
Literal identifiers currently compare by spelling; binding-aware comparison,
hygiene, and template expansion belong to subsequent passes.

The syntax parser handles lists, vectors, and bytevectors with matched `()`, `[]`,
or `{}`, quote abbreviations, booleans, characters, strings, numbers, identifiers
(including `|...|`), and line, nested block, and datum comments. `s-sequence` parses
proper sequences first: no prefix gives a list, `#` a vector, and `#u8` a bytevector.
A separate arm parses improper lists with at least one element and a required
dotted tail. All three forms use `(make-list-syntax elements improper-tail loc prefix)`;
`list-syntax-prefix` returns `()` for lists, `"#"` for vectors, or `"#u8"` for
bytevectors. Prefixes are normalized to lowercase. Elements retain their syntax
objects and source locations, including in bytevectors.
`s-terminal` parses individual literals and symbols; `expr` handles leading
intertoken space. `number-literal?` and `char-literal?`
validate complete strings. Numeric rules recognize radix and exactness prefixes,
integers, ratios, decimals, exponents, and complex numbers before `string->number`
constructs the value; representation and precision still follow the host Scheme.
Bytevector literals use `#u8(...)` with exact integer elements from 0 through 255;
`(bytevector ...)` is an ordinary application. String line continuations,
datum labels, and case directives are still pending. The input stream
remains backed by a character list.
