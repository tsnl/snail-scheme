# Lofi libraries

This namespace contains the [Lofi language](../../doc/book/lofi/index.md) libraries.
The compiler implementation is under
[`compiler/`](compiler/README.md), separate from the standard library. All library
sources use `.sld`. Import `(lofi core)` for named kernel syntax and `(lofi base)`
for scalar operators and homogeneous collections. The sibling `(scheme base)`
library adds Scheme forms through hygienic macros.

All functions have fixed arity. Collection conveniences such as `vector` and
`string-append` are packing macros; their list-taking workers are ordinary
first-class functions. See [packing macros and workers](../../doc/book/lofi/macros.md#packing-macros-and-first-class-workers).

Builtin types such as `I64`, `String`, `Ref` and `Vector` are Lofi type syntax.
They are exported by `(lofi core)` and remain intrinsic in the low-level kernel
for existing direct source/constructed-library APIs. Nominal types
such as `Integer`, `Number`, `Datum` and `InputPort` belong to their declaring
library. Import modifiers preserve those identities and the identity of shared
overload families.

| Library | Responsibility |
| --- | --- |
| `core` | Intrinsic syntax manifest, including declarative macro definitions and types. |
| `primitive` | Intrinsic primitive function manifest. |
| `compiler bootstrap` | Chibi implementation of compilation; loaded through `bootstrap/`. |
| `base` | Static scalar overloads, `Default`, and homogeneous vector/string operations. Only primitive function values come from `(lofi primitive)`. |
| `io` | Scalar file services, explicit shared-handle ownership, borrowed standard streams, line input and text output. |
| `math` | Binary64 trigonometry, exponentials and logarithms through scalar externs. |
| `text` | Unicode scalar properties, full string case folding and lexical string ordering. |
| `bytes` | Packed bytes, checked copies and owned UTF-8 conversion. |
| `integer` | Exact signed integers, arithmetic, division, roots and correctly rounded binary64 conversion. |
| `rational` | Exact normalized ratios with positive coprime denominators. |
| `number` | Concrete exact/inexact real and rectangular complex values, arithmetic, comparison and formatting. |
| `datum` | Interned symbols, numeric token interpretation, explicit heterogeneous data and finite graph equality. |
| `read` | Incremental datum input with explicit token, container and error results. |
| `write` | Datum write/display, finite graph analysis, labels and explicit output continuations. |
| `scalar-text` | Scalar text tokens, interned symbols and diagnostics. |
| `serialization` | Checked serialization capabilities and derived concrete data instances. |
| `sexp` | Shared S-expression graph and text/binary wire encodings. |

## Source and representation contracts

The scalar-services crate in [`src/runtime/`](../runtime/Cargo.toml) supplies
scalar services for linked Wasm; the input packet extension is described below.

The libraries retain concrete storage and explicit mutation. Integer limb arrays
are private scratch storage until publication; rationals normalize at construction;
numeric exactness and binary64 signed-zero rules remain visible in the numeric
modules. Datums retain distinct mutable storage identity and recursive view IDs.
Fixed-width integer arithmetic wraps at its declared width, while floats retain
IEEE overflow and domain results. Literal construction and narrowing remain
checked. Datum hashing's named word operations have the same wrapping contract.
Nominal `Number` inexact arithmetic, the named exact-to-F64 conversions and
`(lofi math)` scalar services also retain IEEE results; unbounded `Integer`
arithmetic remains exact.
Graph equality and output use explicit work lists and cycle handling.

`string-foldcase` follows the [Unicode 16 default full mappings](https://www.unicode.org/Public/16.0.0/ucd/CaseFolding.txt)
and returns fresh mutable string storage, including for empty and unchanged
strings. A first traversal computes the checked output length; a second fills
it. Rust returns scalar mapping lengths and components, without receiving
managed strings or allocating temporary strings. The generated casing exceptions
record Rust's Unicode baseline and require regeneration when it changes.

Boolean short-circuiting is explicit `if`: a strict Boolean operand is evaluated
once, and later operands run only on the required branch. Count/range checks,
mutation order and foreign-call order are unchanged. In particular, default
vectors validate before invoking user code, zero invokes no default, and the
first default value initializes private storage before later slots are replaced.
File close detaches the shared handle before a potentially failing host close;
closing borrowed standard streams remains a no-op. Callback helpers close after normal
return without adding exception recovery.

Recursive construction loops, multi-step numeric transitions, exhaustive data
dispatch and the final tests can exceed the ten-line target when keeping them
together makes the whole operation easier to follow.

## Text input cursor

An owned `InputPort` contains shared mutable cells for its host handle and
pending input packet. All aliases share both cells. Character, line and datum
readers consume that cursor, including CR/LF/CRLF lookahead. The handle is
checked before pending input: explicit close clears the packet and detaches
the handle before closing the host resource, so cached characters and cached
EOF cannot be read after close. Callback cleanup still occurs on normal return;
terminal trap cleanup releases owned Rust resources.

The private `snail:io/read-packet` scalar service demands one character through
the existing UTF-8 reader. If that character is ASCII, it may consume up to six
more ASCII bytes already in the Rust buffer. It never refills the buffer or
decodes a non-ASCII suffix to enlarge a packet. Thus a valid prefix remains
observable before a later UTF-8 error, and batching does not wait for additional
input. A positive I64 holds up to seven nonzero byte lanes, each `ASCII code + 1`;
zero marks exhausted lanes and leaves NUL distinct. `-1` represents EOF, and
`-code - 2` represents one validated non-ASCII scalar. The bounded encoding fits
in I64; the decoding arithmetic stays in range and conversions remain checked.

Peek retains the pending character or EOF. Read consumes one character and
clears an EOF packet, preserving the previous behavior if a file later grows.
Borrowed stdin uses the existing Rust scalar read/peek cursor on every operation,
so its aliases and direct foreign scalar reads share lookahead. Closing stdin
remains a no-op. Owned file handles remain private to their Lofi wrappers; no
public operation exposes a raw handle that could bypass pending input.

`scripts/test-lofi-input-packets` exercises raw and optimized linked Wasm,
retains all command attempts and source/tool/artifact identities, and verifies
packet boundaries, Unicode buffer splits, aliases, mixed readers,
borrowed scalar interoperation, closed cached input, file growth after EOF,
valid output before malformed input, and resource release.

## Tests

The final `Tests` sections of `text`, `integer`, `rational`, `number`, `datum`,
`read` and `write` each expose one ordinary `test-<module>` function returning
`42` on success; helpers remain private. These exports are always available in
Lofi programs, without a feature flag, so tests can call them from linked Wasm.

## Compiler

The [source driver](../../doc/lofi-generation.md) executes explicit
`generate-library` recipes: each compiles to Wasm and returns its library as
source text. Source discovery and provider installation remain explicit driver
operations. The engine owns managed references and machine code; Rust scalar
services live in `src/runtime/`.
