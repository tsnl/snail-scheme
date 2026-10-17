# Native loading and independent instances

The optional Scheme protocol in
[`(wasm-native execute)`](../wasm-native/scheme/wasm-native/execute.sld) loads
x86-64 Linux objects carrying the fixed scalar bridge, links explicit foreign
providers, and creates independent instances. The separate
[`(lofi native)`](../src/lofi/native.sld) adapter converts a compiler
Wasm artifact into such an object. Chibi still hosts compilation, and the compiler
always emits Wasm. The native package imports no compiler modules.

Repository host scripts use
`chibi-scheme -I "$repo/bootstrap" -I "$repo/wasm-native/scheme" SCRIPT`.
Loading an existing object needs only `-I "$package/scheme"`. Supply the
package directory explicitly as `runtime-root`:

```scheme
(import (scheme base) (wasm-native process) (wasm-native execute))

(define runtime-root "/absolute/path/to/checkout/wasm-native")
(define code (load-native (read-bytes "counter.o")))
(define linked
  (link-native code (list (runtime-provider)) "build/counter-loading" runtime-root))
(define first (instantiate linked))
(dynamic-wind
  (lambda () #f)
  (lambda () (invoke-entry first '(10)))
  (lambda () (close-instance first)))
```

Here `counter.o` is the object written by
`(artifact->native-object artifact imports directory output)` for a selected
public `(-> I32 I32)` export. Its `artifact` comes from
`(compile libraries (make-entry library-key public-name))`; `imports` explicitly
declares the program's physical Rust scalar imports with `make-native-import`
from `(wasm-native)`. The caller creates the build `directory` and supplies the
object `output` path. The adapter preserves the Wasm artifact's semantic scalar
signature and origin description while separately invoking native lowering.
Loading snapshots bytes and returns immutable `library`, `export`, `parameters`,
`result` and `imports`
descriptions. Linking retains commands, object bytes and executables under a
fresh private subdirectory of the supplied directory. Each instantiation retains
its own `stdout`, `stderr` and `process.json`. The caller owns these retained
files. No library initializer runs during loading or linking.

Cargo links the shared Rust runtime for terminal cleanup. Resolving its scalar
imports additionally requires the explicit `(runtime-provider)` value.
`(make-rust-provider module source-path)` supplies another Rust crate with
literal scalar `extern "C"` exports. The source's module/name pairs, exported
symbols and physical signatures must match the artifact declarations. Pointer,
variadic and other unsupported declarations fail before linking. Source hashes
are checked across compilation; output aliases cannot overwrite inputs.

The Rust declaration is the unsafe foreign boundary. Comparing its ABI with the
required signature does not verify an arbitrary native function implementation.
Native artifacts, Rust providers, compiler tools and the host environment are
trusted executable inputs. This adapter is not a native-code verifier or sandbox.

## Entry evidence and transport

[`scalar-entry.sld`](../wasm-native/scheme/wasm-native/scalar-entry.sld) resolves the actual
Binaryen-optimized Wasm module and checks that `main` has `() -> Unit` and
`entry` has the recorded physical signature. Automatic start functions are
rejected. It adds a fixed `i64 (ptr)` LLVM bridge to the same module. The bridge
loads scalar bit words, makes a statically typed direct call to `wasm.entry`,
and returns scalar bits. No discovered function pointer is cast to a
caller-selected function type. Arguments and results cannot contain managed
references or native heap pointers.

The relocatable ELF object retains a versioned `.lofi.entry` JSON section,
the bridge arity, and an alias of the bridge whose name encodes the semantic
signature. Loading checks the ELF target, metadata schema, arity and alias
identity before publishing code. These checks detect an incompatible object or
inconsistent saved metadata. They cannot authenticate or prove the behavior of
arbitrary machine code. The adapter's checked construction establishes the
bridge contract, just as the trusted native runtime establishes its own ABI.
The protocol retains the existing section and symbol names, including
`.lofi.entry`, and the saved Bool/Char tags. It owns their scalar encoding and
checks; the source adapter supplies the semantic signature and library/export
description. Generic Wasm-to-native lowering receives only the Wasm
representation, physical imports and runtime contract.

