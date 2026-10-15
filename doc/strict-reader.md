# Strict typed datum input

`(snail datum)` owns concrete `Symbol`, `Scalar`, `Number` and recursive `Datum`
values. `(snail read)` incrementally reads one datum from a `(snail io)` input
port. Scheme performs tokenization, syntax checking and construction; the same
Rust scalar exports supply Unicode file input, numeric conversion and symbol
interning on Wasm and native. No operation converts through `Top` or the legacy
value ABI.

## Results and resource ownership

`read : InputPort -> ReadResult` returns `read-value`, `read-end` or `read-error`.
The result data is defined in `(snail datum)` and re-exported by `(snail read)`.
`string->atom : String -> ReadResult` stages ordinary atom text once, then
checks number parsing, numeric errors and identifier validity in that order.
It returns a datum or syntax error; only input can produce `read-end`.
Their payload accessors are `read-value-datum` and `read-error-message`.
`read-end?` tests EOF; `read-value!` extracts a datum or reports a fatal diagnostic.
Syntax errors consume the characters already inspected and make no recovery
promise. Invalid UTF-8 and file errors retain the file library's fatal diagnostic
contract. Empty lists, false, NUL characters and empty strings remain valid data.

`read-char` and `peek-char` return `CharacterResult`, whose alternatives are
`character-end` and `character-value`. Lookahead belongs to the input port and
survives separate `read` calls. Normal file callbacks close on return, including
a returned syntax error. Invocation hosts call terminal resource cleanup after
traps; they must not resume the failed invocation.

Rust temporary tokens have explicit, monotonically increasing scalar handles.
Only live handles occupy the table. A handle starts as owned text and transitions
once to a numeric result, a nonnumeric result retaining its spelling, or an
error. Numeric getters validate both state and component type. Scheme copies the
result and closes the handle; symbol interning consumes owned text or a parsed
nonnumeric handle. It rejects and consumes parsed-number and numeric-error
handles; terminal failure cleanup also drops other outstanding handles. No
library operation calls user code while transferring a token. Separate handles
can be interleaved on one execution thread. Handles are thread-local and cannot
be transferred between threads. Terminal cleanup drops all outstanding tokens
without resetting their ID counter. These tokens hold no Scheme values or roots.

## Symbols and datums

`string->symbol`, `symbol->string` and `symbol=?` use exact Unicode scalar spelling,
without normalization or case folding. A returned string is a fresh mutable copy.
The root-free strict interner reuses the existing symbol storage implementation
but has its own identity domain, independent of legacy literal initialization.
Names and identities live until runtime destruction; port closure and failed
reads do not roll back interning. Neither strict symbols nor their IDs are
interchangeable with legacy symbols or compiler enumeration symbols.

`Datum` distinguishes null, Bool, Char, String, Symbol, Number, mutable pair,
`Vector Datum` and Bytevector. `datum-cons` allocates fresh pair fields as explicit
Refs; `datum-car`, `datum-cdr`, `datum-set-car!` and `datum-set-cdr!` expose their
ordinary aliasing. Strings, vectors and bytes retain their existing mutable
storage. The reader constructs acyclic data. Applications can create cycles via
mutation; `datum=?` compares finite graphs by their structural unfoldings,
including shared subgraphs and differently shaped but equivalent cycles.

`datum-null?`, `datum-pair?` and `datum-truth?` classify these values; only a
false Boolean datum is false, so the null datum remains true in a condition.
`datum-list`, `datum-length`, `datum-append`, `datum-assq` and `datum-map` operate
on finite proper list spines. Append copies the first spine and shares the final
suffix. Association lookup returns the original entry pair or a false datum.
Map invokes its procedure from left to right and constructs fresh spine nodes.

`datum-eq?` compares symbols by interned identity, atomic values by their existing
scalar equivalence, and mutable strings/vectors/bytes by backing storage.
Pairs have an explicit logical storage identity: both their first-field Ref and
their rest-field Ref must be identical. Each `datum-cons` creates two fresh Refs.
The public `datum-pair` constructor can also make two views of the same two Refs;
those views are aliases under this contract. Sharing only one field is not pair
identity. This API does not claim distinct wrapper-allocation identity or every
implementation-dependent choice of R7RS `eq?` for numbers.

The public `datum-pair` and `datum-vector` names are ordinary constructor
functions. Their internal variants are private, so callers cannot forge the
immutable IDs used by equality. Recursive variants are no longer public match
patterns. `datum-kind` returns the ordered tags 0 through 8 for null, Boolean,
character, string, symbol, number, pair, vector and bytevector. Read-only
projections expose the corresponding contents; `datum-car` and `datum-cdr`
return stored datums without allocating fresh views.

