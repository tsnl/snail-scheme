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
syntax records and accessors (`syntax.sld`), syntax parsing (`syntax-parser.sld`),
and pattern matching and dispatch (`syntax-pattern.sld`). `pmap` transforms parser values;
ordinary Scheme `map` operates on lists. CLI argument parsing lives in `cli.sld`.
Character predicates live in `common.sld`. Syntax rules match the input directly,
using `tuple`, `repeat`, and `pmap` to assemble spellings from character results.
Direct reader access stays in the parser primitives. Separate `s-number` and
`s-symbol` rules check token boundaries with `not-followed-by`, so `12abc` and
`hello#t` cannot split into smaller atoms. Booleans, characters, and dotted tails
also require a delimiter or EOF after their spelling.

`chain` takes an initial parser followed by binders that receive each successful
value and return the next parser. `pmap` uses `chain` to transform a successful
value. `tuple` collects positional values; `named-tuple` accepts `(symbol . parser)`
pairs, conventionally written with quasiquote, and returns an association list.
Use `(cdr (assq 'name fields))` to retrieve a named value. Keys must be unique
symbols, except `_`, whose parser runs but whose value is discarded.

`string->reader` and `list->reader` take a filename followed by their contents;
`file->reader` loads a file by path. Apply `((s-file) reader)` to parse a complete
file, then check `parse-result-ok?` before extracting `parse-result-value`.
The result contains a list of syntax objects; trailing intertoken space and EOF
are handled by `s-file`. Source locations and the reader in a failed parse result
retain the filename. The launcher reports parse failures or prints the syntax records.

`make test` runs `tests/snail-scheme/test.scm`, which loads the CLI, reader,
parser, and syntax test libraries from the same directory. Test helpers also
live there; production libraries do not load test code.

`syntax-dispatch` builds an ordered dispatcher from raw patterns (host datums) and
callbacks. It matches the whole input form; list literal identifiers explicitly
to dispatch on a head, or use `_` to ignore it:

```scheme
(import (scheme base)
        (snail-scheme reader) (snail-scheme parser)
        (snail-scheme syntax-parser)
        (snail-scheme syntax-pattern))

(define dispatch
  (syntax-dispatch '... '(define)
    (list
      (cons '(define name value)
        (lambda (captures)
          (map cdr captures))))))

(define result
  (dispatch (car (parse-result-value ((s-file) (string->reader "example.scm" "(define x 42)"))))))
result                                      ; syntax objects for x and 42
```

Dispatch returns the first callback value other than `#f`. A callback returning
`#f` declines its branch and dispatch tries the next pattern. If no callback
accepts, dispatch returns `#f`. Only `#f` is false in Scheme: `'()`, `0`, and `""`
all select their branch.
Callbacks receive an association list of `(name . capture)` entries in pattern
traversal order. Use `(cdr (assq 'name captures))` to retrieve a capture.
A singleton capture is the original syntax object. Repeated captures contain
lists nested once per ellipsis, preserving empty and ragged repetitions.
Synthesized list tails reuse the containing list's location and original children.
`syntax-dispatch` takes an ellipsis symbol, a literal list, and pattern/callback
pairs. Dispatch separates patterns and callbacks, parses the patterns independently,
and walks the parallel lists with `dispatch-syntax-against-pattern-list`.
Literal identifiers match by symbol spelling: the private dispatcher builder takes explicit
ellipsis, literal-list, and lookup arguments. Lookup maps symbols to identities
compared with `eqv?`, and the public wrapper supplies `(lambda (x) x)`.
Parsing classifies literal symbols without calling lookup. Matching resolves
literal and input symbols through lookup and constructs private match-result
records. A final pass flattens successful results into the callback alist.

Patterns support unique variables, wildcards, constants, dotted lists, vectors,
custom ellipses, and one repeated segment per sequence level. Bytevectors match
as constants. Invalid patterns, including duplicate variables, are rejected when
constructing the dispatcher. Successful matches can have an empty capture list.
List and vector patterns are parsed into a prefix, an optional repeated item, and
a suffix; lists additionally carry an optional improper-tail pattern. Matching
consumes the prefix, reserves and matches the suffix and tail, then matches the
repeated item against the remaining elements. Flattening preserves pattern order,
original syntax objects, and empty and ragged repetition captures.
The intended binding-aware semantics for future `syntax-rules` expansion,
including shadowed literals and exported auxiliary keywords, are documented in
[the macro design](doc/core-ir.md#literal-binding-identity).

Lexical scoping and macro expansion are pending. `make-atom-syntax` constructs
atoms from a value and source location. Later passes will carry lexical scope in
their traversal context.

## Reader

The syntax parser handles lists, vectors, and bytevectors with matched `()`, `[]`,
or `{}`, quote abbreviations, booleans, characters, strings, numbers, identifiers
(including `|...|`, `#%-` names, and `→`), and line, nested block, and datum comments.
`s-list` tries proper lists first, then improper lists with at least one element
and a required dotted tail. `s-vector` parses `#`-prefixed proper lists.
Lists use `(make-list-syntax elements improper-tail loc)`; vectors have their
own record, `(make-vector-syntax elements loc)`, recognized by `vector-syntax?`.
Both store lists of child syntax objects and preserve their source locations.
Vector locations start at the `#` prefix; list locations start at the opening fence. `s-bytevector` validates
each byte and constructs an atom containing a bytevector, located at the prefix.
The matcher compares bytevector datums as ordinary constants.
The parsing API is `s-file`, `s-expr`, and `s-atom`. `s-atom` parses literals,
including bytevectors, and symbols; `s-expr` also handles compound forms and leading
intertoken space. Other rules remain temporarily exported for the external tests.
The standalone literal predicates assert a string argument and recognize complete
spellings; the syntax rules do not call them. Numeric rules recognize radix and exactness prefixes,
integers, ratios, decimals, exponents, and complex numbers before `string->number`
constructs the value; representation and precision still follow the host Scheme.
Bytevector literals use `#u8(...)` with exact integer elements from 0 through 255;
`(bytevector ...)` is an ordinary application. String line continuations,
datum labels, and case directives are still pending. The input stream
remains backed by a character list.
