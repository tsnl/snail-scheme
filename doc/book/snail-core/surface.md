# Proposed layout reader

**Draft for approval; the layout extension is not implemented.** Extend
S-expressions with logical newlines that delimit forms and indentation that
supplies list structure. No colon or backslash marker is needed. Preserve
Scheme's calls, bindings, symbols, macros, and final-expression results.

The new reader deliberately changes how datums outside explicit lists are
grouped: `f x` on one line reads as `(f x)`. It is not a strict superset of
traditional S-expression reading. Inside parentheses, ordinary reading
resumes; the separate `#lang snail/sexp` mode preserves legacy source exactly.
This is a change to list construction, not a new expression language.

## What programs look like

```text
#lang snail
(import
 (snail core base)
 (snail core io))

(: fibonacci (-> I64 I64))
define (fibonacci n)
    if (< n 2)
        n
        + (fibonacci (- n 1)) (fibonacci (- n 2))

define answer
    fibonacci 30
write-line (show answer)
```

After the header, this reads as exactly:

```scheme
(import
 (snail core base)
 (snail core io))

(: fibonacci (-> I64 I64))
(define (fibonacci n)
  (if (< n 2) n (+ (fibonacci (- n 1)) (fibonacci (- n 2)))))

(define answer (fibonacci 30))
(write-line (show answer))
```

`(ask)` is a zero-argument call. Bare `ask` is a reference to its binding.
A function body has the value of its last expression. `if`, `begin`, and
handlers retain their existing meanings. There is no new `return` form,
early-return translation, or special function-body protocol.

The reader does not know that `define` introduces a function or that `if`
has branches. It constructs lists; existing expansion gives them meaning.

## The compatibility tradeoff

Layout applies at the top level as well as inside indented blocks. There is
no marker to enable it and no need for an enclosing `begin` merely to write
several forms on separate lines. These readings assume no indented children:

| Input on one logical line | Traditional reader | Layout reader |
| --- | --- | --- |
| `f x` | Two datums, `f` and `x`. | `(f x)` |
| `f(x)` | Two datums, `f` and `(x)`. | `(f (x))` |
| `f()` | Two datums, `f` and the empty list. | `(f ())` |
| `(f) (g)` | Two complete forms. | `((f) (g))` |
| `(f x)` | `(f x)` | `(f x)` |
| `(ask)` | `(ask)` | `(ask)` |

The new mode does not interpret `f(x)` as postfix application. It reads two
ordinary datums and groups them, just as it does for `f (x)`. Write `f x`
or `(f x)` to call `f` with the value of `x`.

Existing source must not be silently switched to layout mode: a line break,
indentation, or multiple forms on one line can change its structure. Explicit
lists retain their internal reading, but that is not a compatibility claim
for the entire enclosing file. Keep the traditional reader available.

## Two construction rules

**A line without indented children.** Read its datums using the traditional
reader. One datum represents itself; two or more become a list. Empty and
comment-only lines contribute nothing.

| Line without indented children | Constructed datum |
| --- | --- |
| `answer` | `answer` |
| `42` | `42` |
| `(ask)` | `(ask)` |
| `write-line (show answer)` | `(write-line (show answer))` |
| `+ x y` | `(+ x y)` |
| `(make-worker) message` | `((make-worker) message)` |

Application is one ordinary list: `f g x` becomes `(f g x)`, not a curried
call. Write `f (g x)` for nesting. A bare zero-argument name is never called
automatically. In layout mode, `f()` supplies two datums on one line and
therefore constructs `(f ())`; it is not an alternative spelling of `(f)`.

**A line with indented children.** Construct one list from the line's datums
followed by each datum constructed by its children. Having children forces
list construction even when the header is a single datum, such as `begin`.

```text
f x
    g y
    z
```

reads as `(f x (g y) z)`. Indentation does not insert `begin`, make a thunk, or
decide whether its children are statements. Call evaluation and macro
expansion follow the equivalent parenthesized form.

These rules apply recursively at every layout depth. A parenthesized datum
in a header is one element, not a list to splice: `(f)` with an indented
`x` constructs `((f) x)`, whereas `f` with an indented `x` constructs
`(f x)`. To put a body inside an explicit form, enclose it within that form
or write the enclosing form in layout notation.

There is no empty-header grouping marker. Use explicit parentheses for
anonymous lists such as a `let` binding list. Use `()` for an empty list;
it keeps its existing meaning and does not become the `Unit` value. Write
`(unit)` when the program needs `Unit`.

## Existing S-expressions are the escape hatch

Parentheses keep their exact meaning. In particular, `(x)` is a list with
one element, not expression grouping around a variable. Whitespace inside
parentheses is insignificant, including newlines and indentation. Brackets
retain the current reader's list-delimiter behavior; they do not become
Python list literals or generic type application.

An explicit form can span as many lines as needed:

```text
(write-line
  (string-append "hello, "
                 (ask)))
(newline)
```

There is no line-continuation character. For a long line, write its complete
S-expression across lines, or use indented children to construct its argument
list. Explicit lists themselves never enable indentation parsing. To put
an indented child block inside a call, write that enclosing call in layout
notation. Formatting within parentheses never opens a layout block.

