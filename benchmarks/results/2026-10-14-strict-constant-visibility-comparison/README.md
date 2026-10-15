# Strict constant visibility: three-way V8 comparison

General scalar-literal forwarding reduces the complete `bv2string` workload
median from **0.938281 s to 0.722995 s**, using **22.94% less time**. Adding
completed-global readiness facts reduces it to **0.654830 s**, a further
**9.43% reduction** from scalar forwarding and **30.21% less than baseline**.
These are three frozen compiler outputs from the same unchanged full source
and inputs, run through the same clean V8 host in one coordinated quiet window.

| Variant | Retained samples | Workload median (s) | Full retained range (s) |
| --- | ---: | ---: | ---: |
| Baseline | 6 | 0.938280909 | 0.937385150–0.940982346 |
| Scalar literals | 6 | 0.722994675 | 0.721827776–0.726891237 |
| Scalar literals and global readiness | 6 | 0.654829957 | 0.645475020–0.658908317 |

All **21/21 processes** passed. The first process for each variant was the
predetermined discard; all remaining 18 samples are retained. The six retained
rounds enumerate all three-system permutations, placing each variant twice in
each position. There were no replacements, additional warmups or later outlier
exclusions. Total process medians were 0.961646 s, 0.745834 s and 0.678683 s,
respectively; every process duration and workload observation remains in the
individual [measurement records](measurements/campaign.json).

## Exact experiment

The [preparation report](../2026-10-14-strict-constant-visibility/README.md),
[frozen plan](../2026-10-14-strict-constant-visibility/timing-plan.json), and
diagnostic archive remain unchanged historical artifacts. The plan's status
records its preparation time; `execution.json` records the later authorized
campaign. No source edits, compiler changes, native rebuilds, profiling or
code-print instrumentation occurred inside this experiment.

| Variant | Compiler commit | Optimized Wasm SHA-256 |
| --- | --- | --- |
| Baseline | `f32024bf6be9ab434b1581d04624b32d5b43c31f` | `c9ba1e18d65ead5db6cc005d9486e7275c14f9e8c91875edaa68e2ae59d7b1d6` |
| Scalar literals | `eb0f8544cd48bf22417fbb287c6f4d2a6042db70` | `bc2f5942886883a5f4c0c5398304de896db90ad6059ee29dd73ee6b1d3357742` |
| Scalar literals and global readiness | `d8ee1f4d91fe1eebabea5eb983d47ad8ed4bb0e6` | `632f53687dca8d70668832e76e13ac3d0ab2933ecdcfb1a6331b7f8723801178` |

Each process uses count **100**, 1,000 stress roundtrips, maximum size 1,000,
expected failures zero and the complete original predicate. Source, inputs and
host hashes are frozen in the plan; source SHA-256 is
`f67ffdc685fed6a7c33e1519376b0f5eb56590ce7c1d7f84552af1f755f9618c`.
The clean host omits `--validate`: the opacity imports return their arguments
without counters, while the full result must still equal `1` and stderr must
remain empty. Separate full-count validation and archive replay record all
200 expected opacity calls with zero setup calls for each artifact.

The original internal clock includes the complete exported worker and result
assertion. Compilation, instantiation and `main` precede it. V8 JIT work that
occurs during the workload remains included. Node is the pinned 24.19.0 binary
identified by the plan; every process starts fresh and is pinned to CPU 5.

The campaign ran from **2026-10-14 17:15:12.712543 UTC** to
**17:15:30.488089 UTC**, taking 17.776 s in total. The CPU model is Intel Core
Ultra 7 270K Plus. Immediate before/after policy snapshots retain all reads:
`intel_pstate` active, governor `powersave`, energy preference `performance`,
800–5500 MHz bounds, turbo enabled, and unchanged affinity. Instantaneous and
average frequency readings differed; these snapshots do not establish fixed
frequency during the workload. Other agents held builds, guests, profiling
and compression throughout this coordinated window.

The reviewed runner verifies all 14 frozen identities before each process and
after completion, rejects instrumentation environment variables, enforces exact
result framing and a bounded timeout, stops each owned process group and reaps
its leader.
The completion audit rechecked every record against its scheduled position,
recomputed medians/ranges, verified the plan bytes against the preparation
commit, and found no executing members in any owned group. `verification.json`
and `manifest.json` retain those results and every report-file identity.

## What the comparison establishes

The scalar-only artifact retains the original readiness checks. Its direct
literal payloads make the RNG modulus visible to ordinary Binaryen/V8
optimization. Separate machine dumps show two `idivq` instructions in the
baseline canonical RNG branch and one in each scalar variant: signed mask/bias
arithmetic replaces the constant-modulus remainder, while the general bound
still requires division. The mutable seed continues to use Ref storage.

The combined artifact additionally removes four readiness loads from each
decoder loop. Whole-module static readiness loads fall from 63 to one, retaining
the exported-entry check. The canonical RNG branch already had zero such
checks in the baseline; reductions in other RNG branches must not be attributed
to that canonical path.

This comparison isolates the two compiler mechanisms in sequence, not the cost
of each individual machine instruction. The readiness result is conditional
on scalar forwarding already being enabled. Both changes are general strict
compiler rules proved by immutability and creation/initialization ordering;
neither recognizes this benchmark or specializes its common bound 128.
The broad raw/optimized/linked-Wasm and native semantic checks are recorded in
the preparation report. This window measures only V8; it adds no native,
Chez, Rust or whole-suite performance claim.