Each recursive view carries one positive I64 ID in addition to its existing
fields. Creating an alias gives it a different ID while retaining the public
storage identity above. A scalar counter supplies IDs and fails before
exhaustion; it never retains an object or recycles an ID. `Ref` cells and direct
WasmGC vector arrays keep their existing layouts.

Equality owns an explicit continuation stack and an open-addressed table of
ordered ID pairs. It records a comparison before descending, so a repeated edge
terminates without cancelling the pending checks. All traversal calls are tail
calls, including deep `car` chains. Input fields are never temporarily changed,
and every call starts with a fresh table, so mutation between calls is visible.
The table contains only integers, while pending continuations retain the Scheme
values they still need. Neither structure escapes the call.

With constant-time table operations, work is proportional to visited comparison
pairs, their child obligations, and leaf-content comparisons. This is not a
linear bound in arbitrary input graph size: cycles of coprime lengths can visit
the product of those lengths. The deterministic arithmetic hash avoids ordinary
sequential-ID correlations but can still suffer collisions. Union-find or a
stronger identity-map contract is future work if that general cyclic worst case
becomes significant.

`i64->string` constructs a fresh decimal String for every signed I64, including
the minimum value. Its digit loop uses a nonpositive magnitude so it never needs
an unrepresentable positive counterpart.

## Numbers and equality

`Number` distinguishes signed I64 exact integers, F64 inexact reals and complex
pairs of `Scalar` values. `string->number : String -> NumberResult` returns a
parsed value, `not-a-number`, or an explicit unsupported/range error.
`number->f64` accepts real-valued numbers, including complex values with zero
imaginary component, and rejects non-real values. It does not change how tokens
are parsed. Ordinary arithmetic remains the concrete operations in `(snail strict)`.

Numeric input supports binary/octal/decimal/hexadecimal integer prefixes and
`#e`/`#i`, decimal fractions and exponents, signed infinities/NaNs, rectangular
complex forms and inexact polar forms. Exact decimals are checked with decimal
digit arithmetic: `#e9007199254740993.0` remains exact, while `#e1.5` fails. Exact
integers must fit I64. Rational syntax, including `4/2`, and bignums are unsupported.
Finite-looking inexact overflow becomes infinity and underflow becomes signed
zero, following the selected Rust/IEEE conversion contract and tested Chez
behavior. The strict wrapper preserves the two exact polar axes after applying
prefix exactness: an exact zero magnitude produces exact zero, and an exact zero
angle preserves the magnitude. Thus `0@1.0` is exact zero, `1.0@0` is an inexact
real, and `#i1@0` remains an inexact complex value. Other polar conversion follows
the existing Rust helper's trigonometric implementation; shared source does not
promise identical transcendental rounding. Nontrivial exact polar forms fail.

Parsing applies exactness first, then collapses an exact imaginary zero to the
real component. Otherwise mixed exact/inexact complex components become inexact,
matching the selected Chez reader. The public data constructors expose their
representation directly; callers constructing numbers manually retain the given
variants rather than invoking parser normalization.

`number-equivalent?` and `datum=?` compare matching numeric variants and scalar
exactness. Exact `1` differs from inexact `1.0`; positive and negative zero differ;
all NaNs are equivalent; infinities keep their sign. Other binary64 values compare
by their bits. These choices match the tested Chez `eqv?`/`equal?` boundary for
reader-produced numbers. `datum=?` compares strings and characters by scalar
sequence, symbols by strict identity, pairs/vectors recursively and bytes by value.
It is structural equivalence, not the numeric `=` operation or allocation identity.

## Syntax boundary

The reader accepts proper/dotted lists, vectors, bytevectors, booleans, character
literals, strings, bar-escaped symbols, quote/quasiquote/unquote abbreviations,
Unicode whitespace, line comments, nested block comments and datum comments.
A datum comment parses and discards one complete datum, so malformed discarded
input is still an error. Bytevector entries must be exact integers in `[0,255]`.
Strings support scalar escapes and line continuations; physical CR/CRLF line
endings normalize to LF. Hexadecimal escapes reject surrogates and values above
U+10FFFF. Bar-escaped names preserve exact spelling, including empty/numeric names.

Unescaped identifiers use the existing Rust reader's affirmative grammar:
Unicode alphabetic characters and `!$%&*/:<=>?^_~@` initially, with ASCII digits,
`+`, `-` and `.` allowed subsequently, plus its peculiar sign/dot forms. This is
an explicit lexical subset, not a claim to every R7RS Unicode identifier category.
`123abc` is an error; `|123abc|` is a symbol. Datum labels/cycles, case directives,
square/brace delimiters, bare identifier escapes and unsupported numeric forms
are rejected. The reader does not silently reinterpret malformed numbers as
symbols.
