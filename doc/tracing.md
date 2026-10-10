# Tracing operations

Compiler and runtime timing is always enabled. Each participating process writes a separate Chromium
trace JSON file under `build/traces/`, relative to its working directory.
`SNAIL_TRACE_DIR` selects another directory. Build scripts and their children normally share a working directory; use an
absolute override when a script changes directories. Files remain after temporary build projects are removed.
Standalone Cargo build scripts and tests can run from their crate directories;
set an absolute override to collect those files in one place.

Open a file in `chrome://tracing` or [Perfetto's trace viewer](https://ui.perfetto.dev).
The [Chromium JSON format](https://perfetto.dev/docs/getting-started/other-formats)
uses `B`/`E` events with timestamps in microseconds. Rust uses a monotonic clock;
Chibi uses its host microsecond wall clock, so clock adjustments can affect
Chibi intervals. This avoids its standard jiffy clock's millisecond rounding. Each file has its
own clock origin; files are not automatically merged or aligned across processes.
Rust assigns separate thread lanes. The Chibi adapter supports the compiler's
single Scheme execution thread.

The default spans cover source reading, parsing, expansion, WAT emission, Cargo,
Wasm assembly/linking/optimization, and execution. Imported sources appear
within expansion. Use a viewer's inclusive/exclusive durations to separate
costs. There are no per-instruction or per-primitive spans. WasmGC does not
expose portable collector timings; the old `--runtime-stats` and `--timing`
flags are retired.

## Scheme procedures

Import `(snail-scheme trace)` from any module:

```scheme
(define-traced (reader->syntax-list reader)
  (let ((result (s-file reader)))
    (if (parse-result-err? result)
        (error "cannot parse source" (reader-loc (parse-result-input result))))
    (parse-result-value result)))

(call-with-trace "load configuration" (lambda () (load-configuration)))
```

`define-traced` derives its label from the procedure name. It supports fixed,
rest-only, and dotted argument lists and preserves zero, one, or multiple return
values. Trace complete operations; wrapping a recursive loop keeps the wrapper
active until return and defeats that procedure's tail-call behavior.

Chibi uses `dynamic-wind`: errors and continuation transfers close the current
segment, and continuation reentry opens another. The generated runtime does not
yet implement `dynamic-wind`. Its adapter supports normal returns and terminal
errors, but continuation escape followed by continued execution can misnest
trace spans. Do not decorate such procedures until unwinding support lands.
An unfinished begin event after an abort or explicit exit remains inspectable.

The adapter lives in `src/snail-scheme/trace.sld`. Its Chibi-only branch owns the
host file/clock operations; compiled programs call `%trace-begin`/`%trace-end`
through the shared Rust recorder. These primitives allocate no Scheme objects
and do not introduce GC safepoints.

## Scheme trace files

Import `(snail-scheme chromium-trace)` for an explicit destination. `trace` takes
a string and a procedure and returns a procedure accepting the same arguments.
It preserves zero, one, or multiple return values. The returned procedure reads
the current file destination at invocation and raises an error before calling
the original procedure when invoked outside `with-trace-to`.

```scheme
(import (scheme base) (snail-scheme chromium-trace))

(define timed-add (trace "add" (lambda (x y) (+ x y))))

(with-trace-to "operations.json"
  (lambda () (timed-add 20 22)))
```

`with-trace-to` opens the named file for output, replacing existing contents,
then initializes the JSON array, runs the thunk, finalizes the array, and closes
the file on normal return. It preserves the thunk's return values. Nested
scopes on different files restore the outer destination; each span records to
the file selected when it was invoked.

Initialization always writes a thread-name metadata event, even if the thunk
runs no traced procedures. This supplies the first array element, so every
timed span simply writes a leading comma. There is no session record, event
counter, or lifecycle flag; the recording port is private to the library.

Timed events use the Chromium complete-duration phase `X`
with integer microsecond `ts` and `dur` fields, supported by
[Perfetto](https://perfetto.dev/docs/getting-started/other-formats). Names escape
JSON control characters, quotes, and backslashes. Each document uses one logical
process/thread lane (`pid` and `tid` are both `1`); concurrent writes to the same
port are unsupported.

Timing uses `(scheme time)`: Chibi's jiffy clock has millisecond resolution and
uses wall time; compiled programs use a monotonic nanosecond clock. Timestamps
retain that clock's origin and durations round down to microseconds. Backward
wall-clock adjustments clamp duration to zero. Tracing keeps each wrapper active
until return, so decorating recursive loops affects their tail-call behavior.

The same implementation runs on Chibi and compiled Snail-Scheme. A span is
written only after the wrapped procedure returns normally. An invocation that
never returns emits no event; already completed child spans remain. On Chibi,
an error caught inside the file scope or an escape back to that scope can omit
the unfinished span and still produce valid JSON when the thunk returns. If
the whole file scope is abandoned, finalization and explicit close do not run,
so the file may remain incomplete. Continuation reentry is unsupported. Output
errors propagate.

`make test` checks host values, JSON escaping, nesting, file closure, and
omission of failed or escaped calls. `scripts/test-chromium-trace` parses files
recorded by Chibi and linked Wasm and checks missing destinations, file-opening
failures, and omission of a span on terminal error. Add `--target both` to run
the same linked module through the native executor.

## Rust scopes and WASI

```rust
fn operation() {
    let _trace = snail_runtime::trace::span("module.operation");
    // The guard closes the span on return or panic unwinding.
}
```

`src/trace.rs` owns destination selection, exclusive file creation, JSON
escaping, monotonic clocks, thread lanes, and serialized writes. Keep guards on
the creating thread. `Span::elapsed()` measures a Rust scope without separate profiling clocks. Explicit process exit/abort
bypasses destructors; the runner returns from its traced scope before exiting.

The WASI launcher preopens the host trace directory at `/snail-traces` and sets
the guest override accordingly, including when the directory is outside cwd. If preopening fails, the launcher
forwards `SNAIL_TRACE_OPEN_ERROR` to the recorder; it reports the failure once
instead of silently falling back through WASI's cwd preopen.
Other WASI hosts must provide a writable preopen and a matching guest path.
WASI preview 1 lacks process IDs; exclusive filenames distinguish executions.

Every successfully written event leaves a closed JSON array on disk. Recording
requires no shutdown flush. I/O failure disables that process's recorder with
one stderr diagnostic and preserves the program's outcome. Abrupt interruption
in the middle of a write can still leave a partial file.

## Pass entry points

| Module | Entry point | Representation |
| --- | --- | --- |
| `reader.sld` | `file->reader` | Filename → character reader |
| `syntax-parser.sld` | `reader->syntax-list` | Reader → located syntax list |
| `expand.sld` | `syntax-list->ir-library` | Syntax list → unnamed IR library |
| `expand.sld` | `syntax->ir-library` | Library syntax → resolved IR library |
| `wasm.sld` | `write-ir-library-as-wasm` | IR library graph → WAT on a port |
| `compiler.sld` | `source-file->wat-file` | Source filename → WAT output file |
