# Proposed layout reader

**Draft for approval; the layout extension is not implemented.** Extend
S-expressions with a colon that opens an indented block. Inside that block,
newlines delimit forms and indentation supplies list structure. Preserve
Scheme's calls, bindings, symbols, macros, and final-expression results.
There is no backslash grouping or line-continuation syntax.

The compatibility target is precise: every source accepted by the existing
reader that contains no active layout colon must produce the same sequence
of datums, with the same locations. The only proposed carveout is an
unquoted terminal colon outside an explicitly delimited or quoted datum. This is a
reader extension, not the earlier Python-style language proposal.

## What programs look like

```text
#lang snail
(import
 (snail core base)
 (snail core io))

(: fibonacci (-> I64 I64))
define (fibonacci n):
    if (< n 2):
        n
        + (fibonacci (- n 1)) (fibonacci (- n 2))

begin:
    define answer:
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

(begin
  (define answer (fibonacci 30))
  (write-line (show answer)))
```

`(ask)` is a zero-argument call. Bare `ask` is a reference to its binding.
A function body has the value of its last expression. `if`, `begin`, and
handlers retain their existing meanings. There is no new `return` form,
early-return translation, or special function-body protocol.

The reader does not know that `define` introduces a function or that `if`
has branches. It constructs lists; existing expansion gives them meaning.

## Why layout needs a marker

Traditional Scheme already accepts these inputs:

| Input without a layout marker | Existing reading, retained here |
| --- | --- |
| `f x` | Two datums, `f` and `x`. |
| `f(x)` | Two datums, `f` and `(x)`. |
| `f()` | Two datums, `f` and the empty list. |
| `(f) (g)` | Two complete forms. |
| `(f x)` | One form, a call when used as an expression. |
| `(ask)` | One form, a zero-argument call in expression position. |

Making bare top-level `f x` a call or treating `f(x)` as postfix application
would change existing source. Newlines alone cannot both change that
reading and preserve a strict superset. The colon marks where layout rules
start; within an explicit list, ordinary S-expression reading resumes.

Use `begin:` to opt a sequence of program expressions into line notation:

```text
begin:
    define answer:
        fibonacci 30
    write-line (show answer)
    (newline)
```

Outside a colon-opened block, ordinary forms remain ordinary forms and
newlines remain whitespace. Merely indenting an existing source file does
not opt it into layout. The proposal does not promise global bare-line
calls and strict compatibility at the same time.

## Three construction rules

**A line in a layout block.** Read its datums using the traditional reader.
One datum represents itself; two or more become a list. Empty and
comment-only lines contribute nothing.

| Line inside a layout block | Constructed datum |
| --- | --- |
| `answer` | `answer` |
| `42` | `42` |
| `(ask)` | `(ask)` |
| `write-line (show answer)` | `(write-line (show answer))` |
| `+ x y` | `(+ x y)` |
| `(make-worker) message` | `((make-worker) message)` |

Application is one ordinary list: `f g x` becomes `(f g x)`, not a curried
call. Write `f (g x)` for nesting. A bare zero-argument name is never called
automatically. In a layout block, `f()` supplies two datums on one line and
therefore constructs `(f ())`; it is not an alternative spelling of `(f)`.

**A header ending in a colon.** Construct one list from the header's datums
followed by each datum constructed by the indented body. The colon forces
list construction even if the header or body contains just one datum.

```text
f x:
    g y
    z
```

reads as `(f x (g y) z)`. A colon does not insert `begin`, make a thunk, or
decide whether its children are statements. Call evaluation and macro
expansion follow the equivalent parenthesized form.

**A colon-only header.** An empty header constructs a list of its children.
This supplies grouping without an extra backslash marker:

```text
let:
    :
        x 10
        y 20
    + x y
```

reads as `(let ((x 10) (y 20)) (+ x y))`. Explicit lists are often clearer
for short groups, so the same form may be written:

```text
let ((x 10) (y 20)):
    + x y
```

A colon block must contain at least one child. Use `()` for an empty list;
it keeps its existing meaning and does not become the `Unit` value.
Write `(unit)` when the program needs `Unit`.

## Existing S-expressions are the escape hatch

