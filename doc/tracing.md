# Chromium traces

The Chibi-hosted compiler uses the neutral `(native chromium-trace)` utility.
It has no dependency on native lowering. Importing its libraries creates no
trace files. A build establishes a destination before it runs traced passes,
and closes that destination on normal return.

`scripts/build-lofi input.sld output.wasm` retains `output.wasm.trace.json`.
Native builds retain `compile.trace.json` in their unique build directory.
These are compiler timings, separate from benchmark execution measurements.

```sh
scripts/view-traces build/output.wasm.trace.json
```

The viewer binds to loopback and serves the selected trace and pinned Perfetto
assets. Over SSH, forward the printed port to your browser. Serve completed
recordings; reloading reads the current file. `scripts/test-view-traces` checks
loading, refresh, escaped filenames and HTTP file boundaries.

## Pass boundaries

Source reads and syntax parsing have their own spans. The shipped bootstrap
compiler does not currently wrap resolution, inference, specialization and Wasm
emission with phase spans. For those boundaries on a complete Siegework build,
use the private instrumentation in
[`scripts/measure-siegework.mjs`](../scripts/measure-siegework.mjs); see the
[self-hosting investigation](self-hosting.md) for commands and timing limits.
`profile` adds source-labelled binding/function spans and nested preparation work;
`hotspots` additionally retains helper call counts and inclusive/self totals in
`operations.json` without emitting millions of tiny events.
Assembly, mandatory Binaryen optimization, disassembly and native lowering
record their own build operations. Inclusive/exclusive durations distinguish
a pass's own work from its children.

A span is written after its operation returns. Completed children survive an
interrupted parent, but abandoning the outer file scope may leave incomplete
JSON. Failed compilation must not be mistaken for a completed timing sample.
Compiler traces contain no collector or per-instruction measurements.

## Host API

```scheme
(import
 (scheme base)
 (native chromium-trace))
(define timed-add (chromium-trace "add" (lambda (x y) (+ x y))))
(with-chromium-trace-to "operations.json"
                        (lambda () (timed-add 20 22)))
```

This is compiler implementation code executed by Chibi, not Lofi product input.
The decorator preserves zero, one or multiple results and requires an active
file scope. Nested scopes restore the enclosing destination. Each file starts
with thread metadata, followed by Chromium complete-duration events in integer
microseconds. Chibi's jiffy clock has millisecond resolution; backward clock
steps clamp a duration to zero. Concurrent writes to one port are unsupported.
Decorating recursion keeps wrappers active until return and can change tail-call
behavior, so instrumentation must stay outside clean performance comparisons.

`make test` and `scripts/test-chromium-trace` check escaping, nested destinations,
closure, missing destinations, file-opening errors and abandoned spans. A future
Lofi tracing library is separate work; no Scheme compilation path is retained
for the host decorator.

## Native collection pauses

The nondefault `native-runtime/gc-trace` Cargo feature enables explicit Rust
host recordings. Normal builds omit the recorder and its clock reads. Enabling
the feature reads no clocks until the host starts a recording. This feature
changes no collection policy and introduces no GC environment options.
Only the single owning host may start or take a recording, after runtime
initialization and outside guest code or finalizers:

```rust
unsafe { native_runtime::native::gc_trace_start(16384)?; }
// Execute guest work through its ordinary entry point.
let trace = unsafe { native_runtime::native::gc_trace_take() }.unwrap();
trace.write_chromium_json(std::fs::File::create("runtime.trace.json")?)?;
let maximum_pause = trace.summary().maximum_pause;
```

Each `Immix collection` event brackets the complete stop-the-world collection:
evacuation preparation, roots and edges, weak callbacks, sweep, and collection
scheduling. Its monotonic timestamp is relative to recording start; timestamps
and durations are integer microseconds in Chromium JSON. This scope excludes
the requesting allocation's search/growth, event bookkeeping, scalar resource
draining outside collection, process startup and final host cleanup. View the
completed file with `scripts/view-traces runtime.trace.json`.
The event array can be combined with other Chromium recordings; align timestamps
and assign distinct process/thread lanes when merging recordings with different
clock origins, including separate native recording scopes.

The host reserves the requested event capacity before recording. During GC the
recorder only reads clocks and updates that buffer; it never allocates managed
objects, grows the buffer or retains managed references. A full buffer drops
later events but continues updating collection count, total pause and maximum
pause. The `native_gc_summary` metadata reports those totals and dropped count.
Zero capacity records only totals. Starting again replaces the old recording;
reservation failure preserves it. Taking a recording disables capture and
transfers its host-owned data for inspection or serialization.

[`scalar-gc-trace-entry.rs`](../benchmarks/lofi/support/scalar-gc-trace-entry.rs)
records only the configured benchmark work, using the same final predicate as
the ordinary timing entry. Build it with `native-runtime/gc-trace` and pass its
trace output path as the first argument. Its JSON result reports
`instrumented_seconds` for guest work and its result check, plus collection count,
dropped events, total pause and maximum pause. Setup, recorder reservation, trace
serialization and final host cleanup stay outside that clock. Keep these times
and pause distributions separate from uninstrumented total-runtime samples:
instrumentation changes execution, and maximum pause is an observed value for
that run, not a bound.
