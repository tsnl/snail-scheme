# Chromium traces

## Live compilation progress

Compiler and build phases print `[lofi]` start/completion messages to stderr and
flush each message immediately. Completion includes elapsed milliseconds; an
interrupted or failed phase has no successful completion message. Source paths
and public entry names distinguish nested builds. Program output and compiler
protocol stdout remain separate. Set `SNAIL_LOG=off` (or `0`) for quiet builds:

```sh
SNAIL_LOG=off ./lofi run examples/scheme-fibonacci.sld
```

The Chibi host library `(lofi host log)` exports `log-message`,
`call-with-log-phase` and the scoped Boolean parameter `log-enabled?`. Importing
it prints nothing. Progress uses Chibi's wall-clock jiffies, with backward steps
clamped to zero; these durations are build diagnostics rather than benchmark
measurements. Messages remain live through the synchronous Node compiler service,
which forwards its retained stderr file while waiting for FIFO responses. Host
loss reports retain only the last 64 KiB of diagnostics in memory.

## Trace files

The Chibi-hosted compiler uses `(lofi host chromium-trace)`. Importing its
libraries creates no trace files. A build establishes a destination before
running traced passes and closes it on normal return.

`scripts/build-lofi input.sld output.wasm` retains `output.wasm.trace.json`.
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
Assembly, mandatory Binaryen optimization and disassembly record their own build
operations. Inclusive/exclusive durations distinguish a pass's own work from its
children.

A span is written after its operation returns. Completed children survive an
interrupted parent, but abandoning the outer file scope may leave incomplete
JSON. Failed compilation must not be mistaken for a completed timing sample.
Compiler traces contain no collector or per-instruction measurements.

## Host API

```scheme
(import
 (scheme base)
 (lofi host chromium-trace))
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
Lofi tracing library is separate work; the host decorator runs in Chibi.

WasmGC collection belongs to the engine. This utility records compiler operations;
it does not record engine collection pauses. Historical custom-collector traces
remain in the [benchmark archive](../benchmarks/history.md).
