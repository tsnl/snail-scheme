
The `scripts/test-*` commands launch ordinary Chibi programs in `tests/snail-tests`.
The harness records every command, its terminal output, status, duration and owned
process cleanup under a fresh attempt directory in `build/`. These durations are
diagnostics, not clean benchmark measurements. Contract tests retain raw Wasm,
mandatory Binaryen output, and native execution with forced collection where the
contract calls for it.

`native-root-publication/` keeps operand references across repeated publication,
moving collection in imports, branches, loops, and a tail transfer. Its shared
array elements also exercise a moving initializer and an operand-only array.
The native suite runs normal and forced-moving executables plus raw and
Binaryen-optimized Wasm in V8.

`backend-suites.json` is shared by the serial backend umbrella and `ci.mjs`.
The latter creates deterministic CI partitions and invokes the existing runners;
it does not compile or interpret fixtures. Run `node tests/ci.test.mjs` to check
partition coverage and rejection of incomplete execution evidence. Integration
success requires the exact assigned case list in both `selection.json` and
`results.json`, all cases passing, and a matching `completion.json`. Backend
success requires the selected suites to reach the umbrella's final validation
record. New attempt directories prevent stale records from satisfying a check.

The initial scheduling baseline on 2026-10-17 was a successful 29-suite run with
3,432.268 seconds of summed constituent command duration, including 1,632.856
seconds in integration. That is 57.20 minutes of recorded command time, not a
measured GitHub Actions wall time. That historical integration attempt passed 356
cases; the current manifest contains 396. Sharding preserves the current cases,
including expected compile rejections and both Wasm forms for executable cases.
The separate 57-workload benchmark comparison remains unchanged.

A matched local sample at `c9a1c05d` selected 32 evenly spaced integration cases
(`floor(i * 366 / 31)`, `i = 0..31`). With the same toolchain, a warm supervisor,
fresh output directories and `BINARYEN_CORES=1`, serial execution took 121.900
seconds and four concurrent shards took 34.398 seconds on a 24-CPU host. Both
completed the same 19 executable cases, 13 compile rejections and 70 fixture
commands. Summed command durations, including each process's setup, were 120.005
and 121.012 seconds. This cut sample wait time by 71.78% (3.54x faster); it is
not a cold build measurement or a per-case compiler speedup.

The first complete [hosted run](https://github.com/tsnl/snail-scheme/actions/runs/39014095547)
at that revision passed in 19 minutes 2 seconds, including queueing and setup.
Its four ordinary backend groups took 1,000.258, 476.507, 866.857 and 808.016
seconds in their runners; the longest integration shard took 405.424 seconds.
Those recorded suite durations motivated nine backend groups: their longest
summed suite time would be 570.513 seconds, compared with 987.916 seconds in the
original four-group assignment. That calculation excludes setup and is a
scheduling estimate, not an observed speedup. Nine backend, eight integration
and three host/public jobs fit 20 simultaneous runners without another scheduling
algorithm.

`scripts/test-lofi-serialization` checks the complete fixture inventory in
`serialization/cases.json`: derived graphs, nominal type tags, malformed input,
unsupported types, S-expression text/binary boundaries and packed snapshots.
It executes raw and optimized Wasm linked to the Rust WASI runtime, then native
code from the identical optimized guest. Rejection probes check initialization,
failure status and diagnostic text. Supply fixture names to select cases, or
use `--only wasm` and then `--only native --reuse-artifacts DIRECTORY` to split
the execution routes. Small native cases collect on every allocation; the large
boundary case uses an interval of 4,096 allocations.

Lofi fixtures use `.sld` files and `(lofi ...)` imports. Frozen migration,
validation and oracle-provenance records retain the SFIR names and paths from
their recorded revisions; they are historical evidence, not current commands.

Native entries and scalar providers are Rust sources. The build driver creates
Cargo packages that link the generated guest object with the same `snail-runtime`
library used by the product. `tests/Cargo.toml` owns independent transport-data,
optimizer, adversarial compiler-process and host-loss probes; it does not define
another runtime. The host-loss probe publishes its readiness record by writing
and closing a sibling temporary file, then renaming it. Seeing `host-ready`
therefore guarantees complete JSON before the controller kills the host and
checks that its native processes disappear.

Numeric, reader, writer and Unicode expectations are committed data, with source
revision and independent oracle provenance in `oracle-provenance.json`. The
integer, Fraction and seeded arithmetic cases preserve the complete previous
case inventories. Unicode 16 folding stores every nonidentity mapping; the Rust
data probe expands the entire 1,112,064-scalar domain, including identities.
Changing an oracle requires reviewing its expected answers and provenance.
