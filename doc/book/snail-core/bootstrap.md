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
itself. The compiled compiler runs on two engines, V8 and wasmtime, and
`make test-wasmtime`, which runs the suite on wasmtime, compares those on
Siegework.

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

## The native executable

`crates/snail` builds `build/snail`, a native executable that embeds
[wasmtime](https://wasmtime.dev) 48 and runs the compiled compiler without
Node. The compiler needs nothing else: the Rust runtime is merged into
`snailc.wasm`, so its only imports are 21 `wasi_snapshot_preview1`
functions. `build/snail run-compiler MODULE ARGUMENT ...` follows the
protocol `host/native/run-compiler.mjs` follows on Node:

1. WASI gets the module as its first argument, the environment with
   `SNAIL_CWD` naming the working directory, and the host's `/` preopened.
2. The module is instantiated, and `_initialize`, `main` and
   `compiler-compile` are called in turn.
3. A WASI exit with status 1 ends a failed compile and one that needs an
   input alike; then `compiler-request` publishes the pending request, after
   the stack that asked has unwound.
4. `close-resources` runs whatever happened. A nonzero answer, a trap or a
   failure of the host is status 2; a trap prints its Wasm frames.

`build/snail precompile MODULE OUTPUT` writes Cranelift's machine code for
a module as a `.cwasm` file, which loads in place of compiling the module:
the driver keeps `build/compiler/snailc.cwasm` beside the compiler, which
saves each compile about 0.7 s. The file belongs to one wasmtime version,
configuration and CPU, so it is a build output and is never committed.

Node is still the default engine. `SNAIL_ENGINE=wasmtime` runs every compile
on `build/snail` instead, the bootstrap's stages included; the driver builds
the executable with Cargo when it is stale, and `make bootstrap` builds it
first. Compiled programs still run on Node either way.

The engine is opt-in because it is slow. Wasmtime's one working collector,
deferred reference counting, collects whenever its list of possible stack
roots doubles past 1,024 entries, a constant in the code Cranelift
generates. Each collection walks every global of a GC type, resolving its
type, and the compiler has 1,539 of them; that and the collector's
free-list allocator take most of a compile. Warm, in seconds:

| Compile | Node | wasmtime | wasmtime, no collector |
| --- | --- | --- | --- |
| `tests/programs/wire.sld` | 0.10 | 0.94 | 0.08 |
| `tests/programs/http.sld` | 0.14 | 2.0 | 0.15 |
| Siegework | 0.36 | 10.1 | 0.87 |
| The compiler itself | 1.31 | 47 | 4.75 |

Without collecting at all, wasmtime matches Node on small compiles but takes
3.6 times as long on the compiler, since each allocation and each read of a
function reference stored in a GC object is a call into the runtime; it then
needs 2.2 GB, of a GC heap wasmtime addresses with 32 bits. Switching the
default waits for a compile within three times Node's, the gate
[#562](https://github.com/tsnl/snail-scheme/issues/562) sets. The
backend emitting fewer globals of GC types would cut each collection's cost
directly.

**Proposed** in #562, not implemented: running WASI-only programs on
`build/snail`, then one `snail` executable that embeds the compiler and the
project builder as precompiled images, replacing the shell, Node and Chibi
chain for `snail build` and `snail run`, with Chibi kept for stage 0.
