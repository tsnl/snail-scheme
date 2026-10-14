# Frozen Rust Mazefun handoff protocol

The measurement input is the archived, byte-exact `case/input.txt`: count 10,000,
dimensions 11 and 11, then the original complete grid. Its SHA256 is
`38c693aaa745e91ed261ff5c4e4999126ab70c6d4c4b55c61510ba0eef3b3644`.
Use `case/program.wasm`, SHA256
`4e1f45f9c925dde00788408ab97b262c77c7201967c7b49768970bcd50efd885`,
and the frozen `reference-source/run-wasi.mjs` host. The historical program and
the observer are separate correctness diagnostics and cannot replace it.

From the frozen `case/` directory, the command is:

```sh
node --no-warnings ../reference-source/run-wasi.mjs program.wasm < input.txt
```

`handoff.json` retains exact original absolute tool/host/artifact paths, cwd,
stdin bytes and hashes. Verify the Node executable hash/version in `tools.json`;
the host exposes cwd at WASI `/`. Mazefun uses no workload files. Process startup,
Wasm compilation/instantiation and all input decoding happen before its Rust
workload clock. Initialization of false, every maze construction, intermediate
cleanup, previous-result cleanup and the complete supplied-result predicate are
inside that clock. Result/CSV serialization and final-result cleanup follow the
successful stopped clock. A failed predicate must never become a sample.

Accept only exit zero, no stderr, exactly one numeric finite nonnegative
`+!CSVLINE!+rust-wasm,mazefun:10000,...` row and one complete result equal to all
parentheses/121 original mark symbols. Reject missing output, failed predicates,
partial output, wrong labels and any nonzero exit. The full expected canonical
serialization is `expected-maze.txt`; its SHA256 includes its trailing newline.
Whitespace in original input formatting is not semantically significant, but
the timing stdin itself stays byte-exact.

All retained durations in this preparation, historical validation, observer and
replay are diagnostic provenance, not clean timing samples. Parent coordinates
the later quiet campaign and system ordering. Do not shorten counts/dimensions,
add timed validation/counters, reuse a precomputed maze or apply new barriers.
Any source, compiler, flags, host, tool, input or artifact change invalidates this
handoff identity and needs its own preparation/validation evidence.

`manifest.json` maps logical paths to immutable `blobs/SHA256` in
`artifacts.tar.xz`. Restore each mapped file under a new scratch directory and
verify both each blob and each restored file against its SHA256. The archive
verifier runs no workloads. Archived absolute preparation commands remain
honest records; they are not promised to exist after restoration. A relocated
replay substitutes only the restored artifact/host paths and preserves stdin.
The included relocated count-one checks are correctness probes, not timings.

To rebuild Rust with the recorded installed toolchain and dependency cache,
use a fresh target directory and the frozen package:

```sh
env -u RUSTFLAGS -u CARGO_ENCODED_RUSTFLAGS \
  CARGO_TARGET_DIR=/tmp/mazefun-rebuild-target \
  cargo build --offline --release --target wasm32-wasip1 --bin mazefun --verbose \
  --manifest-path /tmp/mazefun-restored/reference-source/Cargo.toml
```

The complete project source, Cargo manifest/lock, actual verbose rustc commands,
selected environment, actual Rust executables and execution tools are hashed.
External registry dependency/sysroot binaries and the full inherited environment
are not vendored. A rebuilt artifact is independently hashed and checked rather
than relabeled as the frozen artifact. The preparation scripts retain their
original worktree-relative layout; exact build/execution commands above make
relocation explicit.

`retained-work.json` maps all 24 observer sites to canonical WAT line locations.
It records exact erasure, feature-limited assembly and completed Node/WASI runs.
Initial observer failures are preserved under `failed-attempts/`: r1 assumed an
extra trailing newline; r2 enabled Binaryen compact imports unsupported by Node.
Neither failure changed the canonical binary or became a successful observation.
