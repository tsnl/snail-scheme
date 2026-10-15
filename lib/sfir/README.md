# SFIR libraries

These are ordinary libraries for the [bare SFIR language](../../doc/sfir.md).
The compiler reads each `.sfir` file directly. Import `(sfir base)` for scalar
operators and homogeneous collections, then import the libraries required by the
program. No Scheme expansion or source generator participates in loading them.

Builtin types such as `I64`, `String`, `Ref` and `Vector` are SFIR type syntax.
They are available without an import and are not library exports. Nominal types
such as `Integer`, `Number`, `Datum` and `InputPort` belong to their declaring
library. Import modifiers preserve those identities and the identity of shared
overload families.

| Library | Responsibility |
| --- | --- |
| `base` | Static scalar overloads, `Default`, and homogeneous vector/string operations. Only primitive function values come from `(sfir primitive)`. |
| `io` | Scalar file services, explicit shared-handle ownership, borrowed standard streams, line input and text output. |
| `math` | Binary64 trigonometry, exponentials and logarithms through scalar externs. |
| `text` | Unicode scalar properties, full string case folding and lexical string ordering. |
| `bytes` | Packed bytes, checked copies and strict UTF-8 conversion. |
| `integer` | Exact signed integers, arithmetic, division, roots and correctly rounded binary64 conversion. |
| `rational` | Exact normalized ratios with positive coprime denominators. |
| `number` | Concrete exact/inexact real and rectangular complex values, arithmetic, comparison and formatting. |
| `datum` | Interned symbols, numeric token interpretation, explicit heterogeneous data and finite graph equality. |
| `read` | Incremental datum input with explicit token, container and error results. |
| `write` | Datum write/display, finite graph analysis, labels and explicit output continuations. |
| `compiler-builder` | Complete library syntax, typed inspection and owned transfer handles. |
| `compiler` | Explicit maps, parsing, compilation and checked Wasm execution services. |

## Source and representation contracts

The initial extraction started from `src/snail/{strict,io,math,text,bytes,integer,rational,number,datum,read,write}.sld`
at commit `2db2216b32254bbaf9b49ebed30e0bca495ec6c2`. `strict` becomes
`core`, subsequently renamed `base`; the other module names stay the same. All 393 value definitions, 24
nominal data declarations, 126 overload signatures and 44 typed foreign
declarations are retained. Foreign module/provider strings and scalar signatures
are unchanged, so the same Rust implementations serve Wasm and native execution.

The libraries retain concrete storage and explicit mutation. Integer limb arrays
are private scratch storage until publication; rationals normalize at construction;
numeric exactness and binary64 signed-zero rules remain visible in the numeric
modules. Datums retain distinct mutable storage identity and recursive view IDs.
Fixed-width arithmetic is checked. Datum hashing explicitly imports wrapping
word operations; nominal `Number` inexact arithmetic and the named exact-to-F64
conversions explicitly retain IEEE overflow results. `(sfir math)` scalar
services also retain IEEE overflow and domain behavior.
Graph equality and output keep their existing work lists and cycle handling.
No generic evaluator, boxed replacement algorithm or reduced numeric domain is
introduced by the migration.

