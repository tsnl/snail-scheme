
The `scripts/test-*` commands launch ordinary Chibi programs in `tests/snail-tests`.
The harness records every command, its terminal output, status, duration and owned
process cleanup under a fresh attempt directory in `build/`. These durations are
diagnostics, not clean benchmark measurements. Contract tests retain raw Wasm,
mandatory Binaryen output, and native execution with forced collection where the
contract calls for it.

Lofi fixtures use `.sld` files and `(lofi ...)` imports. Frozen migration,
validation and oracle-provenance records retain the SFIR names and paths from
their recorded revisions; they are historical evidence, not current commands.

Native entries and scalar providers are Rust sources. The build driver creates
Cargo packages that link the generated guest object with the same `snail-runtime`
library used by the product. `tests/Cargo.toml` owns independent transport-data,
optimizer, adversarial compiler-process and host-loss probes; it does not define
another runtime.

Numeric, reader, writer and Unicode expectations are committed data, with source
revision and independent oracle provenance in `oracle-provenance.json`. The
integer, Fraction and seeded arithmetic cases preserve the complete previous
case inventories. Unicode 16 folding stores every nonidentity mapping; the Rust
data probe expands the entire 1,112,064-scalar domain, including identities.
Changing an oracle requires reviewing its expected answers and provenance.
