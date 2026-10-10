# Native

**Proposed platform; native Rust linkage is not implemented.** Compile Scheme
through WasmGC to LLVM/native objects, compile the Rust runtime natively, and link
them using the target C ABI. Native applications should run without Node. The
same runtime procedures should work in both builds, with platform-specific
operations underneath their common signatures.

Today `src/awi.rs` substitutes panic stubs on native targets so helper tests can
link. Rust's Wasm export names are not yet a set of native unmangled exports.
Passing native unit tests therefore does not demonstrate this platform.

## Module interface

The following is the **Rust runtime's callable surface**, expressed as a Wasm
module before linking. Imports from `snail.awi` are scalar accessors/callbacks
implemented by compiled Scheme's support code. Exports provide Scheme-callable
runtime services, resolved under `snail.rust` during Wasm linking. Native linking
must preserve these signatures and their ownership rules.

These signatures already exist in the Wasm runtime. Their **native realization**
is the proposal. The standard library's OS imports, demonstration-only Rust
callbacks, private GC representations, and executable startup shim are outside
this callable-surface module. The `unreachable` bodies are documentation stubs.

```wat
{{#include native.wat}}
```

## Symbol conventions

In the reference below, `root`, `arguments`, `procedure`, and child values are
**instance-local root handles**, never pointers. Every handle parameter is
borrowed unless explicitly consumed by `release`. Every result described as a
root owns a distinct live slot, even when it refers to the same Scheme object.
Allocation may collect Scheme objects; all needed values must remain rooted.
Invalid raw handles, types, or indices can trap; the checked Rust SDK validates
its safe operations before making raw calls.

Scheme-callable exports all have `(i32 arguments) -> i32`: borrow the rooted
argument vector and return an owned result root. The bullets describe the Scheme
values carried inside that vector. Diagnostic failures currently terminate with
status 1, including wrong arity/types and IO failures; they are not recoverable
Scheme exceptions. Exit/failure functions have nominal Wasm results but never
return. Calls are synchronous, including blocking IO.

## Symbols: imports from `snail.awi`

- <a id="awi-retain"></a>**`snail.awi/retain` — `(i32 root) -> i32`.**
  Retains the same value in a new owned root slot. The input remains borrowed.

- <a id="awi-release"></a>**`snail.awi/release` — `(i32 root) -> ()`.**
  Consumes one owned root and releases its slot. Do not release a borrowed
  handle or use a released handle again.

- <a id="awi-kind"></a>**`snail.awi/kind` — `(i32 root) -> i32`.**
  Returns the scalar AWI Kind discriminant, not an object address or an
  internal object tag. The discriminant table is below.

- <a id="awi-same"></a>**`snail.awi/same` — `(i32 a, i32 b) -> i32`.**
  Returns 1 for reference identity and 0 otherwise. This is not structural
  equality.

- <a id="awi-call"></a>**`snail.awi/call` — `(i32 procedure, i32 arguments) -> i32`.**
  Invokes a Scheme procedure synchronously with a borrowed argument-vector
  root; returns an owned result root. It may allocate and reenter Rust. Do not
  hold a reentrant lock or host borrow. Suspension across this boundary is
  unsupported.

- <a id="awi-integer"></a>**`snail.awi/integer` — `(i64 value) -> i32`.**
  Constructs an exact signed 64-bit integer and returns its owned root.

- <a id="awi-real"></a>**`snail.awi/real` — `(f64 value) -> i32`.**
  Constructs an inexact f64 value and returns its owned root.

- <a id="awi-atom"></a>**`snail.awi/atom` — `(i32 tag) -> i32`.**
  Returns an owned atom root. Tags 0–4 mean false, true, empty list,
  unspecified, and EOF. Characters use Unicode scalar value + 256. Other tags
  are reserved for runtime use.

- <a id="awi-pair"></a>**`snail.awi/pair` — `(i32 car, i32 cdr) -> i32`.**
  Constructs a pair from two borrowed roots and returns its owned root. The
  pair keeps its children reachable after those input roots are released.

- <a id="awi-vector-new"></a>**`snail.awi/vector_new` — `(i32 length) -> i32`.**
  Returns an owned vector root with the given unsigned length, initially
  filled with unspecified values.

- <a id="awi-vector-set"></a>**`snail.awi/vector_set` — `(i32 root, i32 index, i32 value) -> ()`.**
  Stores a borrowed value into a vector at an in-range unsigned index.
  Retaining the vector retains that child; no root ownership is transferred.

- <a id="awi-string-new"></a>**`snail.awi/string_new` — `(i32 length) -> i32`.**
  Returns an owned string root with the given Unicode-scalar length, initially
  filled with NUL characters.

