# Compiler intermediate-stage checkpoint

Actual Node/Wasm agrees with the untouched original Chez compiler on complete
parsed, partially evaluated and normalized trees for the canonical program and
four independent programs: **15 intermediate comparisons pass**. The independent
programs cover recursive captured variables, mutually recursive procedures,
mutable captured parameters and constant/global bindings.

**The complete Compiler workload remains pending.** These probes process their
program once. They do not run the original 2,000 repetitions, generate assembly,
or replace the original exact assembly-list predicate. There are no performance
samples. GVM generation, register/stack contexts, basic-block purification/order,
slot analysis and 68000 emission remain to be ported.

[Validation](validation.json) records each complete serialized tree, actual
commands, diagnostics, and source/tool/binary hashes. [The archive](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-13-rust-compiler-frontend/artifacts.tar.xz)
freezes the Rust module, linked Wasm, original Chez programs/binaries, complete
inputs/results and oracle support. Its [manifest replay](archive.json) verifies
55 regular files. The original compiler functions are unchanged; private oracle
imports set Chez's extended-identifier printer around serialization so `##cell`
symbols remain literal. Bound names are compared with the reviewed lexical
alpha checker; free and quoted values retain their meaning.

The runtime source is SHA-256
`d4347c870b2908c374225940ca0ecb4ff9e827ba2b39642e08c2813178554cb0`;
the actual Wasm is
`c25b1fde4c6b47ca2ea8f3a86565c7d29bc6fa1b50c99d5392dc6139e056cbc0`.
Two native ownership tests verify ordered-set suffix sharing and shared mutable
variable roots between declaration frames. Formatting checks pass. The example
has deliberate unused-field/variant warnings while later stages are unfinished;
no completed full-suite or Clippy result is claimed for this module.

The Rust arena owns separately boxed syntax, variable, environment and parse
records; numeric IDs preserve parent/reference cycles. Linked identity sets copy
prefixes and share suffixes. Declaring an environment shares its mutable variable
root and persistent declaration tail. Rust retains obsolete records until a whole
compilation ends, while Scheme tracing collection can release them earlier.
Temporary traversal/maps and dependency-graph records use Rust vectors.
Fixed formals, checked declarations and canonical numbers are the probe domain;
other in-progress syntax paths fail explicitly. Long syntax/normalization
dispatches keep their contracts visible in one operation. Focused independent
review remains pending while the full compiler implementation continues.

Reproduce the linked intermediate checks with:

```sh
cargo build --offline --release --target wasm32-wasip1 \
  --manifest-path benchmarks/wasm-reference/Cargo.toml --example compiler_frontend
cargo test --offline --manifest-path benchmarks/wasm-reference/Cargo.toml \
  --example compiler_frontend
python3 benchmarks/wasm-reference/tests/compiler_frontend.py \
  --output build/compiler-frontend-reproduction
```
