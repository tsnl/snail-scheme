
`scripts/test SUITE` launches the named suite's Chibi program in `tests/snail-tests`.
The harness records every command, its terminal output, status, duration and owned
process cleanup under a fresh attempt directory in `build/`. Contract tests retain raw Wasm
and Binaryen output and execute both in V8. The engine owns GC; the host retains
explicit scalar-resource cleanup checks.

`backend-suites.json` is shared by the serial backend umbrella and `ci.mjs`.
The latter creates deterministic CI partitions and invokes the existing runners;
it does not compile or interpret fixtures. Run `node tests/ci.test.mjs` to check
partition coverage and rejection of incomplete execution evidence. Integration
success requires the exact assigned case list in both `selection.json` and
`results.json`, all cases passing, and a matching `completion.json`. Backend
success requires the selected suites to reach the umbrella's final validation
record. New attempt directories prevent stale records from satisfying a check.

`scripts/test lofi-serialization` checks the complete fixture inventory in
`serialization/cases.json`: derived graphs, nominal type tags, malformed input,
unsupported types, S-expression text/binary boundaries and packed snapshots.
It executes raw and optimized Wasm linked to the Rust WASI runtime. Rejection
probes check initialization, failure status and diagnostic text. Supply fixture
names to select cases.

Lofi fixtures use `.sld` files and `(lofi ...)` imports.

`tests/Cargo.toml` owns independent transport-data and optimizer probes. `tools/host/process-supervisor.rs` enforces command
deadlines and reaps descendants; its tests include processes that change groups.

Numeric, reader, writer and Unicode expectations are committed data. The
integer, Fraction and seeded arithmetic cases preserve the complete previous
case inventories. Unicode 16 folding stores every nonidentity mapping; the Rust
data probe expands the entire 1,112,064-scalar domain, including identities.
Changing an oracle requires reviewing its expected answers.