- <a id="awi-string-set"></a>**`snail.awi/string_set` — `(i32 root, i32 index, i32 value) -> ()`.**
  Writes a Unicode scalar value at an in-range string index. The checked
  caller must supply a valid scalar, not a UTF-8 byte or surrogate.

- <a id="awi-extension"></a>**`snail.awi/extension` — `(i32 kind, i32 id) -> i32`.**
  Creates the single owning Scheme wrapper for a resource and registers
  finalization. Returns its owned root. To share it, retain the wrapper;
  creating a second wrapper for one resource can cause premature cleanup.

- <a id="awi-as-integer"></a>**`snail.awi/as_integer` — `(i32 root) -> i64`.**
  Extracts an exact integer as signed i64. It does not consume the root.

- <a id="awi-as-real"></a>**`snail.awi/as_real` — `(i32 root) -> f64`.**
  Extracts a numeric value as f64 using the runtime numeric conversion. It
  does not consume the root.

- <a id="awi-atom-value"></a>**`snail.awi/atom_value` — `(i32 root) -> i32`.**
  Extracts an atom tag. Character tags must be decoded by subtracting 256 and
  validating the resulting Unicode scalar.

- <a id="awi-length"></a>**`snail.awi/length` — `(i32 root) -> i32`.**
  Returns the unsigned length of a vector, multiple-values container, string,
  symbol, or bytevector. Text lengths count Unicode scalars.

- <a id="awi-at"></a>**`snail.awi/at` — `(i32 root, i32 index) -> i32`.**
  Returns a new owned root for a vector or multiple-values element at an
  in-range unsigned index.

- <a id="awi-char-at"></a>**`snail.awi/char_at` — `(i32 root, i32 index) -> i32`.**
  Returns the Unicode scalar at a string/symbol index, as a number rather than
  a character root.

- <a id="awi-byte-at"></a>**`snail.awi/byte_at` — `(i32 root, i32 index) -> i32`.**
  Returns a bytevector element as an unsigned scalar in 0–255.

- <a id="awi-car"></a>**`snail.awi/car` — `(i32 root) -> i32`.**
  Returns a new owned root for the first component of a pair.

- <a id="awi-cdr"></a>**`snail.awi/cdr` — `(i32 root) -> i32`.**
  Returns a new owned root for the second component of a pair.

- <a id="awi-extension-kind"></a>**`snail.awi/extension_kind` — `(i32 root) -> i32`.**
  Returns the resource-kind scalar from an extension wrapper. Kind 1 currently
  means a port.

- <a id="awi-extension-id"></a>**`snail.awi/extension_id` — `(i32 root) -> i32`.**
  Returns the resource ID in that kind and instance. This ID is not an AWI
  root and cannot identify a resource in another actor.

`kind` discriminants are stable within AWI v0:

| Value | Kind | Value | Kind |
| --- | --- | --- | --- |
| 0 | Unspecified | 9 | String |
| 1 | Boolean | 10 | Symbol |
| 2 | Nil | 11 | Bytevector |
| 3 | EOF | 12 | Procedure |
| 4 | Integer | 13 | Record / record type |
| 5 | Real | 14 | Extension |
| 6 | Character | 15 | Multiple values |
| 7 | Pair | 16 | Uninitialized |
| 8 | Vector | | |

## Symbols: runtime exports

These are resolved in module `snail.rust`. Every `i32` result below is an owned
root, not an unboxed integer/boolean, except the non-returning failure paths.

- <a id="runtime-string-to-number"></a>**`snail:string->number` — `(i32 arguments) -> i32`.**
  Takes a string and optional radix (2, 8, 10, or 16). Returns an exact i64, a
  decimal inexact value, or false for unrecognized text. Exact overflow is an
  error.

- <a id="runtime-number-to-string"></a>**`snail:number->string` — `(i32 arguments) -> i32`.**
  Takes a number and optional radix. Returns text; inexact values require
  decimal radix.

- <a id="runtime-char-ciequal-p"></a>**`snail:char-ci=?` — `(i32 arguments) -> i32`.**
  Compares two or more characters using Rust Unicode lowercase iterators;
  returns a boolean. This describes the current implementation, not a claim of
  full Unicode case folding.

- <a id="runtime-char-alphabetic-p"></a>**`snail:char-alphabetic?` — `(i32 arguments) -> i32`.**
  Tests one character with Rust Unicode alphabetic classification; returns a
  boolean.

- <a id="runtime-char-numeric-p"></a>**`snail:char-numeric?` — `(i32 arguments) -> i32`.**
  Tests one character with Rust Unicode numeric classification; returns a
  boolean.

- <a id="runtime-char-whitespace-p"></a>**`snail:char-whitespace?` — `(i32 arguments) -> i32`.**
  Tests one character with Rust Unicode whitespace classification; returns a
  boolean.

- <a id="runtime-error"></a>**`snail:error` — `(i32 arguments) -> i32`.**
  Formats one or more values as a diagnostic and terminates the command with
  status 1. No result root is returned.

