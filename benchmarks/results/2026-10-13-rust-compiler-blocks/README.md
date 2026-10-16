# Compiler block and slot checkpoint

**All 26 complete linked comparisons pass** in actual Node/Wasm and original Chez:
raw and fully purified GVM for the canonical program once and twelve independent
programs. Each comparison includes the numeric operand encodings, every
instruction, complete register/slot/closed/live frames and procedure metadata.
Purified comparisons also check every backward stack-slot requirement. The
canonical graph changes from 71 blocks/247 instructions to 38 blocks/181
instructions, exactly matching original cascade removal, reachability, hashed
common-block/tail merging, jump merging, scheduling and label rewriting.

**The complete Compiler benchmark remains pending.** The original 2,000
repetitions, genuine 68000/object assembly and exact complete assembly-list
predicate remain to be implemented and validated. These observations are
one-pass intermediate correctness checks, with no performance claims. The
original raw oracle explicitly stops purification; the purified oracle runs the
original compiler algorithms unchanged through complete slot analysis. Both
add private complete graph serialization in place of the final benchmark call.

[Validation](validation.json) retains complete outputs, actual commands and
source/tool/binary hashes. [The archive](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-13-rust-compiler-blocks/artifacts.tar.xz) freezes both compiler
stages, all source catalogs, Wasm, original Chez programs/binaries, complete
inputs/outputs, oracle support and check logs. [Manifest replay](archive.json)
verifies every retained regular file. Historical frontend/raw archives remain
unchanged. Current hashes are also recorded in the suite checkpoint.

The stricter operand-encoding audit detected a source evaluation-order detail:
Chez evaluates a global copy's destination before its effectful source. The
Rust generator now interns that destination first, so both the operand meanings
and the numeric encodings used in common-block hashing agree. Complete local
identity serialization checks sharing and aliases independently of generated
variable names; globals and literal values stay exact. Adversarial oracle probes
reject changed operands, destinations, frame sizes, aliases and extra instructions.

The separate block module exposes the original purification fixed point and
backward slot analysis. Hash buckets, label associations and ordered identity
sets retain persistent list tails; mutable association pairs keep stable identity.
Truncated frames share their surviving slot suffix. Rust vectors/deques store
code/traversal queues, and separately boxed code records retain per-instruction
slot requirements. Rust retains obsolete graph/record objects until compilation
ends, while Scheme tracing collection may release them earlier. These allocation
adaptations remain explicit; source comments still store located-source IDs.

Seven native tests pass, including slot destinations consumed before operands,
closure-base slot requirements and frame suffix sharing. Formatting and the
negative graph-oracle test pass. Deliberate unused fields/variants remain while
assembly emission is unfinished; no Clippy/full-workload pass is claimed for
this diagnostic module. A [supplemental simplify review](simplify-review.json)
records the fresh no-history explanation, informed debate and source comparison.
The resulting comment/two-test changes leave the release Wasm code and every
non-data section byte-identical to the frozen 26-comparison artifact. The
[decoded section proof](simplify-section-proof.json) verifies that the only
data changes are panic-location source line numbers shifted by the new comments.
The reviewed binary is retained separately. Nine native tests now pass. The refined
model warranted no runtime refactor; whole Compiler/frontend/emitter review
remains separate and pending.

```sh
cargo build --offline --release --target wasm32-wasip1 \
  --manifest-path benchmarks/wasm-reference/Cargo.toml --example compiler_frontend
cargo test --offline --manifest-path benchmarks/wasm-reference/Cargo.toml \
  --example compiler_frontend
python3 benchmarks/wasm-reference/tests/compiler_gvm.py \
  --output build/compiler-blocks-reproduction
```