`string-foldcase` follows the [Unicode 16 default full mappings](https://www.unicode.org/Public/16.0.0/ucd/CaseFolding.txt)
and returns fresh mutable string storage, including for empty and unchanged
strings. A first traversal computes the checked output length; a second fills
it. Rust returns scalar mapping lengths and components, without receiving
managed strings or allocating temporary strings. The generated casing exceptions
record Rust's Unicode baseline and require regeneration when it changes.

Every former procedure definition is an explicit `def` containing a lambda,
with any existing signature attached. A lambda has one body expression;
`begin` supplies ordered statements and a final value. A statement `let` binds
its name only after its initializer. The surface migration preserves each old
parallel let with a fresh block: all initializers run before aliases introduce
the old names. Existing nested blocks remain separate lexical scopes.

The 79 local recursive loops use a fresh lexical `begin`, an explicit lambda
definition and the initial call. Their original initializers contain no reference
to the loop binding, so this change does not capture an outer name. Call operands
retain left-to-right, exactly-once evaluation. These blocks must not be flattened
into their enclosing lexical scope.

Boolean short-circuiting is explicit `if`: a strict Boolean operand is evaluated
once, and later operands run only on the required branch. Count/range checks,
mutation order and foreign-call order are unchanged. In particular, default
vectors validate before invoking user code, zero invokes no default, and the
first default value initializes private storage before later slots are replaced.
File close detaches the shared handle before a potentially failing native close;
closing borrowed standard streams remains a no-op. Callback helpers close after normal
return without adding exception recovery.

Small accessors and conversions remain direct. Recursive construction loops,
multi-step numeric transitions, exhaustive data dispatch and the final tests can
exceed the ten-line target when their explicit binding and sequencing make the
whole operation easier to follow. They retain their original cohesive operations
instead of introducing helpers solely to reduce a line count.

## Tests and current validation

The final `Tests` sections of `text`, `integer`, `rational`, `number`, `datum`,
`read` and `write` retain all existing test bodies. Each exposes one ordinary
`test-<module>` function returning `42` on success; helpers remain private. These
exports are always available in SFIR, replacing the old `snail-tests` conditional
expansion. A program can call them directly without a language feature flag.

Empty lists use the polymorphic `empty-list` operation. Quoted list syntax is
rejected.
The private reader delimiter test constructs its twelve integer elements with
explicit `cons` calls. This is the only test-allocation adaptation; no production
constant or benchmark kernel changes allocation behavior.

The initial extraction's structural audit checked bare-form arities, retained definitions, attached
signatures, data/overload/foreign declarations, numeric/string/character constants
and non-control application inventories. Its only extra non-control calls are
the reader test's twelve `cons` operations. This audit supplements execution; it
does not establish runtime correctness by itself.

The historical source checkpoint `3ae7928`, before the published surface
migration, passed the following execution checks:

- A core fixture returned `42` on raw and mandatory-Binaryen-optimized Wasm,
  including the invocation guard. The same fixture also passed with committed
  frontend `b74e437`.
- Every retained `test-<module>` entry point returned `42` on raw linked Wasm,
  optimized linked Wasm, native64 and native64 with collection forced at each
  allocation opportunity.
- Focused I/O checks passed on both linked Wasm forms and native64. They cover
  generic file callbacks, CR/LF/CRLF and EOF, exact Unicode and minimum-I64 output,
  borrowed stdout, and closed-alias reads and empty writes. The positive native
  check also passed with forced collection. Node verified that owned descriptors
  drained and standard descriptors stayed open.

The combined module and I/O checks used a frozen 97-file compiler snapshot taken
before `b74e437`; its individual source hashes are retained with the command
records. The later core smoke used the committed compiler itself. The first
combined build was deliberately interrupted after discovering the private
nonempty-quote test assumption. The first I/O fixture was correctly rejected
because its negative-check export returned a nominal value; its corrected export
discards that value and returns `Unit`. Both initial records are retained.

These are library correctness checks, not complete benchmark-suite coverage or
performance measurements. Historical strict-Scheme measurements remain historical.
The [surface migration manifest](../../tests/sfir/surface-migration.json) records
original, mechanically migrated, and formatted source hashes. Formatting preserves
every syntax token and comment. Its checks do not revalidate the historical
execution artifacts against the new compiler surface.

The focused `core`/`io` clarity review used the pinned
[simplify skill](../../.agents/skills/simplify/SKILL.md), a fresh explainer without
repository access, and informed debate about scope, initialization, short-circuit
behavior and port lifetime. It supported the explicit control forms above and
retaining native bulk copies, initialized vector storage, CR/LF/CRLF behavior,
empty-write lifetime checks and the existing minimum-I64 formatting algorithm.

The former `artifacts.sld` belonged to the removed Scheme build machinery.
`compiler-builder.sfir` constructs and inspects complete SFIR library syntax.
Compiled producers transfer owned values into Chibi through the checked
[builder protocol](../../doc/sfir-builder.md). The
[source driver](../../doc/sfir-generation.md) executes explicit `generate-library`
recipes. `compiler.sfir` provides first-class parsing, explicit library maps,
compilation, loading, independent instances and checked scalar invocation through
the Chibi-hosted [compiler service](../../doc/sfir-compiler-service.md). That service
currently targets Wasm; [native loading](../../doc/sfir-native-loading.md) uses its
separate host adapter. Source discovery and provider installation remain explicit
driver operations.
