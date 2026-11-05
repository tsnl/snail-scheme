# Source syntax

Snail reads either traditional S-expressions or layout syntax, selected by
an optional `#lang` header. Layout uses logical newlines and indentation to
construct ordinary lists; it needs no colon or backslash marker. Calls,
bindings, symbols, macros, and final-expression results retain Scheme's rules.

Outside explicit lists, `f x` on one line reads as `(f x)`, so layout is not
a strict superset of traditional reading. Inside parentheses, ordinary
reading resumes. Headerless files and `#lang snail/sexp` preserve traditional
reading. Only `examples/fibonacci.sld` and `examples/scheme-fibonacci.sld`
have been converted among the examples; the compiler and standard libraries
remain traditional source.

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

The spelling `def answer = fibonacci 30` can be an ordinary library macro,
used anywhere in layout notation. It does not require a reader production
or reserving `=`. A library can define it with these rules:

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

This helper is not part of the standard library. A `define answer` header with an indented expression
already constructs the existing form.

## Symbols and data

Keep current spelling and lexical rules: `write-line`, `ref-get`, `bump!`,
`empty?`, and `a.b` remain symbols. `-` remains a prefix operation, and
`a-b` remains an identifier. There is no new infix precedence table, dot
projection syntax, snake_case alias scheme, or postfix call notation in
layout syntax. Types keep their existing notation, such as `(List I64)`.

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
- Use spaces for layout indentation, with two spaces per level as the
  writing convention. The reader accepts any consistent increase;
  it does not require exactly two spaces. Tabs in layout indentation are
  diagnosed. Whitespace inside explicit S-expressions, and all whitespace
  under the traditional reader, retains its existing interpretation.
- A line without children is valid by the first construction rule. Missing
  arguments or bodies are for expansion and checking to diagnose from the
  constructed form. Unmatched explicit delimiters retain the traditional
  reader's diagnostics. Invalid dedents report the line and the enclosing
  block's opening location.

Indentation is the physical column of the first significant datum on a
logical line. A leading inline comment therefore contributes to that column,
although tabs inside comment text are not checked as indentation. The source
location of each existing datum is preserved; a synthesized list is located
at its first header or line datum.

## Incremental reader design

