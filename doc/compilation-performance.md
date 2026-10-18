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

The full release build, including shader/simulation compilation and browser
packaging, took 64.45 seconds after these changes. Both generated Wasm files
are byte-for-byte identical to the original PR #322 output. No optimization
level was reduced for this measurement.

An original instrumented build took 698.82 seconds. Its simulation phases were
40.36 seconds resolving, 227.50 checking, 30.82 specializing and 376.65 emitting.
These are diagnostic timings: instrumentation adds overhead and must not be
used as the denominator of a clean speedup claim. An ordinary original sample
is being measured separately.

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
