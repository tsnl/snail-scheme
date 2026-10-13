# Five Rust/WASI references, October 13

Optimized Rust compiled to WASIp1 executes the original `cat`, `lattice`, `wc`,
`graphs`, and `deriv` workloads in Node/V8. It substantially outperforms the
historical Snail batch on the first four; its derivative reference is slower
than Snail. This is a language, representation, allocator, and WASI baseline,
not an isolated measurement of engine or GC overhead.

All times below are median workload seconds. Rust and Chez share the new quiet
measurement window. **Snail is from a separate, earlier clean batch** at
`b218ce27cd5f7a157b68a450899c6805f041e856`; this report measures no later compiler
or typed-extern changes.

| Workload | Original count | Rust → Wasm/V8 | Chez, same window | Snail, historical | Snail / Rust |
| --- | ---: | ---: | ---: | ---: | ---: |
| cat | 50 | 1.914391 | 0.700359 | 21.014144 | 10.98× |
| lattice | 10 | 1.051455 | 1.171034 | 20.358708 | 19.36× |
| wc | 50 | 1.385094 | 0.648524 | 10.246147 | 7.40× |
| graphs | 3 | 0.586436 | 0.770368 | 8.369200 | 14.27× |
| deriv | 10,000,000 | 2.772785 | 0.419001 | 2.142225 | 0.77× |

The IO controls retain one-character buffered reads/writes and original file
reopening behavior. There is no bulk-copy control in this table. Lattice retains
monotone-map backtracking and the nested component order. Graphs retains minimal
permutation-tree pruning, triple-loop reachability, persistent edge lists, all
graph snapshots, and the final result-list traversal. Deriv allocates a fresh
tree on every call and shares compound input subexpressions in its product rule.
The original deliberately incorrect quotient rule is preserved.

These references use Rust vectors, `Rc`, and `LinkedList` where appropriate;
their allocation layout, reference counting, and reclamation differ from Scheme
pairs, WasmGC objects, and tracing collection. The Rust driver uses `black_box`
instead of reproducing the Scheme `hide` scaffolding. Numeric representations
cover the pinned workloads rather than every Scheme numeric case. Those
differences prevent attributing the timing gaps exclusively to the engine,
GC, or the compiler's call ABI. In particular, Rust takes 29.4% more workload
time than Snail on `deriv` despite using the same V8 engine.

Whole-process medians are separate measurements and include loader startup,
Wasm compilation/instantiation or Chez loading, output, and teardown:

| Workload | Rust process seconds | Chez process seconds |
| --- | ---: | ---: |
| cat | 1.937368 | 0.731458 |
| lattice | 1.076533 | 1.203057 |
| wc | 1.409923 | 0.680834 |
| graphs | 0.611222 | 0.803982 |
| deriv | 2.798063 | 0.450626 |

The workload timer excludes input parsing, compilation, process startup, and
external digest validation. It includes all original iterations and the final
original result predicate. `wc` additionally formats its three integer results
before elapsed time is captured; other result formatting follows capture.
Every execution starts a
fresh process; V8 uses its default tiering. One full preliminary run per cell
is discarded, followed by three retained rounds. Benchmark order rotates and
Rust/Chez order alternates for each workload. Other compiler/test processes
were explicitly paused for the retained batch.

The host is Linux on an Intel Core Ultra 7 270K Plus, pinned to logical CPU 5.
Rust/Cargo are 1.95.0 with LLVM 22.1.2; release uses `opt-level=3`, LTO, one codegen
unit, and abort-on-panic, with no custom Rust flags or post-compilation optimizer.
Node is 24.19.0, V8 is `13.6.233.17-node.51`, and its uvwasi is 0.0.23. Chez is
10.4.1 at safe optimization level 2. Tool paths, hashes, versions, source hashes,
module hashes, commands, stdout/stderr, and raw samples are preserved.

Every retained and preliminary run passes the original result predicate. Cat's
entire 4,460,056-byte output matches the input SHA-256
`2994b446dfb07d7cf324fb6aa32d519b3f0bd53a582268714adf08df5f45b8d3`.
The separate untimed graph audit compares all 213,829 graphs and ordered outgoing
edge lists, in their original result order. Both implementations produce
6,128,419 canonical bytes with SHA-256
`8a58eaef7bceea8ab316c8fdad5f6b3aaa3df333a29f39e8d636c4d54b412049`.
Canonicalization removes ASCII whitespace; all atoms are vertices 0–6.
Additional UTF-8 tests verify character copying and that tabs/CR do not delimit
words. Rust formatting and target Clippy with `-D warnings` pass.

The pinned simplify workflow's independent explanation and subsequent critique
are complete. The review matched the six Rust modules against character I/O,
search-state restoration, materialization, sharing, and lifetime requirements.
No code changes were justified. Bulk copying, counting graph leaves without
materializing results, and caching derivatives would change the workloads and
were rejected. This report corrects the `wc` formatting boundary found during
review; the measured source, modules, and samples remain unchanged.

- [Sources and reproduction](../../wasm-reference/README.md)
- [Raw new samples](results.json) and [comparison summary](summary.json)
- [Untimed equivalence checks](validation.json)
- [Original historical Snail/Chez raw report](historical-snail-five.json) and [its summary](historical-five-summary.json)
- [Exact sources, inputs, modules, and full graph outputs](artifacts.tar.xz), indexed by [manifest](manifest.json)

The historical report SHA-256 is
`02e05c9c0e402046e5b3a9ad0b46fef8860296ec12cb139faedd0c50df4f817c`.
The preserved upstream suite revision is
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. Scope is exactly these five workloads.
