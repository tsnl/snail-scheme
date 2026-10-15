# Earley timing plan awaiting release

The canonical input is unchanged: one invocation at length 15 with expected tree
count 2674440. Five systems run in separate fresh processes on CPU 5:

1. Production V8: the once-optimized `strict.wasm` from `build-strict`.
2. Common-artifact V8: `optimized.wasm` produced by the native build's mandatory
   second Binaryen pass.
3. Common-artifact native: the mechanical LLVM lowering of those exact final
   bytes, linked with the existing in-house collector, scalar provider and Rust
   archive. `SNAIL_GC_HEAP_BYTES=1073741824` is explicitly set for this system.
4. Original Chez: complete untouched source kernel and benchmark harness.
5. Adapted Chez: the exact typed-adapter kernel/helpers with Chez representations
   and the same original benchmark harness.

One complete five-process round is discarded in advance. Five retained rounds
rotate the order by one system each time, putting every system in each position
exactly once. There are 30 processes and five retained observations per system.
No other exclusions or retries are planned. Failure, timeout, stderr, incorrect
result, malformed output, source/artifact hash drift or inherited-environment
drift stops the campaign and preserves all started records.

Workload clocks exclude startup and cleanup. The Node host instantiates the
module and runs `main` before `process.hrtime.bigint`; it then times `bench` and
the scalar result assertion. The C entry uses `CLOCK_MONOTONIC` around exactly
`wasm.bench(count)`, after host/module initialization and `wasm.main`, and before
printing and `native_finish`. Original/adapted Chez use the unmodified
`run-r7rs-benchmark` loop/predicate with the existing monotonic nanosecond-jiffy
prelude; input reads, startup, compilation and output lie outside that clock.
These small wrapper differences are disclosed rather than attributed to the
collector. A separate parent process clock includes spawning, capture and group
cleanup and is secondary evidence.

The native timer derivative changes only its C entry. The exact frozen
`module.ll`, provider object, `native.c`, `precise-gc.c` and Rust static archive
are copied and relinked with the original `-O3 -flto` link flags. The archived
`earley-timing-prepare-01/derivation.json` records every source and body identity,
the original link command and the derived command. Its fresh canonical/negative
checks pass; no compiler build policy was changed.

Every process has a 180-second deadline and a 10-second owned-group cleanup
deadline. Descendants are killed even if the leader exits or closes its pipes.
The runner rejects profiling/GC-statistics and inherited input/heap overrides,
sets the explicit system-specific heap/input environment, and preserves exact
stdout/stderr. No build, compression, profiler or other benchmark may overlap
the coordinated clean window.

Review-only command:

```sh
python3 benchmarks/results/2026-10-14-strict-earley-preparation/measure-five.py
```

After explicit parent release, from the isolated worktree:

```sh
python3 benchmarks/results/2026-10-14-strict-earley-preparation/measure-five.py \
  --run --output build/earley-clean-01
```

The output directory must not already exist. The preparation and later
performance report remain separate commits. No clean sample has been launched
by this preparation.
