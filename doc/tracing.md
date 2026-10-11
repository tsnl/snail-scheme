# Tracing operations

Compiler stages and Scheme programs use `(snail-scheme chromium-trace)`.
Executable scripts choose a filename and establish a file scope with
`with-chromium-trace-to`. Importing a compiler or build library creates no trace
files and performs no traced work.

The checked-in `build.scm` writes `<output>.trace.json` (by default,
`build/snail-scheme.trace.json`). The native interpreter owns
`<SCRIPT>.trace.json` for script compilation and execution. Benchmark and
example scripts name their own files beside their artifacts. Integration build
scripts write `<output>.trace.json`, and unit tests use temporary destinations.
Parent directories must exist before opening a trace. Opening replaces existing
contents; use distinct destinations for concurrent workflows.

Open a completed file in `chrome://tracing` or
[Perfetto's trace viewer](https://ui.perfetto.dev).

## Procedure decoration and file ownership

`chromium-trace` takes a string and a procedure and returns a procedure accepting
the same arguments. It preserves zero, one, or multiple return values. The
returned procedure reads the current file destination at invocation and raises
an error before calling the original procedure when invoked outside
`with-chromium-trace-to`.

```scheme
(import (scheme base) (snail-scheme chromium-trace))

(define timed-add (chromium-trace "add" (lambda (x y) (+ x y))))

(with-chromium-trace-to "operations.json"
  (lambda () (timed-add 20 22)))
```

`with-chromium-trace-to` opens the named file, initializes the JSON array, runs
the thunk, then finalizes and closes the file on normal return. It preserves
the thunk's return values. Nested scopes on different files restore the outer
destination; each span records to the file selected when it was invoked.

Initialization always writes a thread-name metadata event, even if the thunk
runs no decorated procedures. This supplies the first array element, so every
timed span simply writes a leading comma. There is no session record, event
counter, or lifecycle flag; the recording port is private to the library.

A workflow that returns an exit status must leave the file scope before exiting:

```scheme
(exit
 (with-chromium-trace-to "build.trace.json"
   (lambda ()
     (build-wasm "." "app.scm" "app.wasm")
     (run-wasm "." "app.wasm" '()))))
```

This assumes `(scheme process-context)` and `(snail-scheme build)` are imported.
Even a nonzero program status returns normally through `run-wasm`, allowing the
trace to be finalized before the script passes that status to `exit`.

## Events, clocks, and failures

Timed events use the Chromium complete-duration phase `X` with integer
microsecond `ts` and `dur` fields, supported by
[Perfetto](https://perfetto.dev/docs/getting-started/other-formats). Names escape
JSON control characters, quotes, and backslashes. Each document uses one logical
process/thread lane (`pid` and `tid` are both `1`); concurrent writes to the same
port are unsupported.

Timing uses `(scheme time)`: Chibi's jiffy clock has millisecond resolution and
uses wall time; compiled programs use a monotonic nanosecond clock. Timestamps
retain that clock's origin and durations round down to microseconds. Backward
wall-clock adjustments clamp duration to zero. Files are not automatically
aligned or merged across processes. Tracing keeps each wrapper active until
return, so decorating recursive loops affects their tail-call behavior.

The same implementation runs on Chibi and compiled Snail-Scheme. A span is
written only after the wrapped procedure returns normally. An invocation that
never returns emits no event; already completed child spans remain. On Chibi,
an error caught inside the file scope or an escape back to that scope can omit
the unfinished span and still produce valid JSON when the thunk returns. If
the whole file scope is abandoned, finalization and explicit close do not run,
so the file may remain incomplete. Continuation reentry is unsupported. Output
errors propagate.

Compiled programs use ordinary Scheme file and clock operations through the
Rust AWI runtime. The Wasm and native launchers expose their working directory
for file access; trace filenames must lie within the host's accessible paths.

## Compiler stages and checks

Spans cover source reading, parsing, expansion, WAT emission, Cargo, Wasm
assembly/linking/optimization, execution, and native translation. Imported
sources appear within expansion. Use a viewer's inclusive/exclusive durations
to separate costs. There are no per-instruction or per-primitive spans; WasmGC
does not expose portable collector timings.

| Module | Entry point | Representation |
| --- | --- | --- |
| `reader.sld` | `file->reader` | Filename → character reader |
| `syntax-parser.sld` | `reader->syntax-list` | Reader → located syntax list |
| `expand.sld` | `syntax-list->ir-library` | Syntax list → unnamed IR library |
| `expand.sld` | `syntax->ir-library` | Library syntax → resolved IR library |
| `wasm.sld` | `write-ir-library-as-wasm` | Library dependency graph → WAT on a port |
| `compiler.sld` | `source-file->wat-file` | Source filename → WAT output file |

`make test` checks host values, JSON escaping, nesting, file closure, and omission
of failed or escaped calls. `scripts/test-chromium-trace` parses files recorded
by Chibi and linked Wasm and checks missing destinations, file-opening failures,
and omission of a span on terminal error. Add `--target both` to run the same
linked module through the native executor. `scripts/test-build` checks compiler
stage coverage, import side effects, destination ownership, and finalization
before a script exits with a nonzero execution status.
