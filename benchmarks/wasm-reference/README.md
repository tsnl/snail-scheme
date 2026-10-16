# Rust/WASI benchmark references

The suite implements all 57 canonical workloads. Source
coverage, successful execution of the unchanged canonical inputs, and measured
performance are separate statuses. [`PORTING.md`](PORTING.md) records the
implementation contracts and remaining work. `suite.scm` freezes sources and
tool/binary hashes, runs actual Node/Wasm plus independent original Chez checks,
and retains failures such as Ackermann's default native-stack overflow.

```sh
chibi-scheme -I src -I wasm-native/scheme -I benchmarks benchmarks/wasm-reference/suite.scm --build \
  --output build/rust-reference-checks --benchmarks all --checks full
```

The complete residual-program, assembly, instruction-graph, nucleic and generated-file
audit tests run with:

```sh
chibi-scheme -D snail-tests -I src -I wasm-native/scheme -I tests -I wasm-native/tests -I benchmarks \
  benchmarks/wasm-reference/tests/audits.scm
```

Compiler stage probes use `tests/compiler-frontend.scm`, `tests/compiler-gvm.scm`,
`tests/compiler-asm.scm`, and `tests/compiler-assembly.scm`, each with `--output DIR`.
Build the `compiler_frontend` Cargo example for `wasm32-wasip1` before running them.

`--checks small` executes independent fixtures and wrong-result probes;
`--checks quick` retains the original algorithm inputs while changing the
iteration count to one. `all` selects implemented sources, and the report
explicitly lists the remaining canonical workloads. Neither reduced checks nor
source presence marks a workload as fully validated. These are correctness
runs; coordinate a clean window separately before collecting performance data.

Historical five-case measurements remain in their immutable result archives.
Active preparation uses the authored Chez controls in `benchmarks/sfir`; no
Scheme source generator or Snail Scheme compiler is used.

The [completed SFIR full57 comparison](../sfir/evidence/20261015-full57.md)
retains 56 measured Rust Wasm routes and all 57 native routes, with default
Wasm Ack's stack failure visible. It compares matching SFIR targets and keeps
original/adapted Chez, source representations and opacity differences explicit.
Corrected Mperm is a separate six-way campaign; later packet-I/O timings are
also separate. Earlier Rust checkpoints below keep their original provenance.

At the latest completed execution checkpoint, all 57 workload executables have
been built and checked, and 56 pass unchanged canonical inputs/counts in Node/Wasm.
The default recursive Ackermann variant retains its native-stack failure;
`ack --heap-frames` separately passes the same canonical workload. Pending
independent sharing/structural/SLaTeX reviews remain visible in the checkpoint.
The [Compiler archive](../results/2026-10-13-rust-compiler/README.md) records its
full 2,000 compilations, exact 497-line result, complete word/graph diagnostics,
negative checks and focused simplify review.
[`checkpoint.json`](checkpoint.json) retains exact source/binary hashes,
validation paths, remaining workloads and pending independent reviews.
The [full-suite evidence store](../results/2026-10-13-rust-full-suite/README.md)
preserves the selected canonical binaries, corresponding source bundles, inputs
and original reports for all 57 cases, with verified relocation mappings.
The [partial-evaluation/parsing archive](../results/2026-10-13-rust-peval-parsing/README.md)
commits their exact source, binary, input, oracle and retained-work evidence.
The [SLaTeX archive](../results/2026-10-13-rust-slatex/README.md) records
all 28,500 canonical generated files and the separate complete-file oracle.
The [exact-arithmetic archive](../results/2026-10-13-rust-exact-arithmetic/README.md)
records reviewed Pi/Chudnovsky recurrences and the fixed Chudnovsky setup correction.
The [Ray handoff](../results/2026-10-14-rust-ray-handoff/README.md) preserves its
historical artifact and a separately corrected result predicate/signed-count
driver, with unchanged rendering source, full50 images and per-invocation file
lifecycle evidence. No clean Ray timings are claimed by that handoff.

