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

## Viewing a trace over SSH

Run the viewer on the development server:

```sh
nix-shell
scripts/view-traces build/snail-scheme.trace.json
```

On your laptop, forward its loopback port and open
`http://127.0.0.1:9000/`:

```sh
ssh -N -L 9000:127.0.0.1:9000 user@server
```

The script prints the URL and forwarding command. `--port 9010` selects another
server port; the local forwarded port may differ. Opening the URL loads the
selected JSON or binary trace directly in Perfetto. Reload the page to load
updated contents. Serve completed recordings.

`shell.nix` supplies the official Perfetto `v58.2` UI release (about 16 MB) as a
hashed Nix dependency and sets `PERFETTO_UI` to its store path. Nix fetches it once;
the script reads the installed assets. The UI and trace bytes are served locally
through the tunnel, so the browser needs no internet connection to load them.
Perfetto starts in dark mode. The theme bootstrap uses
the pinned UI's stored `theme` setting; verify it when updating the release.

The server binds only to `127.0.0.1` and serves only the selected trace and the
installed UI assets. `scripts/test-view-traces` checks automatic loading,
refresh, escaped filenames, HTTP file boundaries, and the required shell dependency.
See [Perfetto's self-hosting instructions](https://perfetto.dev/docs/visualization/embedding-the-ui#self-hosting-the-ui)
for the release bundle's layout.

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
sources appear within expansion. Parsing is recorded as `reader->syntax-list`;
each loaded source produces its own span. Use a viewer's inclusive/exclusive
durations to separate costs. There are no per-instruction or per-primitive spans;
WasmGC does not expose portable collector timings.

| Module | Entry point | Representation |
| --- | --- | --- |
| `reader.sld` | `file->reader` | Filename → character reader |
| `syntax-parser.sld` | `reader->syntax-list` | Reader → located syntax list |
| `expand.sld` | `syntax-list->ir-library` | Syntax list → unnamed IR library |
| `expand.sld` | `syntax->ir-library` | Library syntax → resolved IR library |
| `wasm.sld` | `write-ir-library-as-wasm` | Library dependency graph → WAT on a port |
| `compiler.sld` | `source-file->wat-file` | Source filename → WAT output file |

Within `write-ir-library-as-wasm`, the emitter records these stages:

| Span | Work |
| --- | --- |
| `prepare-module` | Collect globals and procedures; analyze mutation, cells and known callees |
| `generate-procedure-functions` | Build procedure bodies, including local/capture analysis |
| `generate-library-functions` | Build library initialization bodies in dependency order |
| `write-wasm-module` | Write the complete module to the caller's port |
| `write-module-imports` | Write runtime, finalizer and Rust service imports |
| `copy-file <path>` | Copy each runtime text fragment; the path identifies the fragment |
| `write-module-definitions` | Assemble and serialize globals, constants, adapters, bodies and entries |

The last three stages nest inside `write-wasm-module`. Procedure and library
generation register constants before definition writing; their spans cover
generation, while definition writing includes final WAT serialization. Local
capture analysis remains part of procedure generation. Each emission adds eight
stage events regardless of the number of procedures or libraries.

`make test` checks host values, JSON escaping, nesting, file closure, and omission
of failed or escaped calls. `scripts/test-chromium-trace` parses files recorded
by Chibi and linked Wasm and checks missing destinations, file-opening failures,
and omission of a span on terminal error. Add `--target both` to run the same
linked module through the native executor. `scripts/test-build` checks compiler
stage coverage and nesting, import side effects, destination ownership, and
finalization before a script exits with a nonzero execution status.
