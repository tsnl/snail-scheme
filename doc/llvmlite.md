# Immutable LLVM construction

`(snail-scheme llvmlite)` constructs typed LLVM IR and writes its text to a port.
It borrows the types, values, instructions, blocks, functions, and module
vocabulary from Python's [llvmlite.ir](https://llvmlite.readthedocs.io/en/latest/user-guide/ir/index.html).
It is a small Scheme implementation of that idea, not a binding to Python or
LLVM. The Python API's mutable insertion-point builder is replaced by immutable
references and definitions.

[`llvm.sld`](../src/snail-scheme/llvm.sld) owns the Scheme VM protocol: runtime
signatures, tagged constants, safepoints, slot lifetimes, and the mapping from
VM instructions to control flow. [`llvmlite.sld`](../src/snail-scheme/llvmlite.sld)
owns LLVM types, operand checks, and textual spelling. It has no knowledge of
Scheme objects or garbage collection. Target metadata and optimization remain
in `runner/build.rs`.

## References before definitions

Create a function reference, its block references, and any SSA values first.
Then describe their definitions. Branches hold block objects and instructions
hold value objects; callers do not interpolate `%label` or `%value` strings.
Forward branches and loop backedges need no mutation or placeholder patching.

This complete module defines a countdown loop:

```scheme
(import (scheme base) (prefix (snail-scheme llvmlite) ir:))

(define function (ir:function "countdown" ir:i32 '()))
(define entry (ir:block function "entry"))
(define loop (ir:block function "loop"))
(define step (ir:block function "step"))
(define done (ir:block function "done"))
(define index (ir:local function ir:i32 "index"))
(define next (ir:local function ir:i32 "next"))
(define more (ir:local function ir:i1 "more"))
(define (word n) (ir:integer ir:i32 n))

(define definition
  (ir:define-function
   function 'external '()
   (list
    (ir:block-body entry '() (ir:br loop))
    (ir:block-body loop
                   (list (ir:phi index (list (cons (word 10) entry)
                                            (cons next step)))
                         (ir:icmp more 'sgt index (word 0)))
                   (ir:cbr more step done))
    (ir:block-body step (list (ir:binop next 'sub index (word 1))) (ir:br loop))
    (ir:block-body done '() (ir:ret index)))))

(ir:write-module (ir:module (list definition)) (current-output-port))
```

The first body is the function's entry. Every body has an instruction list and
a separate terminator. A phi takes `(value . predecessor-block)` pairs, including
references to values whose definitions appear later. Reuse the same references
when building different immutable definitions or modules. There is no current
block, hidden name counter, or insertion cursor.

## Names, types, and validation

A local name is scoped to its function object. Reconstructing a local or block
with the same owner and spelling denotes the same LLVM name. Two different
function objects are different scopes, even when their function names have the
same spelling. Construction rejects operands and branch targets from another
scope. This prevents an accidentally foreign reference from silently resolving
to a same-named local.

Names are nonempty strings, with quoting and UTF-8 escaping handled by the
writer. `(ir:indexed-name "b" 12)` is also accepted wherever a name is required.
It represents `b12` without converting the number into a temporary string. Its
prefix must be a valid unquoted identifier and its index an exact nonnegative
integer. It shares the namespace with `"b12"` and `(ir:indexed-name "b1" 2)`;
it does not allocate a unique identity. Name accessors return the supplied string
or indexed-name object.

Constructors do not mutate their arguments or previously constructed objects.
Treat lists and strings supplied to them as immutable afterward, too; the
library retains them without deep copying. This is a value-oriented API, not a
deep-freezing facility for mutable Scheme containers.

Types compare structurally. Instruction constructors check operand types,
result types, and call arity. A block checks function ownership, leading phi
placement, the single terminator, and return type. LLVM's verifier remains the
authority on missing or duplicate definitions, dominance, matching phi
predecessors, and other whole-function rules. Run `opt -passes=verify` on emitted
IR; construction is not a substitute for verification.

## Implemented vocabulary

| Operation | API |
| --- | --- |
| Types | `void`, `ptr`, `i1`, `i8`, `i32`, `i64`, `int-type`, `array-type`, `type=?` |
| Typed operands | `local`, `parameter`, `integer`, `null-pointer`, `inttoptr`, `value-type` |
| Function and block references | `function`, `block`, `indexed-name` |
| Data and arithmetic | `call`, `load`, `store`, `icmp`, `zext`, `binop`, `phi` |
| Terminators | `br`, `cbr`, `ret`, `switch` |
| Definitions | `block-body`, `define-function`, `declare`, `global-bytes`, `global-array` |
| Output | `module`, `write-module`, `write-definition`, `utf8-bytes` |

Function parameter specifications are `(type . name)` pairs. `parameter` uses
a zero-based index. Result-producing instructions receive an existing `local`
as their first argument; `call` also accepts `#f` to discard its result.
`ret` uses `#f` for a void return. `switch` takes `(integer-constant . block)`
cases and an explicit default block. `global-array` currently accepts integer
constants; `global-bytes` accepts byte lists without adding a null terminator.

Function definitions accept `external`, `internal`, or `private` linkage and
the `alwaysinline`, `noinline`, `nounwind`, and `cold` attributes. The supported
subset covers the current backend and the arithmetic loop above. Struct types,
GEP, metadata, exceptions, parameter attributes, and LLVM/JIT bindings are not
implemented. Add concrete typed operations when a backend change needs them.

The writer streams definitions to a port. It neither accumulates a complete
module string nor exposes raw-text instructions. The constructor checks remain
local and linear; they do not maintain a mutable definition registry.
Scalar tokens use `write-simple`, avoiding Chibi's shared-structure traversal
tables for integer output. The bootstrap `(scheme write)` exports that operation
as an alias of its existing simple `write` primitive.

## Verification

`make test` calls `test-llvmlite`, the sole test entry point exported by
`llvmlite.sld` when `snail-tests` is enabled. Its private unit tests cover
deterministic reuse, type and scope errors, malformed blocks, and byte escaping.
`scripts/test-backend` additionally assembles and executes the standalone
`tests/emit-llvmlite.scm` fixture through this API on native and WASI. It includes
a loop with two phi backedges, arithmetic, a Unicode function name, an array
load, and a switch whose default reports failure. The existing Scheme semantic
fixtures exercise the migrated emitter with collection at every VM safepoint.
