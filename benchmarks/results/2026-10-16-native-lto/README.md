# Native optimization across the Rust boundary

The native executable already statically links the Rust runtime. This experiment
keeps the generated guest in LLVM bitcode until the final Rust link, allowing
linker-plugin fat LTO to optimize the guest, runtime and real providers together.
The previous path emitted guest machine code before that link. Saved ELF objects
remain supported and retain their existing meaning.

The six-case comparison finds substantial wins, but also a **35% array
regression**. This is experimental evidence for the link change, not a claim
that the candidate is ready to become the default. The regression is under
investigation.

## Six-case comparison

All **288 scheduled executions passed**, including 48 warmups and 240 measured
fresh processes. Three unavailable adapted-Chez rows remain explicit in the
51-row report. Median guest seconds:

| Workload | Current native | Matched native | Shared LTO | V8 | LTO / V8 |
| --- | ---: | ---: | ---: | ---: | ---: |
| fib | 3.189535 | 3.194275 | 1.295187 | 2.094581 | 0.618 |
| fibfp | 0.580911 | 0.580896 | 0.231502 | 0.382525 | 0.605 |
| mbrot | 0.722875 | 0.729078 | 0.479080 | 0.289262 | 1.656 |
| array1 | 3.280763 | 3.311040 | 4.473097 | 5.435680 | 0.823 |
| bv2string | 0.600575 | 0.592913 | 0.415668 | 0.374031 | 1.111 |
| gcbench | 3.982164 | 4.011204 | 3.894414 | 1.428305 | 2.727 |

The last column is elapsed-time ratio: below one favors native. LTO reduces
matched native time by 59.5% for `fib`, 60.1% for `fibfp`, 34.3% for `mbrot`,
29.9% for `bv2string`, and 2.9% for `gcbench`. It increases `array1` time by
35.1%, with clearly separated sample ranges (3.295–3.321 versus 4.469–4.475
seconds). Being faster than V8 on that case does not excuse the regression.

The contemporaneous external controls are:

| Workload | Chez original | Chez adapted | Rust / Wasm | Rust / native |
| --- | ---: | ---: | ---: | ---: |
| fib | 1.334578 | unavailable | 0.658307 | 0.731087 |
| fibfp | 0.851465 | unavailable | 0.228443 | 0.231843 |
| mbrot | 2.225327 | 2.222569 | 0.362327 | 0.219521 |
| array1 | 6.798893 | unavailable | 0.316705 | 2.401186 |
| bv2string | 0.464705 | 0.466649 | 0.043059 | 0.026317 |
| gcbench | 0.385262 | 0.828760 | 0.696752 | 0.569173 |

[comparison.json](comparison.json) retains every sample, range and median for
all arms. Rust and Chez are independent implementations of the workload; these
ratios do not isolate the cost of any individual language feature.

Two additional ablations were included in the fixed schedule:

- Preserving final Wasm type information reduces `bv2string` from 0.412150 to
  0.391922 seconds against its own LTO control, a 4.9% reduction. Sample ranges
  do not overlap (0.409548–0.412775 versus 0.389710–0.396724). This prototype
  remains 4.8% slower than V8. It changes 12 reference-test flags; open targets
  and nullability remain intact.
- Avoiding redundant zero fill reduces non-LTO `array1` from 3.280763 to
  3.018407 seconds, 8.0%. This does not establish its effect when combined with
  LTO, or explain the LTO regression.

## First controlled ablation

The initial `bv2string` pilot uses the unchanged canonical input: 100 outer
iterations, each with a short round trip and 1,000 pseudorandom ASCII bytevector
round trips, maximum length 1,000. One warmup and five measured fresh processes
per arm all passed the complete predicate. Median guest seconds:

| Arm | Median | Minimum | Maximum |
| --- | ---: | ---: | ---: |
| Current native build | 0.599857 | 0.599286 | 0.603203 |
| Omit empty root frames | 0.593897 | 0.589246 | 0.634607 |
| Omit redundant zero fill | 0.602943 | 0.598579 | 0.605834 |
| Matched machine-code guest | 0.592562 | 0.588411 | 0.593463 |
| Matched shared-LTO guest | 0.425286 | 0.420035 | 0.426676 |
| V8 | 0.373211 | 0.371037 | 0.373731 |

Shared LTO reduces time by **28.2%** against its matched control, leaving native
**14.0% slower than V8** on this workload. Omitting empty root frames and omitting
redundant zero fill do not establish useful gains here. LTO already removes
calls whose root-frame capacity is zero; required root bookkeeping remains.

## Experimental boundaries

All sources originate at `313cec8752b1fcd3b7a2577f3fc65b96ea1b9dd3`, including
the landed UTF-8 representation and compiler-host map changes. The fresh freeze
is `/tmp/sfir-native-parity-baseline-20261016`. Native lowering consumes exactly
the same Binaryen-optimized guest Wasm as V8. Workloads, inputs, validation
predicates and previously frozen evidence are unchanged.

