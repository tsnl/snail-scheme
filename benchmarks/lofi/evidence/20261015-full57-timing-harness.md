# Full-corpus clean timing preparation

The timing harness supports the 57 registered SFIR workloads and all six
target/control routes. This checkpoint validates four representative canonical
workloads; it establishes no full-corpus correctness or measurement result.

The frozen compiler, harness and corpus revision is
`039d7f76c3c40707fb70dc7d55df104d01a1e45e`, based on main
`29cf7b345fb87b85034126865090af860323da3f` (checked arithmetic and complete
library data). The selected Rust installation and locked crates were copied
before building. [The summary](20261015-full57-timing-harness.json) identifies
the local preparation tree, terminal records, file digests and native parity.

```sh
BINARYEN_CORES=1 python3 benchmarks/sfir/timing.py prepare \
  --output /tmp/sfir-full57-timing-canonical-20261015-1 \
  --benchmarks fft pi tail equal --compile-timeout 1800 \
  --run-timeout 1800 --cpu 2
PYTHONPATH=benchmarks/sfir python3 -m unittest runner timing
```

| Canonical workload | Original validation | Separate clean-artifact validation |
| --- | --- | --- |
| FFT | All six routes passed | All six routes ready |
| Pi | All six routes passed | All six routes ready |
| Tail | All six routes passed | All six routes ready |
| Equal | All six routes passed | All six routes ready |

The preparation command exited successfully. Every clean native executable
passed the retained raw/optimized guest parity check and its actual execution.
FFT exercised both scalar sine providers. Pi exercised full decimal predicates,
post-clock serialization and the original/adapted Chez driver adapters. Tail
checked complete output bytes. Equal exercised the controls' distinct actual
timer names. The fixed 144-entry warmup/sample schedule was generated and never
executed; no measurement directory exists. No canonical attempt was retried.

All 38 harness tests pass. Reduced synthetic Wasm probes execute every host
category and typed sequence, decimal and math interfaces. Native C probes
execute scalar, F64 and decimal entries, verify disabled observation counters,
and reject incorrect results. Further tests cover the Chez driver adapter,
fixture copies, native heap propagation, frozen dependency changes, exact
process bytes and fixed scheduling/failure behavior. Probe commands and
intentional failed-predicate processes remain under `build/sfir-timing-probes`.
These diagnostic probes are separate from canonical correctness.

After the canonical freeze, the final harness added rejection of nonempty
`NODE_OPTIONS` (tested with `--cpu-prof`), clarified two helper boundaries,
strengthened native counter tests, and removed the unused `diagnostic_only`
metadata on Pi and Chudnovsky. The freeze had empty `NODE_OPTIONS`; these changes
leave canonical workers, counts, predicates and generated artifacts unchanged.
The final test command and the earlier successful test attempt are both retained.