| Lofi type | Scheme value and transport |
| --- | --- |
| I32 | Exact integer in signed 32-bit range. |
| I64 | Exact integer in signed 64-bit range, without a floating conversion. |
| F32 | Inexact real, rounded once to binary32; finite overflow is rejected. |
| F64 | Inexact real, with binary64 bits transported directly. |
| Bool | `#f` or `#t`, encoded as canonical 0 or 1. |
| Char | A Scheme character containing one Unicode scalar, excluding surrogates. |
| Unit result | Symbol `unit`; the fixed result word must be zero. |

Floating transport preserves signed zero, infinities, NaN and subnormals; it
does not promise a particular NaN payload. F32 underflow may round to zero.
Managed entry parameters/results and Unit parameters are unsupported. The
adapter accepts at most 1024 entry parameters. Both argument count and every
semantic argument are checked before a request is sent. Invalid arguments leave
the instance usable. Invalid result representations invalidate it.

## State and lifetime

Each instance executes a fresh native image with its own program globals,
managed collector and process-local provider state. Instances can share the
immutable linked executable. Separate loads and separate instantiations never
silently share mutable program state. Sharing an instance is explicit; providers
can also explicitly share external files or services.

The existing compiled initialization plan runs dependencies first, in source
order, once for each library identity. Import aliases and re-exports preserve
that identity. The adapter publishes an opaque instance only after the worker
acknowledges successful initialization. Failure raises a Scheme error,
returns no instance, and preserves external effects already performed. Ordinary
native terminal cleanup still closes Rust-owned resources on a guest trap.

[`native_worker.rs`](../wasm-native/src/native_worker.rs) supports two executables:
a supervisor with no guest/provider linkage, and a guest worker. Before executing
the guest image, the supervisor establishes an owned process group. Thus foreign
provider constructors execute inside that ownership too. The supervisor becomes
a Linux subreaper, observes host death through `PR_SET_PDEATHSIG`, and kills and
reaps surviving descendants. A descendant ignoring SIGTERM receives SIGKILL.
Adopted children that escape the group are also killed and reaped when observed;
an unexpected surviving descendant makes a command fail. Arbitrary hostile
providers remain outside the trusted native boundary.

Commands and replies travel through dedicated inherited pipes; program stdout
and stderr go to regular log files and cannot fill an undrained output pipe.
The adapter-created bridge fixes the request arity; there is one outstanding
call at a time. I64 and IEEE values use little-endian binary words, not textual
numbers. Scalar words are never treated as GC roots. The compiled exported
function publishes its managed roots across collecting calls as usual.

`(instantiate linked '((timeout . 30) (environment . ())))` supports a positive finite
startup deadline. The same timeout bounds each later request and response
together. Timeout, trap, worker exit, interrupted call or invalid response closes
the instance; a later call cannot consume an old response or restart execution.
This differs from the Wasm adapter, which can retain a successfully initialized
instance after an invocation trap. Calls and close reject concurrent use of the
same instance. Distinct instances can run concurrently.

`close-instance` is idempotent. It requests ordinary resource cleanup, waits up
to two seconds, then requests supervisor termination; the supervisor allows a
short grace period before killing the guest group. Forced termination and host
loss guarantee process ownership cleanup under ordinary Linux scheduling, but
cannot guarantee application-level flushing or rollback. A task stuck in an
uninterruptible kernel operation can delay reaping. Dropping the last instance
handle uses the same cleanup operation; explicit close makes its timing clear.

## Verification

`scripts/test-lofi-native-loading` compiles real Entry artifacts and executes
native machine code. It covers independent mutable state, aliases, captured
references with collection at every allocation, all scalar types, incorrect
provider declarations, descriptor forgery, altered metadata, Rust scalar calls,
Rust resource cleanup, failed initialization, invocation traps, interrupted
startup/calls, publication failure, concurrent calls/close, real timeouts,
provider constructors, TERM-ignoring descendants and abrupt host death.
It also records mandatory Binaryen invocations and compares the native and Wasm
routes' optimized module bytes exactly. Every attempt retains build commands and
per-instance logs, including failures.
