# Strict Scheme source in the cat experiment

[`copy.scm`](copy.scm) expresses the character-copy loop using concrete I32
arguments and typed foreign declarations. The strict compiler emits its native
`copy-code` export. The experiment compares that generated code with the old
Scheme copying code and the earlier hand-written scalar Wasm loop.

All three variants use the archived Rust scalar provider, Node host, original
4,460,056-byte input, and fifty-copy workload. They share assembly, Binaryen
optimization, linking, and initialization commands. The control rebuilds the
frozen old generated copying code with this shared experiment scaffolding;
its final binary is consequently different from the archived control.

The original Scheme harness still owns file opening, closing, and timing. Each
scalar adapter retains both port wrappers in owned AWI roots for the whole copy.
An extra GC global makes the output wrapper available to the source worker. It
is cleared before the roots are released on normal EOF. Numeric resource IDs
never encode WasmGC addresses. The provider calls are synchronous and make no
Scheme callbacks; this single-instance diagnostic global is not a general
reentrant I/O interface. Errors immediately consume the saved provider error
and terminate the process.

The raw scalar interface returns Unicode character codes, EOF, or an error
sentinel. Its write operation validates Unicode. A public typed character/EOF
API remains separate work. Legacy AWI startup and three current-port roots also
remain in this experiment.

## Reproduce

Restore and verify the earlier experiment, then compile the source using the
strict compiler branch that supports `define-extern` and `--export`:

```sh
python3 benchmarks/results/2026-10-13-cat-scalar-extern/replay.py /tmp/scalar-input
python3 benchmarks/strict-cat/measure.py prepare \
  --compiler /path/to/strict-compiler-worktree \
  --frozen /tmp/scalar-input/build/typed-extern-cat \
  --output /tmp/strict-cat
python3 benchmarks/strict-cat/measure.py validate --output /tmp/strict-cat
```

Preparation records commands, compiler sources, hashes, logs, intermediate Wasm,
and final artifacts. It requires the archived tool binaries to match their
recorded hashes. Validation executes both scalar implementations on Node,
covering Unicode, EOF before output validation, fatal read/write errors, native
signature mismatch, owned-port liveness, and temporary-root cleanup.

In a quiet CPU window:

```sh
python3 benchmarks/strict-cat/measure.py measure \
  --output /tmp/strict-cat --cpu 5 --rounds 3
```

The driver uses fresh processes, discards one run per variant, and retains three
runs in rotating order. Every output must match the complete original file's
length and SHA-256. It keeps Scheme workload time and process wall time separate.
These are uninstrumented timings. Compilation and strict-module initialization
occur outside the Scheme workload timer; process wall time includes startup.

The old-to-strict comparison combines representation, calling, boundary, and
generated-control-flow changes. The hand-to-strict comparison tests how closely
compiler output approaches the manually written scalar loop under the same
provider. Neither comparison isolates GC, inference, or Wasm engine overhead.
