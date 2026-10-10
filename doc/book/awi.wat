;; AWI extension ABI: the Rust side of the Scheme/runtime boundary.
;; These scalar signatures exist in the Wasm and native CLI runtimes. The native
;; Rust build uses C adapters exported by the translated Scheme module; roots
;; address the same GC-visible table. Helper-only Rust tests still use stubs.
;; Wasm names are unversioned (informally AWI v0). Native exports use the same
;; unmangled names and extern "C", preserving these types.
;; repr(C) only governs exposed record layout, not function calling conventions.
;;
;; Every root parameter is borrowed except release's consumed root. A returned
;; root owns a distinct slot; cloning retains and dropping releases. Root handles
;; are instance-local u32 table indices, not pointers, remote IDs, or offsets.
;; A released index can be reused. Keep all live values rooted across allocation
;; and callbacks. Invalid raw handles/types/indices may trap; discard that instance.
;; Rust callbacks are synchronous and must not capture/suspend across Rust frames.
;; The current native CLI owns one instance per process. Hosting multiple
;; instances will require explicit context selection and restoration.
;;
;; Scheme-callable exports borrow one argument-vector root and return an owned
;; result root. Comments describe the Scheme values inside that vector. Current
;; command errors terminate with status 1; service/browser failure containment
;; needs its own implementation. Do not expose process exit as browser shutdown.
;; OS files/stdio/process arguments are native platform facilities, not automatic
;; browser capabilities. Demonstration Rust exports and OS imports are omitted.
;;
;; kind discriminants: 0 unspecified, 1 boolean, 2 nil, 3 EOF, 4 integer,
;; 5 real, 6 character, 7 pair, 8 vector, 9 string, 10 symbol, 11 bytevector,
;; 12 procedure, 13 record/record type, 14 extension, 15 multiple values,
;; 16 uninitialized. These are AWI discriminants, not private object tags.
;;
;; This file declares the callable interface. All bodies are documentation stubs.
(module
  ;; ---- Imports from compiled Scheme support ----

  ;; Retains the same value in a new owned root slot. The input remains
  ;; borrowed.
  (import "snail.awi" "retain" (func (param $root i32) (result i32)))

  ;; Consumes one owned root and releases its slot. Do not release a borrowed
  ;; handle or use a released handle again.
  (import "snail.awi" "release" (func (param $root i32)))

  ;; Returns the scalar AWI Kind discriminant, not an object address or an
  ;; internal object tag. The discriminants are listed above.
  (import "snail.awi" "kind" (func (param $root i32) (result i32)))

  ;; Returns 1 for reference identity and 0 otherwise. This is not structural
  ;; equality.
  (import "snail.awi" "same" (func (param $a i32) (param $b i32) (result i32)))

  ;; Invokes a Scheme procedure synchronously with a borrowed argument-vector
  ;; root; returns an owned result root. It may allocate and reenter Rust. Do
  ;; not hold a reentrant lock or host borrow. Suspension across this boundary
  ;; is unsupported.
  (import "snail.awi" "call" (func (param $procedure i32) (param $arguments i32) (result i32)))

  ;; Constructs an exact signed 64-bit integer and returns its owned root.
  (import "snail.awi" "integer" (func (param $value i64) (result i32)))

  ;; Constructs an inexact f64 value and returns its owned root.
  (import "snail.awi" "real" (func (param $value f64) (result i32)))

  ;; Returns an owned atom root. Tags 0–4 mean false, true, empty list,
  ;; unspecified, and EOF. Characters use Unicode scalar value + 256. Other
  ;; tags are reserved for runtime use.
  (import "snail.awi" "atom" (func (param $tag i32) (result i32)))

  ;; Constructs a pair from two borrowed roots and returns its owned root. The
  ;; pair keeps its children reachable after those input roots are released.
  (import "snail.awi" "pair" (func (param $car i32) (param $cdr i32) (result i32)))

  ;; Returns an owned vector root with the given unsigned length, initially
  ;; filled with unspecified values.
  (import "snail.awi" "vector_new" (func (param $length i32) (result i32)))

  ;; Stores a borrowed value into a vector at an in-range unsigned index.
  ;; Retaining the vector retains that child; no root ownership is transferred.
  (import "snail.awi" "vector_set" (func (param $root i32) (param $index i32) (param $value i32)))

  ;; Returns an owned string root with the given Unicode-scalar length,
  ;; initially filled with NUL characters.
  (import "snail.awi" "string_new" (func (param $length i32) (result i32)))

  ;; Writes a Unicode scalar value at an in-range string index. The checked
  ;; caller must supply a valid scalar, not a UTF-8 byte or surrogate.
  (import "snail.awi" "string_set" (func (param $root i32) (param $index i32) (param $value i32)))

  ;; Creates the single owning Scheme wrapper for a resource and registers
  ;; finalization. Returns its owned root. To share it, retain the wrapper;
  ;; creating a second wrapper for one resource can cause premature cleanup.
  ;; The support code currently calls snail.host/register-finalizer (eqref
  ;; object, i32 kind, i32 id) -> (). Its held cleanup data must not strongly
  ;; retain the wrapper; explicit close remains necessary.
  (import "snail.awi" "extension" (func (param $kind i32) (param $id i32) (result i32)))

  ;; Extracts an exact integer as signed i64. It does not consume the root.
  (import "snail.awi" "as_integer" (func (param $root i32) (result i64)))

  ;; Extracts a numeric value as f64 using the runtime numeric conversion. It
  ;; does not consume the root.
  (import "snail.awi" "as_real" (func (param $root i32) (result f64)))

  ;; Extracts an atom tag. Character tags must be decoded by subtracting 256
  ;; and validating the resulting Unicode scalar.
  (import "snail.awi" "atom_value" (func (param $root i32) (result i32)))

  ;; Returns the unsigned length of a vector, multiple-values container,
  ;; string, symbol, or bytevector. Text lengths count Unicode scalars.
  (import "snail.awi" "length" (func (param $root i32) (result i32)))

  ;; Returns a new owned root for a vector or multiple-values element at an
  ;; in-range unsigned index.
  (import "snail.awi" "at" (func (param $root i32) (param $index i32) (result i32)))

  ;; Returns the Unicode scalar at a string/symbol index, as a number rather
  ;; than a character root.
  (import "snail.awi" "char_at" (func (param $root i32) (param $index i32) (result i32)))

  ;; Allocate a zero-filled Scheme bytevector and return its owned root.
  (import "snail.awi" "bytes_new" (func (param $length i32) (result i32)))

  ;; Set one element of a bytevector retained by root. Caller checks the index
  ;; and that value is in 0..255. No Scheme callback or allocation occurs.
  (import "snail.awi" "byte_set" (func (param $root i32) (param $index i32) (param $value i32)))

  ;; Returns a bytevector element as an unsigned scalar in 0–255.
  (import "snail.awi" "byte_at" (func (param $root i32) (param $index i32) (result i32)))

  ;; Returns a new owned root for the first component of a pair.
  (import "snail.awi" "car" (func (param $root i32) (result i32)))

  ;; Returns a new owned root for the second component of a pair.
  (import "snail.awi" "cdr" (func (param $root i32) (result i32)))

  ;; Returns the resource-kind scalar from an extension wrapper. Kind 1
  ;; currently means a port.
  (import "snail.awi" "extension_kind" (func (param $root i32) (result i32)))

  ;; Returns the resource ID in that kind and instance. This ID is not an AWI
  ;; root and cannot identify a resource in another actor.
  (import "snail.awi" "extension_id" (func (param $root i32) (result i32)))

  ;; ---- Scheme-callable runtime exports ----

  ;; Takes a string and optional radix (2, 8, 10, or 16). Returns an exact i64,
  ;; a decimal inexact value, or false for unrecognized text. Exact overflow is
  ;; an error.
  (func (export "snail:string->number") (param $arguments i32) (result i32) unreachable)

  ;; Takes a number and optional radix. Returns text; inexact values require
  ;; decimal radix.
  (func (export "snail:number->string") (param $arguments i32) (result i32) unreachable)

  ;; Compares two or more characters using Rust Unicode lowercase iterators;
  ;; returns a boolean. This describes the current implementation, not a claim
  ;; of full Unicode case folding.
  (func (export "snail:char-ci=?") (param $arguments i32) (result i32) unreachable)

  ;; Tests one character with Rust Unicode alphabetic classification; returns a
  ;; boolean.
  (func (export "snail:char-alphabetic?") (param $arguments i32) (result i32) unreachable)

  ;; Tests one character with Rust Unicode numeric classification; returns a
  ;; boolean.
  (func (export "snail:char-numeric?") (param $arguments i32) (result i32) unreachable)

  ;; Tests one character with Rust Unicode whitespace classification; returns a
  ;; boolean.
  (func (export "snail:char-whitespace?") (param $arguments i32) (result i32) unreachable)

  ;; Formats one or more values as a diagnostic and terminates the command with
  ;; status 1. No result root is returned.
  (func (export "snail:error") (param $arguments i32) (result i32) unreachable)

  ;; Takes a path string and returns an owned port root. The current
  ;; implementation reads the complete file as UTF-8 into Rust-owned character
  ;; storage.
  (func (export "snail:open-input-file") (param $arguments i32) (result i32) unreachable)

  ;; Takes a path string, creates or truncates the file, and returns an owned
  ;; output-port root. Explicit close flushes and releases the file.
  (func (export "snail:open-output-file") (param $arguments i32) (result i32) unreachable)

  ;; Takes a path string and returns a boolean. Metadata/access errors are
  ;; failures rather than a false result.
  (func (export "snail:file-exists?") (param $arguments i32) (result i32) unreachable)

  ;; Closes one port promptly and returns an unspecified-value root. Closing an
  ;; already closed port is harmless; an output-string buffer remains readable
  ;; until finalization.
  (func (export "snail:close-port") (param $arguments i32) (result i32) unreachable)

  ;; Takes an optional input port, defaulting to the current input port.
  ;; Returns a character or EOF; stdin may block.
  (func (export "snail:read-char") (param $arguments i32) (result i32) unreachable)

  ;; Takes a nonnegative character count and optional input port. Returns up to
  ;; that many characters, or EOF if a nonzero request reads none; a zero
  ;; request returns an empty string.
  (func (export "snail:read-string") (param $arguments i32) (result i32) unreachable)

  ;; [path] -> owned binary-input-port. Open the native/Wasm runtime's file
  ;; resource without decoding UTF-8. Explicit close releases it promptly.
  (func (export "snail:open-binary-input-file") (param $arguments i32) (result i32) unreachable)

  ;; [count, optional binary-input-port] -> bytevector or EOF. Read at most count
  ;; bytes; count zero returns an empty bytevector even at EOF. The initial
  ;; current stdin port is textual; pass an explicitly opened binary port.
  (func (export "snail:read-bytevector") (param $arguments i32) (result i32) unreachable)

  ;; [bytevector, optional start, optional end] -> fresh bytevector copy. Bounds
  ;; are byte indices, start-inclusive/end-exclusive; default to the whole input.
  (func (export "snail:bytevector-copy") (param $arguments i32) (result i32) unreachable)

  ;; [bytevector ...] -> fresh bytevector containing the inputs in order.
  ;; No arguments produces an empty bytevector. Input storage is never shared.
  (func (export "snail:bytevector-append") (param $arguments i32) (result i32) unreachable)

  ;; [string, optional start, optional end] -> fresh UTF-8 bytevector. Bounds
  ;; count Unicode scalars in the string, not encoded bytes.
  (func (export "snail:string->utf8") (param $arguments i32) (result i32) unreachable)

  ;; [bytevector, optional start, optional end] -> decoded string. Bounds count
  ;; bytes; invalid UTF-8 is a terminal runtime error, never replacement text.
  (func (export "snail:utf8->string") (param $arguments i32) (result i32) unreachable)

  ;; Takes no arguments and returns a new output-string port. Its buffer
  ;; belongs to the Rust runtime.
  (func (export "snail:open-output-string") (param $arguments i32) (result i32) unreachable)

  ;; Takes an output-string port and returns a Scheme string copy of its
  ;; captured text, including after explicit close.
  (func (export "snail:get-output-string") (param $arguments i32) (result i32) unreachable)

  ;; Takes a value and optional output port, defaulting to the current output
  ;; port. Emits display text and returns an unspecified-value root.
  (func (export "snail:display") (param $arguments i32) (result i32) unreachable)

  ;; Takes a value and optional output port. Emits its written representation
  ;; and returns an unspecified-value root. This formatter is not the planned
  ;; schema- derived actor codec.
  (func (export "snail:write") (param $arguments i32) (result i32) unreachable)

  ;; Takes an optional output port, emits a newline, and returns an
  ;; unspecified- value root.
  (func (export "snail:newline") (param $arguments i32) (result i32) unreachable)

  ;; Takes no arguments and returns a new owned root for the current input
  ;; port.
  (func (export "snail:%current-input-port") (param $arguments i32) (result i32) unreachable)

  ;; Takes no arguments and returns a new owned root for the current output
  ;; port.
  (func (export "snail:%current-output-port") (param $arguments i32) (result i32) unreachable)

  ;; Takes no arguments and returns a new owned root for the current error
  ;; port.
  (func (export "snail:%current-error-port") (param $arguments i32) (result i32) unreachable)

  ;; Takes an open input port, retains it as current, and returns an
  ;; unspecified- value root.
  (func (export "snail:%set-current-input-port!") (param $arguments i32) (result i32) unreachable)

  ;; Takes an open output port, retains it as current, and returns an
  ;; unspecified-value root.
  (func (export "snail:%set-current-output-port!") (param $arguments i32) (result i32) unreachable)

  ;; Takes an open output port, retains it as the current error port, and
  ;; returns an unspecified-value root.
  (func (export "snail:%set-current-error-port!") (param $arguments i32) (result i32) unreachable)

  ;; Takes no arguments and returns an owned list of argument strings. The
  ;; command platform defines the first argument.
  (func (export "snail:command-line") (param $arguments i32) (result i32) unreachable)

  ;; Takes an environment-variable name. Returns its UTF-8 string value or false
  ;; when absent; a non-UTF-8 native value is a runtime error.
  (func (export "snail:get-environment-variable") (param $arguments i32) (result i32) unreachable)

  ;; Takes an optional status (default 0); true maps to 0 and false to 1, or a
  ;; signed i32 integer is accepted. Terminates the command without returning a
  ;; root.
  (func (export "snail:exit") (param $arguments i32) (result i32) unreachable)

  ;; Takes no arguments and returns elapsed monotonic nanoseconds since this
  ;; runtime host was initialized, checked to fit an exact i64.
  (func (export "snail:current-jiffy") (param $arguments i32) (result i32) unreachable)

  ;; Takes no arguments and returns the exact integer 1,000,000,000.
  (func (export "snail:jiffies-per-second") (param $arguments i32) (result i32) unreachable)

  ;; Takes a haystack, pattern, and optional starting scalar index. Returns the
  ;; first match index or false. Copies the pattern and reads the Scheme
  ;; haystack by Unicode scalar index.
  (func (export "snail:string-contains") (param $arguments i32) (result i32) unreachable)

  ;; Takes a span-name string, starts a trace span, and returns an unspecified-
  ;; value root. Trace-file failure is nonfatal.
  (func (export "snail:%trace-begin") (param $arguments i32) (result i32) unreachable)

  ;; Takes no arguments, ends the current trace span, and returns an
  ;; unspecified- value root.
  (func (export "snail:%trace-end") (param $arguments i32) (result i32) unreachable)

  ;; ---- Initialization, diagnostics, and cleanup ----

  ;; Initializes the Rust runtime before any Scheme execution. The Wasm build
  ;; calls its reactor initializer once. Native Rust uses its normal startup
  ;; and lazy per-thread resources; this symbol is specific to the Wasm reactor.
  (func (export "_initialize") unreachable)

  ;; Reports a compiler/runtime failure and terminates with status 1. The
  ;; result type is nominal; it never returns. Codes 1–9 denote numeric type,
  ;; exact overflow, range, arity, value count, uninitialized binding,
  ;; unsupported call/cc, value type, and division-by-zero failures. Other
  ;; codes report a generic runtime error.
  (func (export "snail:fail") (param $code i32) (result i32) unreachable)

  ;; Releases a resource payload. Kind 1 is a port; IDs are never reused within
  ;; its instance. Repeated cleanup and unknown IDs/kinds are harmless, and
  ;; cleanup errors are ignored. The collector hook must not retain the watched
  ;; Scheme wrapper.
  (func (export "snail:drop-resource") (param $kind i32) (param $id i32) unreachable)

)
