# Complete compiler workload

`main.sfir` retains all 1,343 kernel forms from the upstream compiler, including
the frontend, optimization passes, virtual machine representation, register
allocation and target assembly generation. `source-coverage.json` records the
original 1,345 forms, with only the import and benchmark driver replaced. The
canonical input still requests 2,000 compilations for `m68000` with the `asm`
option. Correctness compares all 497 expected assembly strings.

This compiler is itself benchmark code. The product compiler reads its ordinary
static SFIR source; preparation and execution do not invoke a Scheme expander,
converter or host evaluator. The benchmark's own parsing, transformation and
code-generation work remains inside the repeated worker.

The local `Value` variant represents the original heterogeneous data. Pair links
are explicit mutable cells, vectors have a fixed element type, and every closure
case has a concrete signature. Exact numbers retain the Integer/Rational/Number
libraries. Source binding cells preserve mutual scope and initialization order.
The adapted Chez control retains these tags and checks to expose any source
adaptation costs while running the full algorithm. Original Chez uses its native
Scheme representation and remains a separate comparison.

The source uses `call/cc` for active compiler error handlers. `CompilerResult`
represents a normal value or an abort carrying the identity of its target handler.
An abort skips pending operands, assignments and later sequence expressions until
the matching capture catches it. Source handler installation and restoration stay
in their original order. Returning ordinary false is distinct from aborting.
Assignment success carries the source's unspecified Value, since the typed cell
operation itself returns Unit. `initialization-migration.json` lists the 1,268
ordinary-RHS initialization sites corrected at this boundary in both SFIR and
adapted Chez; already explicit aborting-RHS branches retain their control flow.

`escape-summary.json` records the closed call-graph analysis used during authoring.
It leaves 638 raw source functions returning ordinary Value and gives the other
755 an explicit CompilerResult. Indirect calls and callback primitives retain
the result protocol. Converting a proven ordinary function to a first-class
procedure wraps its successful result at that boundary. This analysis is not a
product compiler feature or a runtime fallback.

The focused simplify review used a fresh independent explanation without file
access, followed by critique of handler identity, nested escapes, ordering and
callback propagation. The source audit established that handler handles neither
escape their active scope nor receive multiple values. General continuation
machinery would add behavior this closed program does not require. Extending those
source uses would require a new control representation or proof. The Value/graph
layer also received an independent explanation and critique. A fresh no-files
initialization review checked exactly-once writes, aliases, nested RHS failures,
and earlier effects surviving an abort. Its targeted positive regression runs
on raw/optimized Wasm and native; the original Unit-as-Value form is rejected.

`probes.scm` adds 15 untimed control observations. `observe` combines those with
real internal-error and limit-error reporters, five malformed compiler inputs,
and a complete successful compilation after every reporter/error case. All 22
observations match the original Chez observer, including its complete diagnostics,
mutation trace, handler restoration and all 497 recovery assembly lines. The two
operand-order probes explicitly choose the same permitted left-to-right order in
the original observer. `chez-original.scm` remains unchanged.

`verify.mjs` runs those observations and the complete canonical worker on V8;
`native-entry.rs` supplies the corresponding native invocation. Each accepts a
separate `fatal` invocation that must exit unsuccessfully through the initial
handler. The runner requires exit 1, the exact source diagnostic, and the expected
runtime error; signals or a returning handler cannot pass. The current directory
supplies `input.txt`, `error-inputs.scm`, and
`expected-observations.txt`. Diagnostics are outside the benchmark's worker loop.

The one-off surface migration preserves all numeric tokens.
`literal-migration.json` maps all 2,550 literals to their checked old source
locations; 2,515 explicit I64 annotations preserve their representations under
the current I32 default. The remaining 35 literals are F64. The complete current
typed inventory matches every old representation and target value. These
authoring tools are outside preparation and execution.

Original and adapted Chez passed the complete 2,000-compile workload and all 22
observations. Both Rust routes passed the canonical workload. SFIR passed the
same workload and observations on optimized Wasm and native using the pinned
`3b084776` compiler snapshot, with identical optimized guest bytes. Both target
fatal-handler checks exited through the expected diagnostic. A separate public
`scripts/build-sfir` replay produced byte-identical raw and optimized Wasm,
confirming the inventory walk did not change compilation. Later compiler revisions
need separate evidence.

The retained fourth historical draft attempt diagnosed the Unit/Value authoring
error. The first current frozen build lost its terminal session during
coordination; its exit status is explicitly unknown. The identical-source restart
completed successfully. The focused initialization regressions supplement the
full canonical execution. No timing claim is made from these concurrent
correctness attempts.

Upstream algorithm functions and coherent exhaustive dispatch may exceed the
repository's ten-line target. Their source identities and representation/control
boundaries remain visible instead of splitting them into numbered fragments.

To reproduce all six correctness routes from a fresh freeze:

```sh
chibi-scheme -I src -I benchmarks benchmarks/sfir/runner.scm prepare --benchmarks compiler \
  --output /tmp/sfir-compiler --compile-timeout 7200 --run-timeout 1800
chibi-scheme -I src -I benchmarks benchmarks/sfir/runner.scm validate --output /tmp/sfir-compiler
```

The explicit timeout accommodates the complete source; it does not reduce the
canonical workload. Validation and compiler traces are not timing samples.
