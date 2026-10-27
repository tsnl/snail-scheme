# Bootstrap and self-hosting

The compiler is a Snail-Core program that compiles itself, and Chibi Scheme runs
that same source as stage 0. Both are possible because of one property of
Snail-Core's core: delete its typed forms, replacing them with untyped R7RS
equivalents, and the result is an R7RS program with the same behavior
whenever the Snail-Core program does not trap or overflow.

| Snail-Core | R7RS after erasure |
| --- | --- |
| `(struct (Vec3 T) ((x T) (y T) (z T)))` | `(define-record-type Vec3 (Vec3 x y z) Vec3? (x Vec3-x) (y Vec3-y) (z Vec3-z))` |
| `(enum (Option T) (Some ((value T))) (None))` | One record type per case (`Some`, `None`) and a predicate `Option?` that tests the cases. |
| `(: ...)`, `(type ...)` | Removed, including effect rows. |
| `(effect Log ((log T)) ...)` | A parameter holding a record of implementations and the outer record, and a procedure per operation that calls the current implementation with the parameter rebound to the outer record. The shim supplies host defaults. |
| `(handle Log ((log impl)) body ...)` | `(parameterize ((Log (make-Log impl))) body ...)` |
| `(ann e T)`, `(type-convert e T)` | `e` |
| `(match e ((Some v) a) ((None) b))` | `(let ((x e)) (cond ((Some? x) (let ((v (Some-value x))) a)) ((None? x) b)))` |
| Typeclass method | A generic procedure that dispatches on its first argument's record predicate. |
| `I64`, `F64` literals | Exact integers and flonums. |

Each `define-record-type` creates a fresh runtime type, so struct identities and
enum cases stay distinct after erasure.

**The compiler is written in that core.** No host-specific code appears in the
passes. Hosts differ only in library implementations, which is ordinary
in Scheme, where every implementation provides its own `(scheme base)`:

- **On Snail-Core.** The typed forms are built in, and the compiler's libraries,
  `(snail-core base)`, `(snail-core table)` and `(snail-core io)`, are Snail-Core libraries backed by
  WASI.
- **On Chibi.** `host/chibi/` implements the same three libraries with
  Chibi's own procedures, and `(snail-core forms)` defines `:`, `struct`, `enum`,
  `type` and `match` as erasing macros. The compiler defines no typeclass
  instances of its own, so nothing dispatches at run time.

The shared driver reads its arguments and files through `(snail-core io)`, and both
entries publish missing-input requests after unwinding.

Stage 0's only search root is `bootstrap/chibi-include/`: one symlink per
library the compiler's own load closure reaches, and nothing else, so no other
library under `src/` can enter the bootstrap by accident. Reaching for one
fails with `couldn't find import`, which is how `make test-chibi` and
`make bootstrap` catch a compiler module that starts importing the standard
library.

The hosts disagree on integer overflow, argument evaluation order and the
order of table keys, so the compiler's output must not depend on them. The
places that once did are closed: every generated name derives from what it
names — a lambda from the hash of its own text, a string from its content,
an import from its module and symbol — and a pass that expands, specializes
or emits sibling subexpressions sequences them rather than letting the host
choose. Declarations are listed by name. So the two hosts emit the same text
for the same program, and the build checks it: `make test` compares them on
`examples/fibonacci.sld`, and `make bootstrap` compares them on the compiler
itself.

**Bootstrap.**

1. Stage 0 is the previous compiled compiler, or, the first time, the
   compiler's source running on Chibi.
2. Stage 0 compiles the source to Wasm, giving stage 1.
3. Stage 1 compiles stage 2.
4. Stage 2 must reproduce its own text exactly.
5. When Chibi was stage 0, stage 1's text must be stage 2's as well: the two
   hosts ran the same source on the same input.

The driver repeats this whenever the compiler's source changes, so a pinned
Wasm build bootstraps without Chibi. Chibi remains the host of the first
bootstrap and of `make test-chibi`.