An initial exploratory link exposed benchmark input constants and identity hide
functions to LTO. Such builds are excluded from clean performance claims. The
measured native pairs use identical benchmark-only Rust trampolines, compiled to
machine code without embedded bitcode. The original provider sources remain
unchanged. Each trampoline forwards to its original provider symbol; the extra
tail jump is common to both native arms. Only the guest artifact changes from
machine code to bitcode. The ordinary current native build is retained as an
additional control because it lacks that extra jump. Runtime and ordinary
product-provider functions remain visible to shared LTO.

Instrumented validation is separate from timing. Complete predicates, expected
hook counts, and retained post-LTO IR and assembly establish different facts:
correct results, hook execution, and survival of the intended workload. Hook
counts alone do not establish retained computation. In particular, the integer
and floating Fibonacci loops retain their recursive work, including both
recursive calls and addition inside the worker.

The scalar pilot contains two opaque hooks. The subsequent six-case comparison
uses all 18 benchmark provider hooks behind the same machine boundary for each
paired build. The final-type ablation has its own matched LTO control and must
be compared with that control, rather than assumed byte-identical to another
build.

## Remaining-cost diagnostics

Hardware-cycle sampling of the LTO `bv2string` binary is diagnostic evidence,
not clean timing. Random-number generation, its wrapper and bytevector filling
dominate. Collector allocation and sweep functions account for about 1.2% and
0.7% of self samples respectively; these are not exact total GC durations.
UTF-8 scanning accounts for about 10.5%, while bulk copying accounts for about
0.2%. The native profile therefore does not justify attributing this workload's
remaining gap primarily to the collector.

V8's retained optimized code shows a predicted indirect-call target converted
to a guarded direct call. Native code retains additional calls and reloads.
This motivates preserving more Wasm type and alias facts during mechanical
lowering. It does not establish how much any unimplemented optimization saves.
The measured final-type experiment changes only reference tests whose resolved
Wasm target cannot have subtypes; open targets and nullability remain unchanged.

## Protocol and limits

The selected workloads are `fib`, `fibfp`, `mbrot`, `array1`, `bv2string` and
`gcbench`. These exercise recursive scalar computation, floating arithmetic,
arrays, strings and allocation. They are a targeted subset of the complete
57-workload corpus, not a whole-suite parity claim.

Runs use CPU 2, one warmup and five measured fresh processes per eligible arm.
Case order rotates by round, and each case's arm order rotates as well. Every
scheduled attempt is retained; failures are not replaced. Guest monotonic
timers cover the repeated workload and complete final predicate. Preparation,
compilation, process startup and final cleanup are outside the timer. V8 tiering
during guest execution remains included.

All task-owned builds, tests and profiling were held during clean timing. Host
process observations are retained before and after. Ambient desktop processes
remain, so this is not an exhaustive machine-wide quiet assertion. Small effects
need to be assessed against the retained ranges and matched controls.

The exploratory GCbench LTO build has a Cargo log reporting about two minutes,
but its process record also contains an `EPERM` spawn anomaly. The resulting
binary passed supervised execution. That record is preliminary build-cost
evidence, not a clean compilation-time measurement.

## Retained evidence

[evidence.tar.gz](evidence.tar.gz) contains the pilot and six-case measurement
drivers, fixed plans, every attempt's supervised process record and output,
the preparation manifest and validation, prototype build records and providers,
selected complete guest-function IR and assembly, and the diagnostic profile
summaries discussed above. `evidence-files.sha256` verifies its 3,240 retained
files. Absolute paths identify the original isolated worktrees; executables,
Cargo targets, full toolchains and full post-LTO modules are not embedded.
Their hashes and build commands remain in the records. The archived `archive.scm`
states exactly which evidence was selected.

The fresh preparation uses base `313cec8752b1fcd3b7a2577f3fc65b96ea1b9dd3`.
The native prototype changes are retained as patches against that base:

| Experiment | Source revision | Patch |
| --- | --- | --- |
| Shared LTO | `cf411e298a3067ae2321e4b13475d424e7774082` | [shared-lto.patch](shared-lto.patch) |
| Empty root frames | `c0f29d24e6d3f702099c95113b3ee607151fc97a` | [empty-roots.patch](empty-roots.patch) |
| Redundant zero fill | `ed23cb3cb61149185e0da0d04f12cabcfa59ef21` | [zero-fill.patch](zero-fill.patch) |

The patches omit context lines; use `git apply --unidiff-zero` in an isolated
checkout of the stated base to reproduce an individual prototype.

The final-type experiment modifies generated LLVM only; its type proof, exact
changed-call list, build commands and validation are under
`prototypes/final-types/`. Build metadata saying `not-measured` predates the
parent-owned clean campaign; `six/measurement.json` records those subsequent
measurements against the same executable hashes. Throwaway JavaScript prototype
helpers are retained as experimental provenance, not installed product tooling.

The host was x86-64 Linux on an Intel Core Ultra 7 270K Plus, with Node 24.19.0,
Binaryen 132, Chez 10.4.1, Rust 1.95/LLVM 22.1.2 and system LLVM 22.1.8.
The frozen machine record contains the full tool and CPU observations. Node's
pointer-compression setting was disabled. [SHA256SUMS](SHA256SUMS) covers this
report, comparison, patches and archive.
