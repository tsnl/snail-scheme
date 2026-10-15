# Benchmarks

The active comparison is **SFIR, Chez and Rust across all 57 canonical workloads**.
See [the corpus guide](benchmarks/sfir/README.md) for preparation and execution,
and [the manifest](benchmarks/sfir/corpus.json) for each workload's source,
correctness and measurement status.

```sh
python3 benchmarks/sfir/runner.py inventory
python3 benchmarks/sfir/runner.py prepare --output /tmp/sfir-suite
python3 benchmarks/sfir/runner.py validate --output /tmp/sfir-suite
```

The default selection is the complete suite. A selected subset is a diagnostic,
not completion of the full comparison. Runtime measurements exclude compilation
and startup; instrumentation remains separate. All failures stay in the report.

The first [clean SFIR comparison](benchmarks/sfir/evidence/20261015-clean-six.md)
covers Ack, Fibfp, Cat, WC, CTak and Fibc on V8 and native. All 33 eligible routes
completed one warmup and five measured runs; Rust/Wasm Ack retains its validation
stack overflow. This is six-workload coverage, not a complete suite score.

Historical strict-Scheme results do not establish performance of the new SFIR
frontend. Those [reports](benchmarks/results) retain their exact
compiler revisions, source adaptations, samples and failures. They are not one
whole-suite measurement, and their original reproduction commands require the
recorded source snapshot rather than today's checkout.

Chibi remains the compiler host. Scheme compilation and self-hosting are outside
the current goal; [the roadmap](doc/roadmap.md) records those future projects.
