# `snail-scheme`

> 🚧 Rewrite WIP, for latest mature implementation see
> branch [`v3`](https://github.com/tsnl/snail-scheme/tree/v3).

A small, portable, easy to understand Scheme implementation.

```bash
nix-shell
./snail-scheme examples/fibonacci.scm --release
./snail-scheme examples/fibonacci.scm -o build/fibonacci
./snail-scheme examples/fibonacci.scm --target wasm32-wasip1
make test
```

Use `nix-shell` (or direnv) to load the development tools. Run `make format`
to indent the Scheme sources and tests with Emacs's `scheme-mode` and format
`shell.nix` with nixfmt.
Run `make check` to verify formatting without changing files; it exits with a
nonzero status when formatting is needed. It also enforces a 100-column limit in
`expand.sld` and `hir.sld`. Plain `make` also runs this check.

Scheme indentation uses spaces and preserves existing line breaks. Use `;;` for
comments on their own lines and `;` for trailing comments, following Emacs's Lisp
indentation conventions. `scripts/format-scheme` runs Emacs in batch mode without
loading personal configuration; set `EMACS` to use another executable. With no
arguments it reads stdin and writes stdout, as used by the project's Zed settings.
Use `--write FILE ...` to format files or `--check FILE ...` to check them.

`./snail-scheme INPUT.scm` compiles and runs through Cargo; `-o PATH` builds an
executable without running it. The Rust driver generates a temporary Cargo
project linking Scheme-emitted LLVM with the Rust runtime. Add `--target
wasm32-wasip1` for WASI, `--emit-llvm` to inspect LLVM, or `--dump-vm PATH` for
the stack instructions. Program arguments follow `--`. `--timing` and
`--runtime-stats` report diagnostics on stderr. See `--help` and
[the backend guide](doc/backend.md) for tools, modes, and limitations.

Cargo/rustc, LLVM `opt` and `llc`, and a WASI-capable Node are needed in addition
to the Scheme development tools. Set `CHIBI` to select the hosted compiler's
Scheme executable. The build still uses Chibi; compiling the compiler's sources
is supported without switching the default to self-hosting. Start with
[TOUR.md](TOUR.md) for the control flow and a guide to every module, or
[the benchmark suite](benchmarks/README.md) for the performance baseline.

The libraries in `src/snail-scheme/` separate source locations (`source.sld`),
the character reader (`reader.sld`), general parser combinators (`parser.sld`),
syntax records and accessors (`syntax.sld`), syntax parsing (`syntax-parser.sld`),
pattern matching and dispatch (`pattern.sld`), macro expansion (`expand.sld`),
and resolved HIR records (`hir.sld`).
`pmap` transforms parser values;
ordinary Scheme `map` operates on lists. The historical parser inspection CLI
lives in `cli.sld` and `main.scm`; the compiler command lives in `driver/`.
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
retain the filename. The historical `src/snail-scheme/main.scm` defines a parser
inspection procedure named `main`; it does not call that procedure itself.
Chibi's `-r` supplies the invocation:

```sh
chibi-scheme -I src -r src/snail-scheme/main.scm examples/fibonacci.scm
```

Compiling this definition-only file produces no output when run. The actual
compiler entry is `src/snail-scheme/compile.scm`, which invokes `compiler-main`
at top level; see [compiling the compiler](doc/backend.md#compiling-the-compiler).

`make test` runs `tests/snail-scheme/test.scm`, which loads the CLI, reader,
parser, syntax, and pattern test libraries from the same directory. Test helpers also
live there; production libraries do not load test code.

`pattern-dispatch` builds an ordered dispatcher from raw patterns (host datums) and
callbacks. It matches the whole input form; list literal identifiers explicitly
to dispatch on a head, or use `_` to ignore it:

```scheme
(import (scheme base) (snail-scheme pattern))

(define dispatch
  (pattern-dispatch '... '(define)
    (list
      (cons '(define name value)
        (lambda (captures)
          (map cdr captures))))))

(dispatch '(define x 42))                    ; => (x 42)
```

Dispatch returns the first callback value other than `#f`. A callback returning
`#f` declines its branch and dispatch tries the next pattern. If no callback
accepts, dispatch returns `#f`. Only `#f` is false in Scheme: `'()`, `0`, and `""`
all select their branch.
Callbacks receive an association list of `(name . capture)` entries in pattern
traversal order. Use `(cdr (assq 'name captures))` to retrieve a capture.
A singleton capture is the original datum, including an unchanged list tail or
opaque record. Repeated captures contain lists nested once per ellipsis, preserving
empty and ragged repetitions. The pattern library does not depend on syntax objects;
source locations and lexical identity belong to the reader and expander.
`pattern-dispatch` takes an ellipsis symbol, a literal list, and pattern/callback
pairs. Dispatch separates patterns and callbacks, parses the patterns independently,
and walks the parallel lists with `dispatch-against-pattern-list`.
Literal identifiers match by symbol spelling. The private dispatcher builder takes
explicit ellipsis, literal-list, and lookup arguments. Lookup maps literal symbols
and input datums to identities compared with `eqv?`; the public wrapper supplies
`(lambda (x) x)`.
Parsing classifies literal symbols without calling lookup. Matching resolves
literal symbols and input datums through lookup and constructs private match-result
records. A final pass flattens successful results into the callback alist.

Patterns support unique variables, wildcards, constants, dotted lists, vectors,
custom ellipses, and one repeated segment per sequence level. Bytevectors match
as constants. Invalid patterns, including duplicate variables, are rejected when
constructing the dispatcher. Successful matches can have an empty capture list.
List and vector patterns are parsed into a prefix, an optional repeated item, and
a suffix; lists additionally carry an optional improper-tail pattern. Matching
consumes the prefix, reserves and matches the suffix and tail, then matches the
repeated item against the remaining elements. Flattening preserves pattern order,
original datums, and empty and ragged repetition captures.
The binding-aware semantics of `syntax-rules` expansion,
including shadowed literals and exported auxiliary keywords, are documented in
[the macro design](doc/hir.md#literal-binding-identity).

`(snail-scheme expand)` provides `expand-program`, `expand-library`, and
`macroexpand-1`. It resolves imports and lexical bindings, expands `syntax-rules`
macros, and constructs fully expanded Scheme HIR for the supported core forms.
Library loading uses an explicit function parameter. Scope environments are
transient association lists passed through recursive descent.

`(snail-scheme hir)` defines the immutable records in
[the HIR design](doc/hir.md#hir-records). A `value-definition` holds a binding's
identity and definition location; a `name` refers to it and retains the reference
location. A `value-binding` pairs that identity with an initializer. Library
declarations and core expressions have separate records. HIR carries no types or
closure capture lists; `lower.sld` computes storage and captures while translating
to stack instructions. Type inference remains later work.
This is an initial core and library implementation, not complete R7RS support.
The compiler command runs this expansion before lowering and LLVM emission.

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

## Agent skills

The `.agents/skills/` submodule references [tsnl/skills](https://github.com/tsnl/skills).
Run `git submodule update --init .agents/skills` after cloning. Codex discovers
the skill folders there; `.claude/skills` symlinks to the same checkout for
Claude Code. See the
[skills README](https://github.com/tsnl/skills#use-with-codex-and-claude-code)
for setup and update instructions.
The [simplify skill](https://github.com/tsnl/skills/blob/main/simplify/SKILL.md)
guides explanation-driven simplification of recently written modules.
