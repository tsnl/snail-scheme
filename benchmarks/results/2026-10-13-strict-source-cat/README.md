# Cat compiled from strict Scheme source

The strict Scheme compiler reduces the frozen cat workload from **20.784s to
2.912s**, a **7.14×** speedup against the matched old generated copying code.
The hand-written scalar loop takes **2.620s**. This is a source-compiler result:
[`copy.scm`](../../strict-cat/copy.scm) is compiled through inference,
monomorphization, native Wasm emission, and Binaryen. The surrounding original
Scheme benchmark still owns its timer, files, fifty repetitions, and result
checking.

## Final clean batch

Node 24.19.0 / V8 13.6.233.17, CPU 5, default engine settings. All variants use
the same frozen Rust scalar provider, host, platform, and Binaryen 132 recipe.
One complete run per variant is discarded, followed by three retained runs in
rotating order and fresh processes. No instrumentation runs in this batch.

| Copy implementation | Retained workload seconds | Median |
| --- | --- | ---: |
| Old generated Scheme loop | 20.763350, 20.784071, 20.946551 | 20.784071 |
| Hand-written scalar Wasm loop | 2.591696, 2.619643, 2.640659 | 2.619643 |
| Compiled strict Scheme loop | 2.917474, 2.771919, 2.911732 | 2.911732 |

All twelve full runs produce the original 4,460,056-byte file with SHA-256
`2994b446dfb07d7cf324fb6aa32d519b3f0bd53a582268714adf08df5f45b8d3`.
The workload processes 223,002,800 characters per run. Complete observations,
including separate process wall times, are in [clean.json](clean.json).

An earlier candidate measured 20.702s / 2.654s / 2.790s respectively. Its
public Unit-returning initialization entry still returned an i32 zero. The final
entry returns no Wasm value, matching the native Unit ABI. We rebuilt and reran
all three controls after that interface change. Both batches are preserved;
the standalone optimized copy worker is textually identical across candidates,
as recorded in [worker-comparison.json](worker-comparison.json). The spread
between and within batches limits precise claims about the remaining gap to
hand-written Wasm.

## What changed and what remains

The source worker receives its input port ID in an I32 parameter, reads a scalar
character/EOF/error code, performs integer checks, writes the scalar, and tail
calls itself. Its successful per-character path contains no Scheme boxing,
argument arrays, or AWI root operations. Native binding-readiness checks and
a global non-null closure check remain in the optimized loop. This inspection
describes the worker's code, not an allocation count for the entire process.

An outer adapter owns both GC port wrappers throughout a copy, so raw resource
IDs cannot outlive their owners. The output wrapper is also held in a temporary
GC global and cleared before root release on normal EOF. Reads precede output
validation. The provider's errors terminate the process; the diagnostic does
not support overlapping or reentrant copies.

This comparison combines representation, argument passing, foreign-boundary,
and generated-control-flow changes. It does not attribute the improvement to
inference alone or measure GC time. Both scalar variants retain legacy runtime
startup and port management. The old control is rebuilt with the shared
experiment scaffolding, rather than reusing its earlier final binary. This is
one benchmark and does not replace the full-suite Snail/Chez comparison.

## Validation and reproduction

[validation.json](validation.json) records linked execution of both scalar
variants for Unicode (including NUL and supplementary characters), repeated
EOF, EOF before output validation, fatal closed-input/output errors, incorrect
native import signatures, owned-port liveness, and temporary-root cleanup.
These checks are separate from clean timing. All fifty recorded compiler source
files match review commit `3e91f99` in
[the native boundary PR](https://github.com/tsnl/snail-scheme/pull/76), verified
in [compiler-commit.json](compiler-commit.json).

The archive preserves both candidates' compiler snapshots, source, raw and
optimized Wasm, linked artifacts, disassembly, inputs/outputs, host/provider
copies, build commands, functional checks, and raw timing records. The manifest
checks every archived file. Restore and validate without executing a workload:

```sh
python3 benchmarks/strict-cat/replay.py /tmp/strict-cat-replay
```

To repeat the final clean batch in a quiet CPU window, append `--measure --cpu 5`.
That rerun verifies the recorded Chibi and Binaryen binaries as well as Node,
so their original paths must still exist even though the artifacts are compiled.
To rebuild from Scheme, follow the [source experiment instructions](../../strict-cat/README.md).