Two forms on the same logical line, `(f) (g)`, construct `((f) (g))` under
the first construction rule. Write them on separate lines to sequence them.
Under the traditional reader, those same characters remain two forms.

## Let and nested bodies

Keep the binding list explicit and indent the body:

```text
let ((x 10)
     (y 20))
    write-line (show x)
    + x y
```

This reads as:

```scheme
(let ((x 10)
      (y 20))
  (write-line (show x))
  (+ x y))
```

Each child is a body expression; the last supplies the result. The binding
list's internal indentation is formatting only, so each binding pair still
needs its parentheses. The enclosing header starts at `let`; the closing
parenthesis's column does not set the body's indentation.

Bodies nest by the same rule:

```text
let ((x 10))
    let ((y (+ x 1)))
        write-line (show y)
        + x y
```

This reads as `(let ((x 10)) (let ((y (+ x 1)))
(write-line (show y)) (+ x y)))`. No extra `begin` is inserted. Named `let`
also uses its existing shape:

```text
let loop ((n 3))
    if (= n 0)
        0
        loop (- n 1)
```

## Bodies, bindings, and macros

Nothing about binding scope, mutability, or return values changes. Existing
top-level and local-body rules still apply. Indentation records list
structure; it does not independently introduce lexical scope.

A two-branch `if` has two child expressions. Use an explicit `begin` child
when a branch needs several expressions:

```text
define (report n)
    if (< n 0)
        write-line "negative"
        begin
            write-line "nonnegative"
            write-line (show n)
```

The reader does not recognize Python-style branch clauses. The existing
`cond` macro already provides named alternatives:

```text
cond
    (< n 0)
        write-line "negative"
    else
        write-line "nonnegative"
```

It reads as `(cond ((< n 0) (write-line "negative"))
(else (write-line "nonnegative")))`. A parenthesized datum in a header is
one element of the constructed list, not a list to splice.

Macros receive precisely the same forms as their parenthesized spelling:

```text
unless ready
    write-line "waiting"
    (retry)
```

reads as `(unless ready (write-line "waiting") (retry))`. There is no new
body wrapper or group-pattern language for `syntax-rules` to understand.
Existing pattern repetition and hygiene remain the expander's job.

The earlier preferred `def answer = fibonacci 30` spelling can be an
ordinary library macro, used anywhere in layout notation. It need not become
a reader production or reserve `=`. For example, a proposed helper could
use these rules:

```scheme
(define-syntax def
  (syntax-rules (=)
    ((_ name = value) (define name value))
    ((_ name = callee first rest ...) (define name (callee first rest ...)))))
```

Then, after importing that helper, the desired notation is:

```text
def answer = fibonacci 30
write-line (show answer)
```

The initial reader extension does not depend on adding this macro to the
standard library. A `define answer` header with an indented expression
already constructs the existing form.

## Symbols and data

Keep current spelling and lexical rules: `write-line`, `ref-get`, `bump!`,
`empty?`, and `a.b` remain symbols. `-` remains a prefix operation, and
`a-b` remains an identifier. There is no new infix precedence table, dot
projection syntax, snake_case alias scheme, or postfix call notation in
this proposal. Types keep their existing notation, such as `(List I64)`.

Semicolon comments, strings, quote abbreviations, characters, byte vectors,
and other data retain the lexical behavior the current reader implements.
This does not add unimplemented R7RS features, such as dotted lists, to
Snail-Core. Quote abbreviations and datum comments consume one traditional
datum, not the rest of a layout line or an indented block. For example,
`'f x` reads as `((quote f) x)`; write `'(f x)` to quote the whole list.

Colons remain ordinary symbol characters everywhere. `foo:bar`, `::count`,
`label:`, and the standalone `:` retain their spelling. There is no optional
colon marker: a `begin:` header with a child constructs `(begin: child)`,
not `(begin child)`. `(: square (-> I64 I64))` continues to be the current
signature form, even if formatted over multiple lines.

## Layout and diagnostics

- Top-level forms start at column zero. The first child establishes a block's
  indentation, deeper than the start of its header. Siblings align. Dedents
  close blocks and must return to an enclosing layout column. Any nonempty
  logical line may have children; no keyword or trailing marker is required.
- Newlines end logical lines outside explicit S-expressions and datums
  whose reading spans lines. A multiline explicit datum is one datum; its
  internal indentation does not affect the surrounding block.
- Blank and comment-only lines do not open or close blocks. Newlines
  inside strings and block comments are not form separators. A final
  logical form can end at EOF without a final newline.
- Use spaces for layout indentation, with four spaces as the formatting
  convention. Tabs in layout indentation are diagnosed. Whitespace inside
  explicit S-expressions, and all whitespace under the traditional reader,
  retains its existing interpretation.
- A line without children is valid by the first construction rule. Missing
  arguments or bodies are for expansion and checking to diagnose from the
  constructed form. Unmatched explicit delimiters retain the traditional
  reader's diagnostics. Invalid dedents report the line and the enclosing
  block's opening location.

