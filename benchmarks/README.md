# Benchmarks

The active corpus is [`sfir`](sfir/README.md): all 57 canonical R7RS workloads,
with bare SFIR sources, external Chez controls, Rust implementations, exact
inputs and explicit source/target-validation/measurement status. SFIR is the
only compiler input language. Chibi hosts the compiler; Chez is an independent
comparison system.

```sh
python3 benchmarks/sfir/runner.py inventory
python3 benchmarks/sfir/runner.py prepare --output /tmp/sfir-check --benchmarks ack
python3 benchmarks/sfir/runner.py validate --output /tmp/sfir-check
```

Preparation copies checked-in target sources; it does not elaborate Scheme or
expand macros. The compiler always runs Binaryen. Native builds consume the
retained raw Wasm and verify that their mandatory optimization produces exactly
the V8 program bytes. Earlier freezes supplied already optimized Wasm to the
native helper; the [optimization audit](sfir/evidence/20261015-native-optimization-audit.json)
records those differing effective modules. Missing ports and pending
execution routes stay visible in the corpus manifest. The first [clean SFIR
timing report](sfir/evidence/20261015-clean-six.md) covers Ack, Fibfp, Cat, WC,
CTAK and FIBC on 33 available target/control routes; it retains default Rust
Wasm Ack's stack failure. The remaining workloads are not measured.

The [canonical validation checkpoint](sfir/evidence/20261015-existing41.md)
records 53 SFIR Wasm successes and 52 native successes, with GCBench's native
build timeout preserved. Four source ports remain pending. These correctness
runs do not add performance coverage.

[`wasm-reference`](wasm-reference/README.md) contains the 57 separate Rust ports
and complete correctness fixtures. Its original Chez controls now come from
the static SFIR corpus rather than a Scheme-source generator.

[`results`](results) retains historical evidence unchanged, including original
raw records, frozen snapshots, failures and measurements made before the SFIR
migration. Those results describe their recorded revisions and do not establish
SFIR behavior or performance. The removed Scheme benchmark drivers remain
available in Git at revision `d5c2d06`; the complete Peval preparation checkpoint
is `0cda43f`. Historical snapshot replay requires its recorded source revision.
