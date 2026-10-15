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
records those differing effective modules. The
[complete 57-workload report](sfir/evidence/20261015-full57.md) records 326 measured
routes and all 1,956 scheduled processes passing their full predicates at frozen
compiler `8e547bfb`. Both default Ack Wasm failures, 12 unavailable adapted Chez
controls and two primary Mperm Chez timer-name rejections remain visible.
Corrected Mperm's six-way campaign is reported separately. SFIR trails Chez and
Rust on all six geometric-mean comparisons; matching-case counts, observed
ranges and representation differences accompany every comparison.

The later [packet-input comparison](sfir/evidence/20261015-input-packets.md)
measures current input buffering on Cat/WC separately; those medians do not
replace this full-suite freeze. The earlier
[six-case timing report](sfir/evidence/20261015-clean-six.md)
and the following validation checkpoints remain historical evidence.

The [canonical validation checkpoint](sfir/evidence/20261015-existing41.md)
records 53 SFIR Wasm successes and 52 native successes, with GCBench's native
build timeout preserved. At that checkpoint four source ports remained pending. These correctness
runs do not add performance coverage.

The subsequent [native parity check](sfir/evidence/20261015-native-parity.md)
passes GCBench and establishes identical optimized guest programs for nine
cases, bringing canonical native correctness coverage to all 53 programs in that
checkpoint. Earlier failures and measured artifacts remain unchanged.

Subsequent current-source checks pass complete SLaTeX, Dynamic and Scheme
workloads. The [Dynamic/Scheme checkpoint](sfir/evidence/20261015-dynamic-scheme.md)
includes original/adapted Chez, both Rust targets, interpreter probes and source
resource lifecycles. That checkpoint registered 56 sources while Compiler was
pending. It added no clean timing coverage; the completed full57 report above
supersedes its current coverage status without changing the original records.

[`wasm-reference`](wasm-reference/README.md) contains the 57 separate Rust ports
and complete correctness fixtures. Its original Chez controls now come from
the static SFIR corpus rather than a Scheme-source generator.

[`results`](results) retains historical evidence unchanged, including original
raw records, frozen snapshots, failures and measurements made before the SFIR
migration. Those results describe their recorded revisions and do not establish
SFIR behavior or performance. The removed Scheme benchmark drivers remain
available in Git at revision `d5c2d06`; the complete Peval preparation checkpoint
is `0cda43f`. Historical snapshot replay requires its recorded source revision.
