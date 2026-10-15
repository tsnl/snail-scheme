# Complete Ray comparison

| Variant | Median seconds | Range |
| --- | ---: | ---: |
| Strict Snail on V8 | 0.128911 | 0.127927–0.131207 |
| Original Chez | 0.848783 | 0.846462–0.849886 |
| Adapted-source Chez | 0.796802 | 0.791982–0.798219 |
| Rust/Wasm | 0.053999 | 0.053751–0.054236 |

Strict Snail runs this workload 6.584× faster than original Chez and 6.181×
faster than the adapted source on Chez. Rust/Wasm is 2.387× faster than Snail.
All four implementations perform the original 50 complete 100 × 100 renders,
rebuilding the 33-sphere scene and formatting every output pixel each time.
These are four retained process observations per implementation, each containing
50 renders; the renders are not independent timing samples.

## Source and retained work

The [strict preparation](../2026-10-14-strict-ray/README.md) preserves sphere
construction/traversal order, negative roots, Euclidean hit distances, shading,
ties-to-even rounding, and all image bytes. Concrete Point/Sphere products,
optional root/candidate variants, Hit objects and a world-list Ref replace the
original generic Scheme vectors, false values and mutable world binding. The
adapted Chez control shares that typed kernel and its explicit Scheme decimal
formatter, with the documented tagged wrappers. Original Chez remains unchanged.

The frozen compiler/runtime source basis is
`053a8d85860be536095247e3217db60c45908a70`. All 70 files are retained. The
strict artifact is linked with the scalar Rust I/O provider and optimized with
Binaryen before execution. Its SHA-256 is
`c0fbff207e707c2de1aa17c063f9f81ecf06b6ba09fa326de5c268b65e8d65ab`.

Separate observation of the exact optimized Wasm establishes all 500,000
pixel/round operations, 16.5 million sphere visits, and 1,650 scene-sphere
constructor sites at count 50. The instrumented form is never timed. These
are executed Wasm sites, not physical V8 allocation counts. Separate file
lifecycle diagnostics establish 50 opens, 49 deletions and 50 closes. The final
image check by itself would not establish that the first 49 renders survived.

The [corrected Rust handoff](../2026-10-14-rust-ray-handoff/README.md) preserves
the same canonical finite-scene algorithm and exact false/`ok` result predicate.
Its contiguous `Vec<Sphere>`, inline points and optional temporaries differ from
the Scheme representations. Rust drops its owned scene inside each invocation;
Scheme's final world remains reachable after the clock. Rust also hoists
ray-invariant arithmetic. Those differences are retained and documented, so
this comparison does not isolate GC, foreign-call, representation or language
costs. The corrected artifact SHA-256 is
`e66e1b8a221250c113073e9336b5247722de7484464c77963ce9d6d3b61bb081`.
Its predecessor and original observations remain in the handoff report.

## Timing and validation

All 20 executions pass: one discarded round followed by four retained cyclic
rotations. Each implementation appears once in each retained ordinal position.
Agent-controlled builds, tests and other workloads were paused. Every process
ran on logical CPU 5, on the recorded Intel Core Ultra 7 270K Plus machine.
Unrelated system activity and ordinary filesystem cache effects remain possible;
fresh processes do not imply cold disks or caches.

The driver uses Node 24.19.0 / V8 13.6.233.17-node.51 and Chez 10.4.1. It clears
Node options, coverage and debugging variables, suppresses Node's experimental
WASI warning, and adds no JIT, profiler or counter flags. Each trial has a fresh
working directory with `outputs/` present and `outputs/ray.output` absent.
The original input bytes and pathname remain unchanged. All other paths are
absolute; working-directory relocation changes only the output destination.

Input/expected decoding, process startup and module initialization precede the
program clock. Scene construction, all renders, formatting, file deletion,
creation, writing and normal closing, and the original final predicate occur
inside it. Strict terminal resource cleanup and complete image validation occur
afterward. All implementations produce the same 29,517-byte PGM, SHA-256
`38babccc4583f44c18d17488314bffe9723a0fd2bdeff7227ec0d7ed1ea1463d`.
Every image is compared byte for byte after its process exits, including the
discarded trials. Raw output/status are saved before validation; there are no
retries, replaced failures, or removed outliers.

All 349 frozen source, artifact, host, tool and driver identities match before
and after the campaign. `clean.json`, `freeze.json`, `quiet-window.json` and
`measure-matched.py` preserve its raw evidence and driver. `summary.json`
contains every retained value, median, range and ratio. Process-inclusive
medians are separately 0.152302 s, 0.880200 s, 0.827531 s and 0.078274 s in
table order; they answer a different question from the program clocks.

Four samples support a descriptive comparison under this protocol. They do not
establish significance, narrow confidence intervals or a whole-suite result.
Historical strict measured coverage is now 31 of 57 workloads, including 30
paired Chez comparisons, at their recorded compiler checkpoints.

## Replay and checks

`artifacts.tar.xz` retains the strict preparation, corrected Rust handoff, exact
sources and compiled modules, diagnostic evidence, all clean records/images,
and the parent Rust execution check. External Nix/system tools are identified
by path and hash rather than copied. The manifest verifies every regular file
and the archive itself. The independent protocol explanation and parent critique
are summarized in `measurement-review.md`; no implementation was shown to the
explainer.

Restore and verify without running a workload:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/ray-comparison-replay \
  --report benchmarks/results/2026-10-14-strict-ray-comparison
```

Resolve `files/` paths in `replay-plan.json` beneath that restored directory;
retain the pinned external tools. Create a separate task directory with an
empty `outputs/` directory for each variant. The plan retains all 50 renders
and the complete image contract. `replay-check.json` records four actual
relocated executions; they are correctness checks outside the clean samples.
A new timing campaign requires remapped frozen paths and a new quiet window.
