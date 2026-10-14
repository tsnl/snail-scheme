# Complete Rust Compiler reference

The original 2,000-compilation workload passes in actual Node/Wasm and original
Chez. Its final predicate compares all 497 assembly strings, including the final
empty string. The Rust executable performs located-source construction, lexical
parsing, partial evaluation, assignment conversion, lambda lifting, GVM
generation, block purification, backward slot analysis and genuine 68000/object
assembly on every iteration. It compiles the supplied Fibonacci/Takeuchi/
Ackermann/vector program; that program is not executed by this benchmark.

[Canonical validation](validation.json) includes three independent complete-list
checks and both systems' rejection of a changed instruction, truncated list and
extra line. [Assembly validation](assembly-validation.json) compares every line
and normalized object word for the canonical program once and 17 independent
programs. These cover captured mutation/cells, closures, mutual recursion,
rest/stacked arguments, indirect calls, boolean control flow, arithmetic overlap,
multioperand comparisons, vectors and pair mutation. All 26 complete
[GVM/slot comparisons](gvm-validation.json) and five complete
[assembler diagnostics](assembler-validation.json) also pass with current source.
These are correctness observations; their embedded elapsed times are not clean
performance samples.

The [archive](artifacts.tar.xz) freezes exact source/catalog/manifest/lock/input
files, runtime and diagnostic Wasm, original Chez programs/binaries, complete
outputs, check logs, the focused review and retained-work disassembly. Its
[manifest replay](archive.json) verifies every retained regular file. Historical
frontend/GVM/block/assembler archives remain unchanged. The current runtime
Wasm SHA-256 is
`429ef6969b077d5b6c9c57fe8bb9a8d269fa6d007878cc75a21ac0418ada673e`.

Primitive descriptions/registrations persist outside the workload timer. Every
compilation creates fresh syntax/global state and initializes all 10,000 virtual
operand entries before constructing/parsing source, preserving their overlapping
lifetimes. Replacing the assembly result constructs the next list before dropping
the preceding one. Complete final equality is timed; formatting and diagnostic
word/list/graph comparisons follow the relevant timers.

Rust uses typed arenas, persistent `Rc` list cells, stable mutable association
pairs and owned assembly buffers. It retains obsolete parse/GVM records until
compilation ends and reclaims owned records immediately; Scheme tracing GC has
different allocation and reclamation behavior. Shared mutable environment-root
handles remain distinct from retained immutable list heads. Logical stack slots,
closure captures, trap saves and shared label/descriptor positions preserve the
source semantics. Trap metadata copies its slot spine. Assembly first assigns all
label locations, then separately scans monotonic branch promotions, retaining
the source's old-size-on-promotion behavior and signed upper-word quirk.

Explicit opacity covers supplied expression/target/options, complete returned
assembly, normalized object words and retained descriptor queues. Per-word
opacity keeps object assembly whose original binary-file writes are disabled;
descriptor opacity retains construction despite disabled debug output. The
default timed executable does not enable optional complete word recording.
[Optimized-binary inspection](retained-work.json) locates fresh 40,000-byte virtual
table initialization inside the compilation loop and retains normalization,
purification, instruction emission, descriptors and object-word processing.

The checked domain includes the canonical program and the independent programs
above. Other targets/output options, tasks/futures, unsupported inline primitive
families and compound literal-object dumping fail explicitly. All 360 primitive
descriptions and 230 registration recipes remain present. Synthetic arithmetic
identity values and a cell's null helper argument emit direct typed immediates,
where the source interns late GVM operands; ordinary operands retain their
existing identities. This adaptation does not occur in the canonical program.

Fifteen focused native tests, the all-suite native checks, negative assembly
oracle, formatting and Wasm Clippy with warnings denied pass. The
[focused simplify review](simplify-review.json) records a fresh Sol 6.1 max
no-history/no-files explanation, informed critique and corrected behavioral
model. The resulting model matches the source; no runtime refactor was warranted.
Earlier GVM/block review remains separate.

```sh
cargo build --offline --release --target wasm32-wasip1 \
  --manifest-path benchmarks/wasm-reference/Cargo.toml --bin compiler \
  --example compiler_frontend
python3 benchmarks/wasm-reference/suite.py --benchmarks compiler --checks full \
  --output build/rust-compiler-reproduction
python3 benchmarks/wasm-reference/tests/compiler_assembly.py \
  --output build/compiler-assembly-reproduction
```
