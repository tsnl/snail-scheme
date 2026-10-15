# Rust exact-arithmetic reference review

The reviewed Rust/Wasm `pi` and `chudnovsky` references pass their unchanged
canonical inputs against independently compiled original Chez controls.
These are correctness observations, not retained performance samples.

| Workload | Canonical repetitions | Precisions | Complete result |
| --- | ---: | --- | --- |
| `pi` | 100 | 50 through 500, step 50 | Three fixed-point algorithms, including both signed differences |
| `chudnovsky` | 1,000 | 50 through 500, step 50 | All ten exact integers |

[Validation](validation.json) also covers independent small examples, empty
precision ranges, and rejection of a changed signed difference or late result.
Five native unit tests cover signed quotient semantics, root boundaries, exact
split triples from the original Scheme oracle, and empty ranges. Formatting and
Wasm-target Clippy checks pass.

The [independent behavioral review](review.json) found one extra timed operation:
the Rust translation recomputed `640320^3` at every recursive split leaf. The
original Scheme computes it once at top level, before timing. Rust now defines
the exact value as a compile-time u64 constant. Each leaf still computes its
variable cube, product and quotient. Inspection of the emitted recursive Wasm
function finds two bigint exponentiation call sites before the change and one
after it, with the full u64 constant retained. The canonical source traversal
has 210,000 leaves; this is a source-derived count, not dynamic V8 profiling or
a measured speedup.

Each Pi recurrence retains its original scale construction, old-state reads and
division boundaries. Keeping each complete transition together makes those rules
visible. Rust uses inline rows in result vectors and owned bigint buffers;
Scheme uses lists and tracing collection. The scalar constant can select a
different multiplication routine. These representation and library differences
remain part of the reference comparison.

The source checkpoint is `c14f3f1`. [Artifacts](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-13-rust-exact-arithmetic/artifacts.tar.xz) include the
complete source/input snapshots, linked Wasm, compiled Chez controls, independent
split oracle, and before/after disassemblies. [The manifest](manifest.json) and
[replay check](replay-check.json) verify all 147 regular files and two relative
input links. Archive SHA-256:
`893f59fcd4e8dc6681cb316985c05f38e1f0e14b95b163ce40ccea8738a5d6a5`.

Extract the archive into a fresh directory. From `validation/cases/pi`, run the
recorded Node and Chez tools with:

```sh
node --no-warnings ../../reference-source/run-wasi.mjs program.wasm < input.txt
scheme --program program.so < input.txt
```

Use `validation/cases/chudnovsky` for the other workload. The archive's source
snapshot, pinned Cargo lockfile and release profile support rebuilding. This
review covers these two references; it does not complete the all-57 porting and
measurement task.