Parentheses keep their exact meaning. In particular, `(x)` is a list with
one element, not expression grouping around a variable. Whitespace inside
parentheses is insignificant, including newlines and indentation. Brackets
retain the current reader's list-delimiter behavior; they do not become
Python list literals or generic type application.

An explicit form can span as many lines as needed:

```text
begin:
    (write-line
      (string-append "hello, "
                     (ask)))
    (newline)
```

There is no line-continuation character. For a long line, write its complete
S-expression across lines, or use a colon block to construct its argument
list. Explicit lists themselves never enable indentation parsing. To put
an indented child block inside a call, write that enclosing call in layout
notation; a trailing colon inside a parenthesized form stays an ordinary
symbol character.

Grouping is local to the new block context. Two forms on the same block
line, `(f) (g)`, construct `((f) (g))` under the first construction rule.
Write them on separate lines to sequence them. Outside layout, those same
characters remain two forms. This does not weaken the compatibility claim
for complete legacy sources without an active colon.

## Bodies, bindings, and macros

Nothing about binding scope, mutability, or return values changes. Existing
top-level and local-body rules still apply. Indentation records list
structure; it does not independently introduce lexical scope.

A two-branch `if` has two child expressions. Use an explicit `begin` child
when a branch needs several expressions:

```text
define (report n):
    if (< n 0):
        write-line "negative"
        begin:
            write-line "nonnegative"
            write-line (show n)
```

The reader does not recognize Python-style `else:` clauses. The existing
`cond` macro already provides named alternatives:

```text
cond:
    (< n 0):
        write-line "negative"
    else:
        write-line "nonnegative"
```

It reads as `(cond ((< n 0) (write-line "negative"))
(else (write-line "nonnegative")))`. A parenthesized datum in a header is
one element of the list the colon constructs, not a list to splice.

Macros receive precisely the same forms as their parenthesized spelling:

```text
unless ready:
    write-line "waiting"
    (retry)
```

reads as `(unless ready (write-line "waiting") (retry))`. There is no new
body wrapper or group-pattern language for `syntax-rules` to understand.
Existing pattern repetition and hygiene remain the expander's job.

The earlier preferred `def answer = fibonacci 30` spelling can be an
ordinary library macro, used inside a layout block. It need not become a
reader production or reserve `=`. For example, a proposed helper could
use these rules:

```scheme
(define-syntax def
  (syntax-rules (=)
    ((_ name = value) (define name value))
    ((_ name = callee first rest ...) (define name (callee first rest ...)))))
```

Then, after importing that helper, the desired notation is:

```text
begin:
    def answer = fibonacci 30
    write-line (show answer)
```

The initial reader extension does not depend on adding this macro to the
standard library. `define answer:` already works with the existing forms.

## Symbols and the colon carveout

Keep current spelling and lexical rules: `write-line`, `ref-get`, `bump!`,
`empty?`, and `a.b` remain symbols. `-` remains a prefix operation, and
`a-b` remains an identifier. There is no new infix precedence table, dot
projection syntax, snake_case alias scheme, or postfix call notation in
this proposal. Types keep their existing notation, such as `(List I64)`.

Semicolon comments, strings, quote abbreviations, characters, byte vectors,
and other data retain the behavior the current reader implements. The
compatibility claim covers accepted reader input, not unimplemented R7RS
features. For example, it does not add dotted lists to Snail-Core.

A layout marker is an unquoted colon at the end of a logical header line,
outside strings, comments, characters, and explicit parentheses/brackets.
It may be attached to the last header token, as in `begin:`, or separated
by whitespace. Remove that terminal colon before reading the header's
datums. An isolated `:` is the empty-header case. A trailing `;` comment
after the marker is permitted.

Only one terminal colon is reserved. An identifier ending in a run of two
or more colons remains an identifier. Internal colons in `foo:bar`, and
the prefix of `::count`, keep their existing meaning. Strings such as
`"label:"`, the character `#\:`, and quoted symbols such as `'label:`
are not block openers. Datum comments consume a traditional datum before
layout processing resumes.

