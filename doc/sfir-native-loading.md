# Native loading and independent instances

The Python adapter in [`execute_native.py`](../src/snail-sfir/execute_native.py)
loads compiler-produced x86-64 Linux objects, links explicit foreign providers,
and creates independent instances. Chibi still hosts compilation. This adapter
does not add a Scheme frontend, self-hosting, or an SFIR compiler service.

With `src/snail-sfir` on the Python module search path:

```python
from pathlib import Path
from execute_native import (
    load_native, link_native, instantiate, invoke_entry, close_instance,
    CProvider, RustProvider,
)

code = load_native(Path("counter.o").read_bytes())
linked = link_native(code, [RustProvider()], Path("build/counter-loading"))
first = instantiate(linked)
second = instantiate(linked)
try:
    result = invoke_entry(first, [10])
finally:
    close_instance(first)
    close_instance(second)
```

Here `counter.o` is the byte sequence returned by `compile` with a
`native64-target`, for a selected public `(-> I32 I32)` export. The target must
declare the Rust scalar imports used by that program. Loading snapshots bytes
and returns immutable `library`, `export`, `parameters`, `result` and `imports`
descriptions. Linking retains commands, object bytes and executables under a
fresh private subdirectory of the supplied directory. Each instantiation retains
its own `stdout`, `stderr` and `process.json`. The caller owns these retained
files. No library initializer runs during loading or linking.

The native linker uses the existing Rust archive for terminal resource cleanup.
Resolving Rust scalar imports additionally requires the explicit `RustProvider()`
value. `CProvider(module, header, source)` supplies a small scalar C interface.
Clang reads its header declarations and compiles the `.c` source with that header
included. Required module/name pairs, C symbol spellings and physical signatures
must match the artifact declarations. Pointer, variadic, unprototyped and other
unsupported declarations fail with diagnostics. Arbitrary C object/archive
providers are unsupported by this adapter; the lower-level native build driver
has its separate interface.

The header is the unsafe foreign boundary. Comparing its declared ABI with the
required signature does not verify an arbitrary native function implementation.
Native artifacts, C/Rust providers, compiler tools and the host environment are
trusted executable inputs. This adapter is not a native-code verifier or sandbox.

## Entry evidence and transport

[`native-entry.sld`](../src/snail-sfir/native-entry.sld) resolves the actual
Binaryen-optimized Wasm module and checks that `main` has `() -> Unit` and
`entry` has the recorded physical signature. Automatic start functions are
rejected. It adds a fixed `i64 (ptr)` LLVM bridge to the same module. The bridge
loads scalar bit words, makes a statically typed direct call to `wasm.entry`,
and returns scalar bits. No discovered function pointer is cast to a
caller-selected function type. Arguments and results cannot contain managed
references or native heap pointers.

The relocatable ELF object retains a versioned `.sfir.entry` JSON section,
the bridge arity, and an alias of the bridge whose name encodes the semantic
signature. Loading checks the ELF target, metadata schema, arity and alias
identity before publishing code. These checks detect an incompatible object or
inconsistent saved metadata. They cannot authenticate or prove the behavior of
arbitrary machine code. The compiler's checked construction establishes the
bridge contract, just as the trusted native runtime establishes its own ABI.

| SFIR type | Python value and transport |
| --- | --- |
| I32 | `int` in signed 32-bit range; `bool` is rejected. |
| I64 | `int` in signed 64-bit range, without a floating conversion. |
| F32 | `float`, rounded once to binary32; finite overflow is rejected. |
| F64 | `float`, with binary64 bits transported directly. |
| Bool | `bool`, encoded as canonical 0 or 1. |
| Char | A one-character `str` containing one Unicode scalar, excluding surrogates. |
| Unit result | `None`; the fixed result word must be zero. |

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
acknowledges successful initialization. Failure raises `InitializationError`,
returns no instance, and preserves external effects already performed. Ordinary
native terminal cleanup still closes Rust-owned resources on a guest trap.

[`native-worker.c`](../src/snail-sfir/native-worker.c) builds as two executables:
a supervisor with no guest/provider linkage, and a guest worker. Before executing
the guest image, the supervisor establishes an owned process group. Thus C
provider constructors execute inside that ownership too. The supervisor becomes
a Linux subreaper, observes host death through `PR_SET_PDEATHSIG`, and kills and
reaps surviving descendants. A descendant ignoring SIGTERM receives SIGKILL.
Providers intentionally escaping the process group are unsupported.

Commands and replies travel through dedicated inherited pipes; program stdout
and stderr go to regular log files and cannot fill an undrained output pipe.
The compiler-created bridge fixes the request arity; there is one outstanding
call at a time. I64 and IEEE values use little-endian binary words, not textual
numbers. Scalar words are never treated as GC roots. The compiled exported
function publishes its managed roots across collecting calls as usual.

`instantiate(linked, timeout=30, environment=None)` supports a positive finite
startup deadline. The same timeout bounds each later request and response
together. Timeout, trap, worker exit, interrupted call or invalid response closes
the instance; a later call cannot consume an old response or restart execution.
This differs from the Wasm adapter, which can retain a successfully initialized
instance after an invocation trap. Calls and close reject concurrent use of the
same instance. Distinct instances can run concurrently.

`close_instance` is idempotent. It requests ordinary resource cleanup, waits up
to two seconds, then requests supervisor termination; the supervisor allows a
short grace period before killing the guest group. Forced termination and host
loss guarantee process ownership cleanup under ordinary Linux scheduling, but
cannot guarantee application-level flushing or rollback. A task stuck in an
uninterruptible kernel operation can delay reaping. Dropping the last instance
handle uses the same cleanup operation; explicit close makes its timing clear.

## Verification

`scripts/test-sfir-native-loading` compiles real Entry artifacts and executes
native machine code. It covers independent mutable state, aliases, captured
references with collection at every allocation, all scalar types, incorrect
provider declarations, descriptor forgery, altered metadata, Rust scalar calls,
Rust resource cleanup, failed initialization, invocation traps, interrupted
startup/calls, publication failure, concurrent calls/close, real timeouts,
provider constructors, TERM-ignoring descendants and abrupt host death.
It also records mandatory Binaryen invocations and compares the native and Wasm
routes' optimized module bytes exactly. Every attempt retains build commands and
per-instance logs, including failures.