- <a id="runtime-open-input-file"></a>**`snail:open-input-file` — `(i32 arguments) -> i32`.**
  Takes a path string and returns an owned port root. The current
  implementation reads the complete file as UTF-8 into Rust-owned character
  storage.

- <a id="runtime-open-output-file"></a>**`snail:open-output-file` — `(i32 arguments) -> i32`.**
  Takes a path string, creates or truncates the file, and returns an owned
  output-port root. Explicit close flushes and releases the file.

- <a id="runtime-file-exists-p"></a>**`snail:file-exists?` — `(i32 arguments) -> i32`.**
  Takes a path string and returns a boolean. Metadata/access errors are
  failures rather than a false result.

- <a id="runtime-close-port"></a>**`snail:close-port` — `(i32 arguments) -> i32`.**
  Closes one port promptly and returns an unspecified-value root. Closing an
  already closed port is harmless; an output-string buffer remains readable
  until finalization.

- <a id="runtime-read-char"></a>**`snail:read-char` — `(i32 arguments) -> i32`.**
  Takes an optional input port, defaulting to the current input port. Returns
  a character or EOF; stdin may block.

- <a id="runtime-read-string"></a>**`snail:read-string` — `(i32 arguments) -> i32`.**
  Takes a nonnegative character count and optional input port. Returns up to
  that many characters, or EOF if a nonzero request reads none; a zero request
  returns an empty string.

- <a id="runtime-open-output-string"></a>**`snail:open-output-string` — `(i32 arguments) -> i32`.**
  Takes no arguments and returns a new output-string port. Its buffer belongs
  to the Rust runtime.

- <a id="runtime-get-output-string"></a>**`snail:get-output-string` — `(i32 arguments) -> i32`.**
  Takes an output-string port and returns a Scheme string copy of its captured
  text, including after explicit close.

- <a id="runtime-display"></a>**`snail:display` — `(i32 arguments) -> i32`.**
  Takes a value and optional output port, defaulting to the current output
  port. Emits display text and returns an unspecified-value root.

- <a id="runtime-write"></a>**`snail:write` — `(i32 arguments) -> i32`.**
  Takes a value and optional output port. Emits its written representation and
  returns an unspecified-value root. This formatter is not the planned schema-
  derived actor codec.

- <a id="runtime-newline"></a>**`snail:newline` — `(i32 arguments) -> i32`.**
  Takes an optional output port, emits a newline, and returns an unspecified-
  value root.

- <a id="runtime-current-input-port"></a>**`snail:%current-input-port` — `(i32 arguments) -> i32`.**
  Takes no arguments and returns a new owned root for the current input port.

- <a id="runtime-current-output-port"></a>**`snail:%current-output-port` — `(i32 arguments) -> i32`.**
  Takes no arguments and returns a new owned root for the current output port.

- <a id="runtime-current-error-port"></a>**`snail:%current-error-port` — `(i32 arguments) -> i32`.**
  Takes no arguments and returns a new owned root for the current error port.

- <a id="runtime-set-current-input-port"></a>**`snail:%set-current-input-port!` — `(i32 arguments) -> i32`.**
  Takes an open input port, retains it as current, and returns an unspecified-
  value root.

- <a id="runtime-set-current-output-port"></a>**`snail:%set-current-output-port!` — `(i32 arguments) -> i32`.**
  Takes an open output port, retains it as current, and returns an
  unspecified-value root.

- <a id="runtime-set-current-error-port"></a>**`snail:%set-current-error-port!` — `(i32 arguments) -> i32`.**
  Takes an open output port, retains it as the current error port, and returns
  an unspecified-value root.

- <a id="runtime-command-line"></a>**`snail:command-line` — `(i32 arguments) -> i32`.**
  Takes no arguments and returns an owned list of argument strings. The
  command platform defines the first argument.

- <a id="runtime-exit"></a>**`snail:exit` — `(i32 arguments) -> i32`.**
  Takes an optional status (default 0); true maps to 0 and false to 1, or a
  signed i32 integer is accepted. Terminates the command without returning a
  root.

- <a id="runtime-current-jiffy"></a>**`snail:current-jiffy` — `(i32 arguments) -> i32`.**
  Takes no arguments and returns elapsed monotonic nanoseconds since this
  runtime host was initialized, checked to fit an exact i64.

- <a id="runtime-jiffies-per-second"></a>**`snail:jiffies-per-second` — `(i32 arguments) -> i32`.**
  Takes no arguments and returns the exact integer 1,000,000,000.

- <a id="runtime-string-contains"></a>**`snail:string-contains` — `(i32 arguments) -> i32`.**
  Takes a haystack, pattern, and optional starting scalar index. Returns the
  first match index or false. Copies the pattern and reads the Scheme haystack
  by Unicode scalar index.