Explicit S-expressions preserve colon symbols too. In particular,
`(: square (-> I64 I64))` continues to be the current signature form,
even if formatted over multiple lines. A source that uses an unquoted
terminal colon symbol at a layout boundary must keep the traditional
reader or rewrite that occurrence explicitly. This is the stated carveout;
the reader must not silently fall back when a colon block is malformed.

## Layout and diagnostics

- The first child establishes a block's indentation, deeper than the start
  of its header. Siblings align. Dedents close blocks and must return to an
  enclosing layout column; unexpected indentation is an error.
- Newlines end logical forms only in a colon-opened block and outside
  explicit S-expressions. A multiline explicit datum is one datum; its
  internal indentation does not affect the surrounding block.
- Blank and comment-only lines do not open or close blocks. Newlines
  inside strings and block comments are not statement separators. A final
  logical form can end at EOF without a final newline.
- Use spaces for layout indentation, with four spaces as the formatting
  convention. Tabs in active layout indentation are diagnosed. Legacy
  whitespace, including tabs inside ordinary S-expressions or outside
  layout, retains its existing interpretation.
- A colon with no indented children is an error at the marker. Unmatched
  explicit delimiters retain the traditional reader's diagnostics. Invalid
  dedents report the line and the enclosing block's opening location.

Multiline and datum comments need explicit treatment: indentation belongs
to the first significant datum on a logical line, not skipped comment text.
The source location of each existing datum is preserved; a synthesized
list is located at its header, its first line datum, or its colon-only marker.

## Incremental reader design

The t-expression and n-expression work is useful precedent for extending
S-expressions incrementally. SRFI 110 adds indentation and additional
grouping markers; its compatibility section concerns suitably formatted
S-expressions, not every traditional source. SRFI 105's neoteric call
notation changes the reading of adjacent forms such as `f(x)`, and its
curly infix intentionally supplies no conventional operator precedence.
This proposal borrows the incremental approach and uses colon-delimited
layout to preserve the stricter compatibility boundary. It does not claim
conformance to either complete SRFI. See
[SRFI 110](https://srfi.schemers.org/srfi-110/srfi-110.html) and
[SRFI 105](https://srfi.schemers.org/srfi-105/srfi-105.html).

The implementation boundary becomes:

```text
source header -> traditional reader with optional layout construction
              -> existing located syntax
              -> existing hygienic expansion, checking, and lowering
```

There is no second language grammar, return-normalization pass, or new macro
syntax representation. Reuse the traditional reader for explicit datums;
the added layer owns logical line endings, the active indentation stack,
and construction of the omitted lists. It must not stringify and reparse
the result. Reading remains pure apart from reporting source failures.

The reader does not synthesize binding names: a colon constructs a list
from the identifiers the programmer wrote. Their binding and hygiene are
therefore the same as in the equivalent explicit list. The formatter may
retain comments, source ranges, and which delimiters were explicit; those
details do not belong in the compiler's semantic IR.

## Migration and verification after approval

Retain per-file selection: `#lang snail` chooses the extended reader and
`#lang snail/sexp` chooses exact traditional reading, including colon
symbols. Selection does not propagate through imports. During migration,
headerless existing files continue to use the traditional reader. Avoid a
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

Verification must establish both parts of the contract:

1. Differentially read existing source with both modes after accounting
   for headers. Every file without an active layout colon must produce
   identical syntax and datum locations, regardless of line breaks or
   indentation. Include multiple forms on one line, adjacent delimiters,
   quotes, colon signatures, comments, tabs, and multiline strings.
2. Pair layout examples with their explicitly parenthesized equivalents.
   Compare syntax, then execute programs using definitions, local bindings,
   conditionals, macros, mutation, handlers, and ownership. Include
   colon-only headers, singleton and multi-datum lines, malformed blocks,
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

The proposal is limited to colons, logical newlines, and indentation as a
way to construct existing S-expressions. It selects `(ask)` for a nullary
call, ordinary Scheme results and binding rules, and no backslash syntax.
Compatibility excludes only active layout-colon occurrences.

Infix, neoteric postfix calls, new type notation, dot projection, `return`,
and the callable/place/effect proposals are separate decisions. The optional
`def` helper above is a library convenience, not a prerequisite for the
reader. Implementation still waits for explicit approval of this revision.
