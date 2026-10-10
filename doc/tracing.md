# Tracing operations

Timing is always enabled. Each participating process writes a separate Chromium
trace JSON file under `build/traces/`, relative to its working directory.
`SNAIL_TRACE_DIR` selects another directory. The CLI resolves that path before
launching its children, so compiler, Cargo build script, and executable use the
same destination. Files remain after temporary build projects are removed.
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

The default spans cover source reading, parsing, expansion, HIR lowering, LLVM
writing, Cargo, LLVM optimization/code generation, execution, and collection.
Imported sources appear within expansion. Use a viewer's inclusive/exclusive
durations to separate their costs. There are no per-instruction or per-primitive
spans. `--runtime-stats` reports elapsed/GC time in seconds alongside object counters;
`--timing` has been removed.

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

## Rust scopes and WASI

```rust
fn operation() {
    let _trace = snail_trace::span("module.operation");
    // The guard closes the span on return or panic unwinding.
}
```

`trace/src/lib.rs` owns destination selection, exclusive file creation, JSON
escaping, monotonic clocks, thread lanes, and serialized writes. Keep guards on
the creating thread. `Span::elapsed()` also supplies the existing runtime and
GC statistics without separate profiling clocks. Explicit process exit/abort
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
| `expand.sld` | `syntax-list->hir-library` | Syntax list → unnamed HIR library |
| `expand.sld` | `syntax->hir-library` | Library syntax → resolved HIR library |
| `lower.sld` | `hir-library->mir-library` | HIR library graph → MIR library graph |
| `mir.sld` | `write-mir-library` | MIR libraries → readable dump on a port |
| `llvm.sld` | `write-mir-library-as-llvm` | MIR library graph → LLVM text on a port |
| `compiler.sld` | `source-file->llvm-file` | Source filename → LLVM output file |

The compiler's private `mir-library->llvm-file` and `mir-library->dump-file`
helpers name their output formats explicitly. No generic `write-program`
callback obscures which representation a writer consumes.