Multiline and datum comments need explicit treatment: indentation belongs
to the first significant datum on a logical line, not skipped comment text.
The source location of each existing datum is preserved; a synthesized
list is located at its first header or line datum.

## Incremental reader design

The t-expression and n-expression work is useful precedent for extending
S-expressions incrementally. SRFI 110 adds indentation and additional
grouping markers; its compatibility section concerns suitably formatted
S-expressions, not every traditional source. SRFI 105's neoteric call
notation changes the reading of adjacent forms such as `f(x)`, and its
curly infix intentionally supplies no conventional operator precedence.
This proposal borrows the incremental approach, accepting changes to
grouping outside explicit lists so layout needs no colon or backslash
markers. It retains the existing datum reader rather than adopting
neoteric postfix calls or curly infix. It does not claim conformance to either
complete SRFI. See
[SRFI 110](https://srfi.schemers.org/srfi-110/srfi-110.html) and
[SRFI 105](https://srfi.schemers.org/srfi-105/srfi-105.html).

The implementation boundary becomes:

```text
source header -> selected reader, reusing traditional datum reading
              -> existing located syntax
              -> existing hygienic expansion, checking, and lowering
```

There is no second language grammar, return-normalization pass, or new macro
syntax representation. Reuse the traditional reader for explicit datums;
the added layer owns logical line endings, the active indentation stack,
and construction of the omitted lists. It must not stringify and reparse
the result. Reading remains pure apart from reporting source failures.

The reader does not synthesize binding names: layout constructs a list
from the identifiers the programmer wrote. Their binding and hygiene are
therefore the same as in the equivalent explicit list. The formatter may
retain comments, source ranges, and which delimiters were explicit; those
details do not belong in the compiler's semantic IR.

## Migration and verification after approval

Retain per-file selection: `#lang snail` chooses layout reading and
`#lang snail/sexp` chooses exact traditional reading. Selection does not
propagate through imports. During migration, headerless existing files
continue to use the traditional reader. Avoid a
tree-wide header or source conversion until bootstrap supports it.

Generated binary syntax and program data-reading APIs keep their existing
protocols. An embedded fragment takes its reader mode explicitly. Do not
infer a reader from whether a file happens to begin with parentheses.

Chibi loads compiler sources directly during stage 0. Before converting
those sources, provide a tested adapter that itself runs on Chibi through
the deliberate bootstrap include closure, handles source headers, lowers
layout to ordinary forms, and preserves source mapping. It must not need
an already-compiled Snail compiler. Other libraries and examples can use
the reader before the compiler source is migrated.

Verification must establish the mode boundary as well as list construction:

1. Read existing source through the traditional mode and compare with the
   current reader, accounting for headers. Preserve syntax and datum
   locations regardless of line breaks or indentation. Include multiple
   forms on one line, adjacent delimiters, quotes, colon signatures,
   comments, tabs, and multiline strings.
2. Compare explicit datums in both modes when each starts on its own logical
   line at column zero and has no layout children. Vary whitespace inside
   lists freely. Separately assert the intentional differences for `f x`,
   `f(x)`, `f()`, multiple forms on one line, and indented children. Include
   quoted datums and colon-suffixed symbols with no marker interpretation.
3. Pair layout examples with their explicitly parenthesized equivalents.
   Compare syntax, then execute programs using definitions, local and named
   `let`, nested bodies, conditionals, macros, mutation, handlers, and
   ownership. Include singleton and multi-datum headers, multiline binding
   lists, malformed dedents, comments between siblings, EOF without a newline,
   and mixed-reader imports. Formatting must preserve those readings.

Run the relevant local compiler checks, including `make test`, `make check`,
`make test-chibi`, and `make bootstrap`; execute linked Wasm. Formatter and
editor changes must share the reader's layout decisions and be exercised
through the existing browser tests. Until layout formatting is implemented,
the editor must preserve extended source instead of applying Lisp indentation
that changes its meaning. Use Rust checks if Rust sources change.

## Completing the documentation

This is a temporary review chapter. Completing the feature includes replacing
it with the implemented reader contract: rename the title and book navigation
to **Source syntax**, remove draft/approval language and implementation plans,
and update the Terms link to the final reference. Keep one authoritative
description of the reader and its compatibility boundary. Move genuinely
deferred work to GitHub issues or the relevant proposed-semantics chapter;
do not retain an obsolete proposal beside the implemented documentation.

## Review boundary

The proposal is limited to logical newlines and indentation as a way to
construct existing S-expressions. It selects `(ask)` for a nullary call,
ordinary Scheme results and binding rules, explicit `let` binding lists,
and no colon or backslash markers. Layout mode deliberately changes grouping
outside explicit lists; traditional reader mode preserves legacy input.

Infix, neoteric postfix calls, new type notation, dot projection, `return`,
and the callable/place/effect proposals are separate decisions. The optional
`def` helper above is a library convenience, not a prerequisite for the
reader. Implementation still waits for explicit approval of this revision.
