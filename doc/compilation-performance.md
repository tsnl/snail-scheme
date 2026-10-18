# Siegework 3D compilation

The workload is the 3D application in [PR #322](https://github.com/tsnl/snail-scheme/pull/322),
base `e24ac1b82bc44e268d63e0d8e5f4244f84d404ba`, including shader generation,
simulation compilation and browser packaging. The older 2D prototype is a
separate, smaller workload.

## Causes and changes

The costly work was inside the compiler. Chibi's `guard` captures continuations;
overload compatibility entered it repeatedly at deep compiler stacks. Trials
now copy types and return a boolean from a private solver. They retain rigidity,
occurs checks and repeated-variable consistency. Actual committed unification
still uses the diagnostic solver. Concrete matching types need no trial.
Occurs and concreteness queries short-circuit over types instead of allocating
complete variable lists just to answer a Boolean question.

Checking repeatedly scanned lexical environments even for expansive or closed
initializers. Generalization now inspects candidates first. Monomorphic
annotations skip skolem escape scans. Mutable solver results are never cached.

Macro expansion used linear binding-list lookup. A name index narrows each lookup
to ordered references to the same binding objects; context identity and current
namespace visibility are still tested at use time. Class lookup similarly
caches only the ordered family members for an exact immutable instance list.

Emission scanned and sorted the entire entity graph for each of roughly 1,450
functions. Specialization now partitions that completed graph by activation
owner once, preserving allocation order. Concrete layouts use an identity-aware
structural index alongside their ordered registry; recursive layouts are still
reserved before their dependencies. Function locals accumulate with constant-time
cons instead of repeatedly copying growing lists. GC slots and initialization
order retain their previous meaning.

## Observations

| Ordinary 3D release build | Wall seconds | User CPU seconds |
| --- | ---: | ---: |
| Original PR #322 | 560.99 | 558.92 |
| Compiler fixes, `9537e62f` | 68.22 | 67.38 |

This is an **8.22× end-to-end speedup**, including shader/simulation compilation
and browser packaging. Another improved release sample took 64.45 seconds.
Both generated Wasm files are byte-for-byte identical to the original PR #322
output. No optimization level was reduced. See the
[measurement record](measurements/siegework-3d-compilation-2026-10-18.json)
for commands, CPU times, source provenance and artifact hashes.

These are single-machine observations with uncontrolled host load and caches.
Some correctness checks and a separate diagnostic profile ran concurrently with
the original sample. Chibi 0.12, Binaryen 132 and `BINARYEN_CORES=1` were used.
The original sources and build recipe were frozen in a private loader overlay
before edits; the ordinary after sample used the clean `9537e62f` worktree.

An original instrumented build took 698.82 seconds; its simulation phases were
40.36 seconds resolving, 227.50 checking, 30.82 specializing and 376.65 emitting.
Instrumentation changes allocation and stack behavior. Those timings locate
costs and are excluded from the speedup calculation above.

## Verification on current main

The performance-only patch was reapplied on `9bdee767` after the `All` requires
syntax change. A bounded full 3D rebuild took **77.77 seconds** and retained both
original Wasm hashes. The application and ordinary libraries remained at the
measured PR #322 revision; only the intrinsic core syntax manifest followed
current main. This run used a 4 GiB memory ceiling, no swap, two CPU cores and a
ten-minute timeout, with one Binaryen worker. It verifies current-main correctness;
host load and caches were uncontrolled, so it is not a matched new speedup result.
See the [verification record](measurements/siegework-3d-main-verification-2026-10-18.json).

## Reproduction

Run ordinary samples sequentially in separate output directories:

```sh
node scripts/measure-siegework.mjs baseline build/three-release-sample --3d
```

The driver records source identity/diff, tool versions, host load, command,
wall time and artifact hashes. `profile` adds private phase and source-unit
instrumentation; `hotspots` also measures helper calls. Run those separately
from ordinary samples. Their stack and allocation overhead changes timings;
instrumented totals are diagnostic evidence, not clean speedup measurements.
The 57-workload runtime comparison remains separate and unchanged.
