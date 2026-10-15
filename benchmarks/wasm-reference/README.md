# Rust/WASI benchmark references

The suite implements all 57 canonical workloads. Source
coverage, successful execution of the unchanged canonical inputs, and measured
performance are separate statuses. [`PORTING.md`](PORTING.md) records the
implementation contracts and remaining work. `suite.py` freezes sources and
tool/binary hashes, runs actual Node/Wasm plus independent original Chez checks,
and retains failures such as Ackermann's default native-stack overflow.

```sh
python3 benchmarks/wasm-reference/suite.py --build \
  --output build/rust-reference-checks --benchmarks all --checks full
```

`--checks small` executes independent fixtures and wrong-result probes;
`--checks quick` retains the original algorithm inputs while changing the
iteration count to one. `all` selects implemented sources, and the report
explicitly lists the remaining canonical workloads. Neither reduced checks nor
source presence marks a workload as fully validated. These are correctness
runs; coordinate a clean window separately before collecting performance data.

The historical five-case measurement driver and report below remain frozen.

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

Extract the [checked measurement archive](../results/2026-10-13-wasm-five-reference/README.md)
into `/tmp/five-reference`. It contains the original input fixtures and Chez
programs, so the historical worktrees are unnecessary for reproduction:

```sh
mkdir -p /tmp/five-reference
tar -xJf benchmarks/results/2026-10-13-wasm-five-reference/artifacts.tar.xz \
  -C /tmp/five-reference
python3 benchmarks/wasm-reference/measure.py \
  --source /tmp/five-reference/upstream \
  --chez-source /tmp/five-reference \
  --output /tmp/five-rerun/results.json --prepare-only
python3 benchmarks/wasm-reference/validate.py --prepared /tmp/five-rerun
```

After coordinating a quiet CPU window, repeat `measure.py` without
`--prepare-only`. It discards one full preliminary run per implementation and
retains three fresh-process runs, rotating benchmark order and alternating
implementation order. Compilation is separate. Whole-process times are recorded
beside workload times. The defaults select only the five references and Chez,
with CPU 5 and unchanged original inputs/counts.

`validate.py` additionally checks Unicode copying, tab/CR word behavior, and all
213,829 graphs in their complete original order. Its graph audit runs one
generation and compares serialized results after removing ASCII whitespace;
all graph atoms are single-digit vertex numbers. These audits are functional
checks and do not contribute timing samples.
