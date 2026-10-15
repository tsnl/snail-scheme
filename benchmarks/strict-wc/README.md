# Strict Scheme source in the wc experiment

[`count.scm`](count.scm) implements the original `wcport` state transitions with
I32 character/status reads, I64 counters, and a Bool word state. It reads one
Unicode scalar at a time from the frozen scalar provider used for the cat
experiment. Only ASCII space and newline end a word. Tabs, carriage returns,
NUL, and other Unicode characters stay within words. EOF changes no counter;
an error immediately consumes the provider's saved fatal diagnostic.

The original benchmark opens and closes each input file, runs fifty counts of
the 4,460,056-byte corpus, and checks the ordinary Scheme list
`(31102 851820 4460056)`. Those operations and its workload timer are preserved.
The strict worker submits three I64 results through one native scalar call.
The adapter constructs the list only after successful EOF. Its owned ABI root
keeps the input wrapper alive throughout the reads and result allocation;
WasmGC traces intermediate list values on the operand stack. A resource ID is
never a GC address.

The scalar result sink uses single-instance diagnostic globals. Calls are
synchronous, the provider makes no Scheme callbacks, and invocations do not
overlap. Fatal errors never expose stale or partial results. Fixed I64 counters
cover the pinned workload; this experiment does not implement arbitrary-size
Scheme integers or a public typed character/EOF API.

The old generated `wcport` and strict worker use the same frozen Rust provider,
Node host, platform module, Binaryen flags, startup entry, and strict-module
initialization. Both are rebuilt with the experiment's probes. The old control
therefore has a different final binary from its historical measurement.
An untouched compiled Chez 10.4.1 program uses the original character loop,
file lifecycle, result predicate, fifty repetitions, and safe optimization
level 2. Its harness uses Chez's monotonic clock.

## Reproduce

Restore the [checked result archive](../results/2026-10-13-strict-source-wc/README.md)
and validate its manifest and compiled artifacts:

```sh
python3 benchmarks/strict-wc/replay.py /tmp/strict-wc-replay
```

The restored experiment contains the frozen provider, legacy wc compilation,
Chez source and binary, strict compiler sources, commands, logs, raw/optimized
and linked Wasm, functional checks, corpus, and raw timings. To rebuild with a
compiler supporting strict `define-extern` and native exports:

```sh
python3 benchmarks/strict-wc/measure.py prepare \
  --compiler /path/to/strict-compiler-worktree \
  --frozen /tmp/strict-wc-replay/experiment/provider \
  --legacy /tmp/strict-wc-replay/experiment/legacy \
  --chez /tmp/strict-wc-replay/experiment/chez \
  --output /tmp/strict-wc
python3 benchmarks/strict-wc/measure.py validate --output /tmp/strict-wc
```

Preparation verifies the earlier provider and Chez manifests and all consumed
legacy artifact hashes. It records the strict compiler revision and source
snapshot, exact tool paths/hashes, build environment, and commands. Validation
executes the final linked artifacts on Node. The
[functional checker](../../tests/strict-wc/check.mjs) lives with integration
runners; a source link in this directory supplies the experiment snapshot.
It covers delimiter transitions,
Unicode including supplementary scalars and NUL, UTF-8 across a file-buffer
boundary, repeated EOF, full corpus counts, fatal closed/wrong-direction and
malformed/truncated input errors, I64 result transport, native signature
rejection, owned-port liveness, and temporary-root balance. A zero-repeat
initializer fixture runs the original startup before the functional probes.
Chez separately passes the original full-corpus predicate with one repetition.

After coordinating a quiet CPU window:

```sh
python3 benchmarks/strict-wc/measure.py measure \
  --output /tmp/strict-wc --cpu 5 --rounds 3
```

Each variant runs in a fresh process with default engine settings. One full run
per variant is discarded; three retained rounds rotate variant order. Every
run must pass the original predicate with the exact corpus and parameters.
Workload and process wall times are recorded separately. Compilation and
initialization occur before the Scheme workload timer; process wall time
includes startup. Functional probes and GC forcing occur outside clean timing.

This is a matched boundary/representation/control-flow experiment. It does not
isolate inference, Wasm engine overhead, or collection time. Legacy AWI startup,
current-port roots, file management, and final list construction remain.
