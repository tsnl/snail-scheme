# Reusing the current environment for lexical self calls

On the canonical `array1` workload, replacing a redundant self-closure environment
load improves ordinary native, shared-LTO native, and V8 execution. The shared-LTO
variant now takes less time than ordinary native execution, resolving the array
regression seen in the [earlier LTO experiment](../2026-10-16-native-lto/README.md).
This report measures an isolated emitter change; it does not enable shared LTO
in the product or change the native collector.

These are **uninstrumented exploratory timings**. All task-owned heavy jobs were
held, but unrelated Chibi and Rust compiler jobs were visible on the same host.
Before/after process snapshots are retained. The large effect is consistent
across the five rotated samples; these runs do not establish small performance
differences or whole-suite parity.

| Execution | Control median (range), seconds | Self environment median (range), seconds | Time reduction |
| --- | --- | --- | --- |
| Native, machine object | 3.085972 (3.062461–3.139759) | 2.174309 (2.169606–2.217095) | 29.5% |
| Native, shared LLVM LTO | 3.875772 (3.806311–3.990319) | 1.331117 (1.311177–1.341343) | 65.7% |
| V8 | 5.642478 (5.626115–5.736065) | 3.462507 (3.387456–3.562177) | 38.6% |

The candidate LTO executable takes 38.8% less time than the candidate ordinary
native executable and 61.6% less than the candidate V8 module in this comparison.
Every execution passes the original final predicate. One warmup and five fresh
measured processes per arm produce 36 retained attempts, with no failed or
replacement samples. All runs use CPU 2. Compilation, process startup and cleanup
are outside the workload timer; V8 tiering inside the workload remains included.

## What changed

The emitter already knows the target of a direct recursive call, but previously
loaded its environment through the binding cell and closure on every iteration.
The candidate passes the current environment when the operator is the exact
lexical self binding. It requires both the enclosing concrete implementation ID
and that binding's complete literal-lambda initializer to match. Function request
keys include the concrete binding instance, so shared syntax nodes alone cannot
establish this identity. Separate factory activations retain their own cells and
environments; aliases, computed initializers and nested owners do not qualify.

The operator still executes after the arguments, with the original readiness and
payload non-null checks. Its fresh held local cannot change before invocation,
so the additional assertion on that same local is redundant when the environment
load is removed. This does not remove closure allocation, change capture, or add
a runtime equality test. Native lowering receives ordinary optimized Wasm.

Raw-Wasm comparison finds exactly nine environment substitutions in `array1` and
no other expression changes. Final LTO IR and machine code retain the complete
array initialization and copying loops. Their former loop-carried environment
dependency is absent. Both optimized-Wasm arms observe the original two opaque
input barriers; all three static opaque-call sites remain in each native binary.
The third static site is a separate helper, not an additional observed barrier.

## Fixed inputs and provenance

The baseline is `0a765e72375a07c521c404e5a95b3688c265956b`; the prototype commit is
`c3155b165c0dafdd30097b11cfcf765341ed4249`. All four native executables use the same
baseline Rust runtime, provider, entry, configuration and opaque boundary object.
Only the emitter changes between control and candidate. Machine-object and
shared-LTO builds retain their separate commands and final disassembly. These
experiments use the earlier opaque object boundary. The Rust `black_box` variant
of the benchmark harness remains on the unlanded LTO branch.

The unchanged source uses count 1, inputs `[500, 1000000]` and expected result
1000000: 500 complete array creation/copy iterations. The exact workload,
configuration and input are archived. V8 and both native modes consume the same
Binaryen-optimized guest for each arm:

| Arm | Optimized Wasm SHA-256 |
| --- | --- |
| Control | `232431e37c25c9ba1b5466568b77192127fc3e643bf1892ae707f6cb79c4af95` |
| Candidate | `134befc1c8bfd72766c6f983c2522a2d233e067b295bf3105ca94beefa790821` |

The control matches the earlier frozen six-case guest. A comment-only edit after
prototype compilation is documented in `probe/compiler-provenance.json`; the
exact compiled source snapshot is retained separately. Product commit
`18b3325ce9b571ca8420dfe9b65bd29f5e8927b1`, based on main after the collector
field-layout change, emits byte-identical candidate optimized Wasm. This equality
does not substitute for that product commit's separate correctness validation.

## Evidence and checks

[comparison.json](comparison.json) retains every attempt, sample, range and
median. [evidence.tar.gz](evidence.tar.gz) contains the fixed plan and driver,
commands and process records, source snapshots and patch, correctness probes,
raw/optimized Wasm text, relevant LLVM IR, final disassembly and host observations.
`evidence-files.sha256` verifies 728 retained files. The large whole-program
pre/post-LTO IR files remain hashed in the frozen manifest and available locally;
the archive includes the relevant function IR and complete final disassembly.
[SHA256SUMS](SHA256SUMS)
covers the published report and archive. Build/runtime environment entries use
an explicit allowlist; host observations omit unrelated command arguments.
Filtering is documented with original-record hashes,
and the original local records remain unchanged.

The prototype also passes 18 focused control/candidate V8 checks and eight actual
native contract executions spanning ordinary/shared-LTO linking and forced GC
before every allocation. These exercise distinct captured factory activations,
aliases, nested calls, tail and non-tail recursion, separate polymorphic
instances, early-read traps and argument ordering. A public-library probe retains
one shared lambda node in two bindings and confirms distinct concrete IDs.
Earlier failed fixture/import attempts are retained. The independent proof
review and permanent product tests accompany the implementation change.

Product validation passes `make test`, `make check`, all 29 ordered
`scripts/test-backend` components (including all 323 integration cases), all 255
checked commands in `scripts/test-native`, and all 35 checked commands in
`scripts/test-build`. These suites include linked Wasm, actual saved-ELF loading
and native execution, expected traps, and forced GC. The public shared-lambda
probe returns 42, and raw-Wasm comparisons for both `array1` and the focused
fixture permit only the nine intended environment substitutions. This
correctness validation is separate from the exploratory timings above.