The [Mazefun handoff](../results/2026-10-14-rust-mazefun-handoff/README.md) preserves
its historical artifact and a separately corrected complete result predicate,
signed counts/dimensions and false/error results. Full-count output, rejection,
persistent-kernel and executed retention evidence are frozen before clean timing.

The historical measured references port `cat`, `lattice`, `wc`, `graphs`, and `deriv` from
the pinned R7RS suite at `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. Each executable
reads the original Scheme-format benchmark input from stdin and executes its
original iteration count. They provide a Rust/LLVM, linear-memory allocation,
WASI, and V8 baseline for those algorithms.

| Executable | Original workload | Count | Validation |
| --- | --- | ---: | --- |
| `cat` | Buffered character-by-character UTF-8 copy; delete/open/copy/flush/close each iteration | 50 | Complete output SHA-256 equals the 4,460,056-byte input |
| `wc` | Character scan; only space and newline delimit words | 50 | `(31102 851820 4460056)` |
| `lattice` | Build the L2/L3/L4 lattices and enumerate monotone L4→L4 maps | 10 | `120549` |
| `graphs` | Generate and materialize rooted directed graphs, preserving permutation pruning and edge traversal | 3 | `213829`, plus complete ordered materialization equality with Chez |
| `deriv` | Construct a fresh derivative tree for the original expression, retaining shared input subexpressions | 10,000,000 | Exact equality with the original expected expression |

[`src/lib.rs`](src/lib.rs) contains the small reader for these frozen input
formats, the UTF-8 character reader, and timing output. The reader is not a full
Scheme datum reader. Each algorithm lives in its own executable under
[`src/bin/`](src/bin/). [`run-wasi.mjs`](run-wasi.mjs) invokes Node's built-in WASI
preview1 implementation and exposes the case directory as the guest filesystem
root. The workload timer starts after input parsing and ends after the original
result predicate. `wc` also formats its three integer results before the timer
ends; other result formatting and all external digest checks follow it.

The Rust representations are deliberate language differences: vectors replace
some Scheme lists; `Rc` retains persistent assignments, edge lists, and shared
expression nodes; `LinkedList` materializes the outer graph result. Graph length
still traverses every result node. Rust drops unreachable objects through
ownership and reference counting, whereas Scheme relies on tracing GC. Numeric
domains cover the pinned inputs and results rather than arbitrary Scheme numbers.
`black_box` prevents eliding or hoisting workload calls; it does not reproduce
the Scheme harness's `hide` allocations. The comparison therefore does not
isolate engine overhead, GC cost, or one compiler optimization.

Build with the installed Rust toolchain and WASIp1 target. The exact-integer
workloads use pinned `num-bigint` 0.4.8 and its Cargo.lock dependencies:

```sh
cargo build --offline --release --target wasm32-wasip1 \
  --manifest-path benchmarks/wasm-reference/Cargo.toml
cargo fmt --all --manifest-path benchmarks/wasm-reference/Cargo.toml -- --check
cargo clippy --offline --release --target wasm32-wasip1 \
  --manifest-path benchmarks/wasm-reference/Cargo.toml -- -D warnings
```

The measured release profile uses `opt-level = 3`, LTO, one codegen unit, and
abort-on-panic. There is no post-compilation Binaryen transformation. The original
Scheme controls are the frozen, already compiled Chez programs at safe
optimization level 2.

The [checked five-case measurement archive](../results/2026-10-13-wasm-five-reference/README.md)
retains its historical artifacts and protocol. The old five-case driver was
removed from the active tree during SFIR migration; its source is available at
revision `d5c2d06`. New SFIR/Chez/Rust comparisons use the explicit status and
freezing contracts in [`../sfir`](../sfir/README.md). Historical Rust validation
and timings do not establish SFIR validation or clean comparison coverage.
