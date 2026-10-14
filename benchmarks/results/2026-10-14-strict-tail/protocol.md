# Tail preparation and future comparison

Preparation uses the pinned upstream submodule and the existing Chibi-hosted
strict compiler. Run from a checkout containing the input-library prerequisite:

```sh
python3 benchmarks/strict-suite/measure.py prepare \
  --output build/strict-tail --benchmarks tail --compiler-basis 97c6b87
```

The command freezes sources/tools, reads the original count/pathname datums,
copies the complete bibliography into real input files, builds and validates
linked raw/optimized Wasm, both Chez controls and native output, and checks
nineteen supplemental files in five systems. The native path lowers the optimized
Scheme Wasm and links the same Rust scalar services. Its retained build record
shows the required Binaryen step even with `--wasm` input.

Canonical workload boundaries include every repeated pathname transfer, open,
delete, line read/construction, retained list node, output character and close.
Input parsing and initial pathname String construction happen before the worker.
Every write and the original always-true predicate remain in the workload;
complete byte verification follows it. Invocation cleanup brackets reactor
initialization and Scheme main as well as the worker.

The archive's `evidence/retain.py` constructs and runs the separate WASI observer
host. Removing its counted textual additions recovers the canonical host. The
Scheme binary stays byte-identical. Audit durations are not clean samples.

No clean timing campaign ran during this task. A later coordinated campaign
must use complete count 50 and the actual full input/output files in every
system, validate complete bytes after each sample, retain failed runs, and keep
diagnostic observers outside the measurement cohort. Any Rust reference must
first disclose or resolve its CR handling, input-close order, count domain and
Vec/UTF-8 storage differences. Original Chez and the same adapted source control
remain separate; neither is relabeled as a Rust or strict allocation control.
