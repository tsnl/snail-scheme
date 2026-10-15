# Compiler assembler checkpoint

All five complete assembler diagnostics agree in actual Node/Wasm and original
Chez. They compare every assembly line, emitted object word and shared label
descriptor position, including empty code, zero-distance/long branch promotion,
forward/backward relocations, alignment, signed words and symbol/procedure
records. All 26 complete raw/purified GVM and backward-slot comparisons also pass
with this exact linked binary. These are intermediate correctness checks; the
full Compiler workload and its unchanged 2,000 iterations remain pending.

[Validation](validation.json) retains actual commands, complete outputs and
source/tool/binary hashes. [GVM regression](gvm-regression.json) checks the
earlier stages with the same emitter-enabled executable. The
[archive](artifacts.tar.xz) freezes sources, catalogs, original Chez oracles and
binaries, Wasm, inputs, complete outputs and check logs. Its
[replay manifest](archive.json) verifies every archived regular file. Historical
frontend/GVM/block artifacts remain unchanged.

The assembler retains the source symbol tables, object queue, compact 68000
operand encoding, alignment records, shared mutable label locations, relative
references and monotonic branch tensioning. A promoted branch advances its old
short length until the following location pass, as the original does. The
original signed `upper-16bits` quirk remains explicit and tested. Assembly text
uses owned buffers and code-part arenas in place of Scheme cons/reverse queues;
the full assembler graph lives until compilation ends. Rust reference counting
and arena lifetimes differ from Scheme collection.

The original binary-file word writes are disabled. Rust explicitly applies
`black_box` to each normalized object word to retain otherwise unobservable
object assembly. This additional opacity is documented separately from the
optional diagnostic word audit. No complete-result validation is added inside
a timed workload, and no performance observations are claimed here. High-level
GVM-to-68000 opcode and primitive emission remains to be completed.

Twelve native tests pass. The negative oracle rejects changed assembly lines,
object words, label positions and extra words; formatting passes. Deliberate
unused emitter fields remain while high-level generation is pending, so no
Clippy or full-workload success is claimed for this diagnostic checkpoint.

```sh
cargo build --offline --release --target wasm32-wasip1 \
  --manifest-path benchmarks/wasm-reference/Cargo.toml --example compiler_frontend
cargo test --offline --manifest-path benchmarks/wasm-reference/Cargo.toml \
  --example compiler_frontend
python3 benchmarks/wasm-reference/tests/compiler_asm.py \
  --output build/compiler-assembler-reproduction
```
