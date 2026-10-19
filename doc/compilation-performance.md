# Siegework 3D compilation

For current phase progress and emission-memory diagnostics, see
[live logging](tracing.md#live-compilation-progress) and
[retained compiler storage](#retained-emission-storage-18-october-2026).

The [latest checkpoint](#checked-expression-evidence-18-october-2026) measures
the canonical application after preserving checked type evidence. The earlier
checkpoint below uses the 3D application in [PR #322](https://github.com/tsnl/snail-scheme/pull/322),
base `e24ac1b82bc44e268d63e0d8e5f4244f84d404ba`, including shader generation,
simulation compilation and browser packaging. The older 2D prototype is a
separate, smaller workload.

## Earlier compiler changes

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

## Earlier observations

The full release build, including shader/simulation compilation and browser
packaging, took 64.45 seconds after these changes. Both generated Wasm files
are byte-for-byte identical to the original PR #322 output. No optimization
level was reduced for this measurement.

An original instrumented build took 698.82 seconds. Its simulation phases were
40.36 seconds resolving, 227.50 checking, 30.82 specializing and 376.65 emitting.
These are diagnostic timings: instrumentation adds overhead and must not be
used as the denominator of a clean speedup claim. This checkpoint has no recorded
ordinary baseline time.

## Reproducing the earlier workload

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

## Checked expression evidence, 18 October 2026

At compiler `a2818640`, the canonical Siegework application built in **50.9,
69.2 and 67.5 seconds**, with a **67.5-second median**. All three runs produced
identical shader and simulation Wasm. The matched baseline `601a6962` produced
the same shader but did not finish simulation compilation within the 600-second
process-tree limit. No completed baseline time or exact speedup ratio is claimed.

Both revisions used the same application sources, Chibi `-h16M/1G`, one Binaryen
core, a two-CPU quota, 4 GiB aggregate memory and no swap. Each attempt had a fresh
application output directory; host/provider build caches were retained. Runs were
sequential, with no other build or benchmark from this task. Shared-host load
varied; these are bounded build observations, separate from runtime performance.

Checking now freezes typed expressions after obligations settle. Specialization
records concrete decisions once, and emission consumes them without repeating
inference. Existing schemes retain control of polymorphic instantiation. See the
[compiler guide](compiler.md), [exact measurements](measurements/siegework-checked-types-2026-10-18.json)
and [raw records](measurements/siegework-checked-types-2026-10-18-records.tar.gz).

The current canonical application is selected without `--3d`:

```sh
CHIBI=/path/to/chibi-wrapper BINARYEN_CORES=1 \
  node scripts/measure-siegework.mjs baseline /tmp/siegework-fresh-sample
```

Use a wrapper that invokes the pinned Chibi executable with `-h16M/1G`, and
apply the recorded resource limits externally. The raw archive includes that
wrapper and the bounded launcher used for these samples. `--3d` selects the
earlier application under `apps/siegework/three`.

## Retained emission storage, 18 October 2026

Completed function definitions, including the module initializer, now become
opaque immutable WAT fragments immediately. Each fragment owns encoded byte
chunks; there is no large string join or second UTF-8 encoding. The existing serializer handles
escaping and exceptional numeric tokens once. Emission still discovers layouts,
imports and constants in the same order before writing the module header; no
analysis is repeated and no expression cache or temporary-file pipeline is added.
The internal `write-wasm` API takes a binary output port, allowing byte chunks
to cross UTF-8 character boundaries without decoding them.

On the complete Sboyer input, a forced-GC diagnostic reduced pairs retained after
emission from **722,357 to 199,084**. Subtracting each sample's post-write host
baseline gives **564,892 versus 40,706 output-associated pairs**, plus 534 compact
WAT fragments. The complete 3,138,011-byte WAT files are byte-identical. These
counts exclude the encoded WAT bytes; they are not a whole-process memory
ratio. Resident memory had already reached its high-water mark during checking
and did not meaningfully decrease. See the
[recorded observations](measurements/compiler-memory-fragments-2026-10-18.json).

The complete Compiler input was also attempted with a 4 GiB process-group cap,
zero swap, two CPUs, 128 tasks, a ten-minute limit and Chibi `-h16M/1G`. It timed
out during resolution at a 2.22 GiB process-group peak, before checking or
emission. That attempt does not establish a fix for the historical complete
Compiler emission failure. The earlier 8/16 GiB evidence and all 57 workload
sources remain unchanged.

For retained object counts and Linux resident-memory snapshots, run this tool
under the same external resource limits:

```sh
chibi-scheme -h16M/1G -I bootstrap scripts/measure-compiler-memory.scm \
  . benchmarks/lofi/sboyer/main.sld /tmp/lofi-memory
```

It writes `memory.json`, `compile.trace.json` and `source.wat`. Each snapshot
forces collection, so this is an instrumented diagnostic. Phase boundaries also
move some serialization work into emission; compare complete build times rather
than interpreting the final WAT-writing span as an independent speedup.
