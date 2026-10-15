# Compiler raw GVM checkpoint

Actual Node/Wasm agrees with original Chez on **nine complete raw instruction
graphs**: the canonical program once and eight independent programs. Each graph
includes every instruction, operand, procedure name/call pattern, complete
register/slot/closed/live frame, and local-variable identity. The independent
programs cover recursive and mutual procedures, captured mutation, indirect
operators, five arguments with stack arguments, rest parameters, short-circuit
values/predicates, and nested branch-context merges. All 15 frontend comparisons
also still pass. These validation durations are correctness evidence only.

**The full Compiler workload remains pending.** These diagnostics stop immediately
before basic-block purification. They do not run the original 2,000 repetitions,
emit 68000 assembly or apply the original complete assembly-list predicate.
Purification/order, slot analysis and genuine assembly emission remain in scope.
The private original oracle replaces only `bbs-purify!` with an explicit phase
stop, removes the final benchmark invocation, and adds complete graph printing;
all algorithms through raw GVM generation remain original. It is an intermediate
oracle, separate from eventual untouched original full-input validation.

[Validation](validation.json) records the complete outputs, input hashes, actual
commands and exact source/tool/binary hashes. [The archive](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-13-rust-compiler-gvm-raw/artifacts.tar.xz)
retains the Rust sources/catalogs, Wasm, original Chez source/binary, all inputs
and outputs, oracle support and check logs. [Manifest replay](archive.json)
verified 57 regular files. The raw GVM source is SHA-256
`0587b2d71049d111d567d72345df872bd0603b8a41a8d9438c07cac80cae26c5`;
the actual Wasm is
`391820af354c452166999549794fee49d25b6d52f097245b6bdfbb554edfd899`.

The complete 360 original primitive descriptors, 197 dialect/common procedure
descriptors and 230 registration recipes are retained. Specialization preserves
shared descriptor identity. Instruction/procedure/block records are separately
boxed; persistent frame/set lists copy prefixes and share tails. Mutable
association pairs and their list cells are separately allocated, so temporary
recursive procedure bindings retain and restore the same shared pair even after
new association prefixes are added. Register/slot transitions and polling follow
the source. Fixed-arity local jumps, general calls and closure work queues perform
their actual compiler work; no compiled result is cached.

Rust vectors/deques store temporary traversal and basic-block queues, and source
comments store located-source IDs rather than Scheme comment association lists.
The compilation arena retains obsolete records until compilation ends; Scheme
tracing collection may release them sooner. These allocation policies are
adaptations, and must remain visible in eventual timing interpretation. Three
special variable records are currently allocated per diagnostic compilation;
the original constructs them once at top level. No timing comparison uses this
unfinished diagnostic executable.

Five native tests include mutable association identity/restoration, ordered-set
tail sharing, declaration-root sharing and catalog specialization identity.
A negative oracle test rejects changed operands/destinations, changed frame
size/aliases and extra instructions. Formatting checks pass; deliberate unused
fields/variants remain while later stages are unfinished. Fresh focused simplify
and source review are pending. Long generator transitions keep their atomic
state/effect contracts together.

```sh
cargo build --offline --release --target wasm32-wasip1 \
  --manifest-path benchmarks/wasm-reference/Cargo.toml --example compiler_frontend
cargo test --offline --manifest-path benchmarks/wasm-reference/Cargo.toml \
  --example compiler_frontend
python3 benchmarks/wasm-reference/tests/compiler_gvm.py \
  --output build/compiler-gvm-reproduction
```
