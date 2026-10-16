# Compiler traces

The Chibi-hosted compiler uses the neutral `(wasm-native chromium-trace)` utility.
It has no dependency on native lowering. Importing its libraries creates no
trace files. A build establishes a destination before it runs traced passes,
and closes that destination on normal return.

`scripts/build-sfir input.sfir output.wasm` retains `output.wasm.trace.json`.
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

The compiler records resolution, inference, specialization and Wasm emission
as separate spans. Each source read and syntax parse has its own nested span.
Assembly, mandatory Binaryen optimization, disassembly and native lowering
record their own build operations. Inclusive/exclusive durations distinguish
a pass's own work from its children.

A span is written after its operation returns. Completed children survive an
interrupted parent, but abandoning the outer file scope may leave incomplete
JSON. Failed compilation must not be mistaken for a completed timing sample.
There are no portable collector or per-instruction measurements in these traces.

## Host API

```scheme
(import (scheme base) (wasm-native chromium-trace))
(define timed-add (chromium-trace "add" (lambda (x y) (+ x y))))
(with-chromium-trace-to "operations.json"
  (lambda () (timed-add 20 22)))
```

This is compiler implementation code executed by Chibi, not SFIR product input.
The decorator preserves zero, one or multiple results and requires an active
file scope. Nested scopes restore the enclosing destination. Each file starts
with thread metadata, followed by Chromium complete-duration events in integer
microseconds. Chibi's jiffy clock has millisecond resolution; backward clock
steps clamp a duration to zero. Concurrent writes to one port are unsupported.
Decorating recursion keeps wrappers active until return and can change tail-call
behavior, so instrumentation must stay outside clean performance comparisons.

`make test` and `scripts/test-chromium-trace` check escaping, nested destinations,
closure, missing destinations, file-opening errors and abandoned spans. A future
SFIR tracing library is separate work; no Scheme compilation path is retained
for the host decorator.