- <a id="runtime-trace-begin"></a>**`snail:%trace-begin` — `(i32 arguments) -> i32`.**
  Takes a span-name string, starts a trace span, and returns an unspecified-
  value root. Trace-file failure is nonfatal.

- <a id="runtime-trace-end"></a>**`snail:%trace-end` — `(i32 arguments) -> i32`.**
  Takes no arguments, ends the current trace span, and returns an unspecified-
  value root.

## Symbols: initialization, diagnostics, and cleanup

- <a id="initialize"></a>**`_initialize` — `() -> ()`.**
  Initializes the Rust runtime before any Scheme execution. The Wasm build
  calls its reactor initializer once. The native entry shim must establish
  equivalent once-per-instance initialization; sharing code must not share
  actor state.

- <a id="fail"></a>**`snail:fail` — `(i32 code) -> i32`.**
  Reports a compiler/runtime failure and terminates with status 1. The result
  type is nominal; it never returns. Codes 1–9 denote numeric type, exact
  overflow, range, arity, value count, uninitialized binding, unsupported
  call/cc, value type, and division-by-zero failures. Other codes report a
  generic runtime error.

- <a id="drop-resource"></a>**`snail:drop-resource` — `(i32 kind, i32 id) -> ()`.**
  Releases a resource payload. Kind 1 is a port; IDs are never reused within
  its instance. Repeated cleanup and unknown IDs/kinds are harmless, and
  cleanup errors are ignored. The collector hook must not retain the watched
  Scheme wrapper.

## Native symbol mapping

Specify the native name alongside each runtime declaration; do not derive names
by stripping punctuation, which can cause collisions. The following names are
**illustrative proposed mappings**, not symbols exported by current native builds:

| Wasm symbol | Native declaration |
| --- | --- |
| `snail.rust/snail:write` | `uint32_t snail_runtime_v0_write(uint32_t arguments);` |
| `snail.awi/retain` | `uint32_t snail_awi_v0_retain(uint32_t root);` |
| `snail.awi/release` | `void snail_awi_v0_release(uint32_t root);` |
| `snail.awi/integer` | `uint32_t snail_awi_v0_integer(int64_t value);` |

One explicit declaration set should determine the Wasm names/types and the native
names/C signatures. Ordinary runtime function bodies should be shared; IO uses
Rust's native services or its Wasm platform support as appropriate. Native GC,
roots, and callbacks need real implementations behind the same scalar calls.
Rust uses `extern "C"` and an explicit unmangled export; `#[repr(C)]` is only
needed for exposed records, which this initial scalar ABI avoids.

## Lifecycle and instance context

The native entry shim creates an instance and establishes its runtime context,
initializes support, invokes the command, then tears down its resources. It
selects roots, globals, ports, callbacks, and other resources for that instance.
An explicit context parameter or a scoped call-entry context is still a design
choice; the first native implementation must settle it before hosting multiple
actors. Unscoped TLS is insufficient when instances share a thread.

The generated code and runtime must agree on root/collector semantics across
allocation and callbacks. Reference-valued Wasm instructions remain the compiler
or executor's responsibility. The host finalization hook requires a collector
adapter which never strongly retains the watched wrapper. Physical native
pointers can be wider than Scheme's proposed 32-bit addressing/handle model;
that does not authorize exposing them as Scheme offsets or root IDs.

Current command failures and exit terminate a command. A future service hosting
several actors must separately define failure containment and cleanup; installing
these exports alone does not provide it. General actor dispatch, async IO,
subprocess actors, suspension, and hot reload are later capabilities. No global
thread pool or `call/cc` scheduling behavior is implied by this ABI.

## Evidence required before calling this implemented

- Execute compiled Scheme linked against the native Rust runtime, with **no Node
  process**. Native compilation or pure helper tests alone do not count.
- Run equivalent argument, UTF-8 IO, exit-status, numeric, and clock cases on Wasm
  and native. Exercise actual allocation and Rust-to-Scheme callbacks.
- Interleave two instances on one thread and verify independent roots, globals,
  current ports, and cleanup. A callback must restore the correct context.
- Retain/release values across allocation, close resources explicitly, and exercise
  eventual finalization without a wrapper-retention cycle. Report traps honestly.
- Resolve every imported symbol with the declared target C calling convention;
  reject unsupported ABI versions/features before entry.

Implementation starting points are
[`src/awi.rs`](https://github.com/tsnl/snail-scheme/blob/main/src/awi.rs),
[`src/lib.rs`](https://github.com/tsnl/snail-scheme/blob/main/src/lib.rs), and
[`src/runtime/awi.wat`](https://github.com/tsnl/snail-scheme/blob/main/src/runtime/awi.wat).
The [ABI chapter](../abi.md) specifies the shared ownership and value mapping.
