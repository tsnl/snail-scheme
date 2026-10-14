# Share empty immutable constructors: full Ray comparison

Sharing zero-field data constructors reduces full Ray workload time by **25.1%
on V8** and **52.0% on native** in this matched comparison. Native and V8 are now
within about 2% of each other on this workload. These results do not establish
performance across the suite.

| Compiler / executor | Median workload seconds | Retained range | Median process seconds |
| --- | ---: | ---: | ---: |
| Baseline / V8 | 0.127367 | 0.126726–0.133636 | 0.151485 |
| Shared empty values / V8 | 0.095375 | 0.095143–0.095937 | 0.119572 |
| Baseline / native | 0.194123 | 0.193194–0.196023 | 0.196052 |
| Shared empty values / native | 0.093274 | 0.092838–0.094737 | 0.095308 |

Each median contains eight retained fresh-process observations. Every invocation
renders the original 100 × 100, 33-sphere scene 50 times. All 36 invocations,
including the excluded cycle, pass the complete 29,517-byte image comparison.
Candidate/baseline workload ratios are 0.748819 on V8 and 0.480487 on native;
process ratios are 0.789333 and 0.486136. Native/V8 workload ratios change from
1.524128 to 0.977972. The small final cross-host difference is descriptive.

## One compiler change

Baseline source is commit `71c6cfbe4ce1fede25b598578c611bfb3951b6b8`.
The implementation commit is recorded in `summary.json`. Of the 58 frozen
frontend source/helper files, only `strict-wasm.sld` changes. It emits one
private rooted global for each concrete zero-field case and uses `global.get`
at construction sites. Concrete nominal layout identities remain distinct
before Wasm structural canonicalization. The source constructor's operator
evaluation and binding initialization checks remain in place.

There is no runtime cache, second representation, source rewrite or LLVM-specific
optimization. Constructors with fields still evaluate and allocate normally;
explicit mutable cells and containers retain their identities. The original
baseline frontend snapshot, its hashes, exact source patch and build commands
are retained. The baseline Wasm was compiled before editing the emitter.

Both variants use identical Ray source, canonical inputs, Rust source/services,
C benchmark provider, native lowering, collector and tools. For each variant,
`scripts/build-native --wasm` runs mandatory Binaryen optimization. Its actual
`optimized.wasm` is also the input to the V8 Rust-runtime linker, which runs
its normal final Binaryen optimization. Both executors therefore receive each
variant's common optimized program; historical timing samples are not reused.
The provider is compiled separately without LTO, keeping input/barrier results
opaque to the guest optimizer.

| Artifact | Baseline SHA-256 | Candidate SHA-256 |
| --- | --- | --- |
| Common optimized Wasm | `9140eb850c16747ae558a603b95381908b82c3d67d9e634aa78c19a807455275` | `f331477b481932b9ee274fdefe87add40b731a423dec8e8aae65ac195463bda4` |
| Linked V8 Wasm | `7650bbf8856d413bd9e3c42936f6547c7910e3296cc58d746a6f01a0702f1062` | `3444c5ef8c0dfcf4d7309a607e4b80e6a7e0598d86c2527b9cffa2f70f9c92db` |
| Native executable | `30a568b5d10152d27ca70593da51d03ad0b3eba80ff821671088a9cdbd39c7a9` | `e0e03394dcf88426074a93b3eee58e836ae210efccf1ca7e56a764b141dc7f45` |

The native target is the validated 64-bit x86-64 Linux implementation with
precise nonmoving Immix, default 256-MiB virtual reservation and 8-MiB minimum
collection budget. Node 24.19.0 uses default V8 tiering; Binaryen is version 132
and Clang/LLD are 22.1.8. No GC policy or root-frame implementation changes.

## Separate allocation evidence

The exact native executables were run separately with the existing opt-in
`SNAIL_GC_STATS` flag. Both full images pass. These records include process
setup and cleanup, and their timings are excluded from the clean comparison.

| Process total | Baseline | Shared empty values |
| --- | ---: | ---: |
| Allocation requests | 34,992,393 | 2,302,993 |
| Requested payload bytes | 319,662,960 | 58,147,760 |
| Collections | 73 | 11 |

This establishes a large allocation reduction for the changed generated program.
The change also permits downstream optimization; these counters do not assign
all saved time to allocation, collection, or a particular constructor site.
They are native counts, not a measurement of V8 physical allocations. Private
global initialization and retention can move costs outside the workload clock;
the separately reported process clock includes initialization and shutdown.

## Timing and validation

One excluded four-way cycle precedes eight retained cyclic rotations, placing
every variant in every retained ordinal position twice. Each invocation uses
a fresh process and directory, empty `outputs/`, and logical CPU 5. The driver
clears Node instrumentation variables and native GC/test controls. There are
no profiler flags, replacement samples or outlier removal. All 212 frozen input,
source, artifact, helper and tool identities match before and after the campaign.

Both hosts initialize their runtime/module and call Scheme `main` before the
workload clock. Ray's original guest predicate checks its sentinel result `1`;
native checks that result and Node performs its result conversion/assertion
before stopping their respective clocks. Cleanup and JSON output follow.
The process clock encloses launch, captured output and reaping.

The driver persists every raw process outcome before validating it. The entire
final image is compared after process exit, outside both clocks, including
excluded invocations. Its SHA-256 is
`38babccc4583f44c18d17488314bffe9723a0fd2bdeff7227ec0d7ed1ea1463d`.
The source, opaque per-iteration inputs and observable file operations preserve
the complete 50-render workload. Separate V8 preflights also verify 100 workload
barrier calls and zero setup barriers. No current-artifact per-site allocation
census or additional file-event tracing is claimed.

Agent-controlled builds, tests, profiling, compression and replay were held.
The unrelated long-running Nucleic compiler was explicitly stopped for the
window and resumed afterward; its waiting wrapper did no compilation. Other
desktop/system activity and lightweight source/tool activity were uncontrolled.
CPU affinity does not reserve the core, and fresh directories do not imply cold
caches. Environment removal rules, rather than the whole inherited environment,
are recorded. Eight samples support a bounded descriptive comparison.

All 48 datatype compiler contracts pass on raw and optimized Wasm. New cases
exercise first-class empty constructors, effects before alias-readiness traps,
distinct nominal/generic `Top` checks, and independent mutable cells. The native
suite executes 198 recorded commands, including forced-GC fixtures. Linked raw
and optimized I/O tests, `make test`, `make check`, offline Rust tests, Rust
format checks, `scripts/test-backend` and `scripts/test-build` all pass.
`checks.json` and archived raw logs retain those outcomes. The focused independent
implementation and measurement reviews are summarized in `review.md`.

## Evidence and replay

`clean.json`, `freeze.json`, `summary.json`, `statistics.json` and
`source-comparison.json` preserve the raw observations and comparison basis.
`artifacts.tar.xz` and `manifest.json` preserve exact programs, compiler sources,
providers, build records, complete images and validation logs. External tools
remain pinned dependencies with recorded hashes.

```sh
python3 benchmarks/strict-suite/replay.py /tmp/empty-variant-ray-replay \
  --report benchmarks/results/2026-10-14-empty-variant-ray
```

The replay plan supplies the four relocated full-count commands. Use a fresh
directory with empty `outputs/` for each invocation. Replay timings are correctness
evidence only; any new timing campaign needs a new coordinated quiet window.
`replay-check.json` records all four actual relocated executions passing the
complete image check, after restoration verified all 596 archived files and
the 17 pinned external dependencies were checked.
