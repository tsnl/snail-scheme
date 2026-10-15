# Identical optimized guest Wasm for native benchmarks

All nine checked workloads now pass native execution from optimized guest Wasm
that is byte-identical to V8's program. This includes Pi's complete decimal
output, Primes, and GCBench's previously timed-out native route. The six timing
cases also pass their separate native timing entries, giving 15 checked native
builds. These were correctness runs; no new timing samples were collected.

The runner supplies the retained raw compiler output to the native helper.
The helper still performs mandatory Binaryen optimization, then lowers to LLVM.
Before accepting the executable, the runner checks the actual native build
manifest's raw-input, optimized-output, LLVM and executable identities and
compares optimized guest bytes directly with V8's program. Missing raw input,
changed artifacts, multiple build attempts or differing optimized bytes prevent
acceptance. Clean timing preparation copies the raw sidecar, repeats this check
for its separate executable and preserves the proof in its frozen plan.

| Workload | Correctness native | Clean-entry native | Shared optimized guest size |
| --- | --- | --- | ---: |
| Ack | Passed | Passed | 1,171 B |
| Fibfp | Passed | Passed | 69,785 B |
| Cat | Passed | Passed | 49,207 B |
| WC | Passed | Passed | 56,531 B |
| CTAK | Passed | Passed | 1,599 B |
| FIBC | Passed | Passed | 1,879 B |
| Pi | Passed | Not prepared | 19,417 B |
| Primes | Passed | Not prepared | 3,334 B |
| GCBench | Passed | Not prepared | 22,424 B |

The equality concerns the guest program. Wasm and native retain their separate
runtime providers and execution hosts. Every new executable passed its full
canonical result and observation predicates. Both original and adapted Chez
controls remain separate; all present controls and Rust routes passed except
the retained default Rust Wasm Ack stack failure. The six-case plan contains
33 ready routes, two unavailable adapted controls and that failed Rust route.

## Frozen checks and retained evidence

The [machine-readable report](20261015-native-parity.json) records both complete
campaigns, all 15 parity proofs, exact artifacts, actual build configurations
and the six-case timing plan. The [record archive](20261015-native-parity-records.jsonl.gz)
contains 206 terminal process records and 15 native build manifests. Both full
preparation manifests are archived with exact hashes:

- [Six-case preparation](20261015-native-parity-six-manifest.json.gz), frozen at
  `e3c464d2d79c528df6a93a5a311f39e5ee84e833` before the scalar-runtime cleanup.
  Session 59928 exited 0, chunk `2c9141`. Its clean-entry checks are correctness
  evidence only; no measurement campaign was started.
- [Pi/Primes/GCBench preparation](20261015-native-parity-extra-manifest.json.gz),
  frozen at `dd99e5df4e6d28b8abbed4868f5653f94057b341` after the scalar-runtime
  cleanup. Session 80752 exited 0, chunk `e3db13`. All six routes pass for each
  case.

Full frozen source/input/tool/build-dependency verification passed after both
campaigns terminated. Every native proof was then checked again against its
retained artifacts and native build manifest. Twenty runner/timing tests cover
freeze and process behavior, missing raw input, a deliberately different native
optimized module, replaced executable evidence, ambiguous attempts and rejected
timing eligibility. No compiler or native-helper interface changed.

## Earlier attempts remain unchanged

The [original 41-case campaign](20261015-existing41.md) remains intact, including
GCBench's 1,800-second native build timeout and the expanded second-pass Wasm
and LLVM artifacts. The new one-pass build retains a 2,417,320-byte GCBench LLVM
module, compared with the earlier 111,616,338 bytes. Primes now retains 143,673
LLVM bytes, compared with 41,857,797 bytes earlier. These are artifact sizes,
not clean performance comparisons.

The corpus now has canonical correctness evidence for all 53 authored programs
on both SFIR targets. Nine have the additional optimized-program parity proof;
the other retained native validations used the earlier pipeline. Four ports
remain pending in this checkpoint. Only the original six cases have performance
measurements, whose [second-optimization caveat](20261015-native-optimization-audit.json)
continues to apply. Fresh performance runs require a new latest-main freeze
and a coordinated quiet interval.