The t-expression and n-expression work is useful precedent for extending
S-expressions incrementally. SRFI 110 adds indentation and additional
grouping markers; its compatibility section concerns suitably formatted
S-expressions, not every traditional source. SRFI 105's neoteric call
notation changes the reading of adjacent forms such as `f(x)`, and its
curly infix intentionally supplies no conventional operator precedence.
The layout reader borrows the incremental approach, accepting changes to
grouping outside explicit lists so layout needs no colon or backslash
markers. It retains the existing datum reader rather than adopting
neoteric postfix calls or curly infix. It does not claim conformance to either
complete SRFI. See
[SRFI 110](https://srfi.schemers.org/srfi-110/srfi-110.html) and
[SRFI 105](https://srfi.schemers.org/srfi-105/srfi-105.html).

The implementation boundary is:

```text
source header -> selected reader, reusing traditional datum reading
              -> existing located syntax
              -> existing hygienic expansion, checking, and lowering
```

There is no second language grammar, return-normalization pass, or new macro
syntax representation. Reuse the traditional reader for explicit datums;
the added layer reads nonempty logical lines and constructs their nested
lists by sibling column. Each line stores its first datum separately, which
establishes that it is nonempty and supplies its location. Reading remains
pure apart from reporting source failures; it never prints and reparses
syntax.

The reader does not synthesize binding names: layout constructs a list
from the identifiers the programmer wrote. Their binding and hygiene are
therefore the same as in the equivalent explicit list. The formatter may
retain comments, source ranges, and which delimiters were explicit; those
details do not belong in the compiler's semantic IR.

## Resolving `#lang`

`read-source-file` in `src/snail/shell/compiler/inputs.sld` passes file text
to `read-source-text` in `read.sld`. That entry point resolves the header
before reading any body datums. Resolution is a fixed mapping to two
built-in readers:

| Source-file header | Reader |
| --- | --- |
| `#lang snail` | Layout: logical lines and indentation construct lists. |
| `#lang snail/sexp` | Traditional: whitespace separates ordinary datums. |
| No header | Traditional, preserving existing files during migration. |

These are exact, case-sensitive names. The slash in `snail/sexp` is part of
the name; it is not a library path. Resolution does not search import
directories, evaluate a binding, load a package, or run a reader supplied by
the source. A future user-defined reader mechanism would need its own
loading and bootstrap contract; it is not implemented.

### Recognizing the header

Recognize the standalone `#lang` token only at column one of the first
physical line, before reading any datums. The line contains `#lang`, one or
more spaces or tabs, and one reader name, optionally followed by horizontal
whitespace and a semicolon comment. LF, CRLF, or EOF terminates the header.
For example:

```text
#lang snail ; use layout in this file
define (square n)
  * n n
```

A missing name, an unknown name, or additional non-comment tokens is a
header error at the offending source location. Report the supported names;
do not retry with another reader. The scanner does not skip blank lines or
comments to find a later directive. Only the initial header selects a mode;
later text, including `#lang` in a string or explicit datum, is handled by
the selected reader and cannot switch modes.

Parse the header into a reader choice and the index where its body starts.
Keep the original source and its line table: the first body line is still
line two, and a diagnostic points into the original file. Do not strip the
header and restart positions at line one. A header-only file has an empty
body; a headerless file starts reading at index zero.

### Using the selected reader

`read-source-text` in `read.sld` takes text and a filename and returns the
existing `List Syntax`, with source locations from the original file.
`source-header` returns a `SourceHeader` containing the `ReaderMode` and the
body's starting index; `SexpReader` and `LayoutReader` are the two modes.
Expansion and checking see the same representation in both modes. `read-text`
remains the traditional datum-reading API for callers such as compiler-request
parsing; it does not interpret source headers.

Resolve each entry file and each imported library independently. For
example, a file using `#lang snail` can import a file using
`#lang snail/sexp`; a headerless dependency still uses the migration default.
Library lookup continues to use the existing import paths. `#lang` chooses
only the reader: it neither imports libraries implicitly nor changes a
file's declared library name or its exported bindings.

Compiler file loading and dependency discovery reach the same selector.
The highlighter uses `source-header` too, marking a valid initial `#lang` as
a keyword and an invalid one as an error without losing the remaining text.
No imports are inferred from the selected mode.

## Formatting and bootstrap

The command-line formatter and the IDE's save and Tab paths preserve any
file beginning with a `#lang` directive unchanged. This includes traditional,
unknown, and unfinished headers.
[Layout-aware reformatting](https://github.com/tsnl/snail-scheme/issues/686)
is not implemented;
applying Lisp indentation would change the program's grouping. Use two spaces
per level when writing layout source. Headerless files continue to use the
existing Lisp formatter.

Generated binary syntax and data-reading APIs keep their existing protocols.
Project descriptions such as `project.datum` are data, not source files;
the source header does not apply to them. Reader selection is not guessed
from a filename or from whether the first expression uses parentheses.

The compiler's own sources remain headerless S-expressions. Chibi loads them
directly during stage 0, and that running compiler can read layout programs
and libraries through `read-source-text`. Converting compiler sources would
require a separate header/layout adapter in Chibi's bootstrap include closure;
that migration has not been made.

The reader's unit tests cover headers, indentation, lexical boundaries,
locations, and diagnostics. Program fixtures exercise both directions of
mixed-reader imports and ordinary macros, bindings, and branches. The two
converted Fibonacci examples keep their existing expected outputs. The
compiler remains subject to the same source-on-Chibi and self-bootstrap
checks as the other passes.
