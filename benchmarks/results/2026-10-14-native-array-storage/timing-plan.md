# Native array storage experiment

This comparison changes native array storage from eight bytes per element to
the declared Wasm storage width. It uses the complete, unchanged `bv2string`
kernel and its canonical 100 iterations with the original 1000/1000 inputs.
It does not include the separate strict compiler constant-propagation experiment.

The three systems are the frozen baseline native executable, the packed native
executable, and V8 running their exact common final optimized Wasm. Both native
builds used mandatory Binaryen through `build-native --wasm`. Their Wasm,
separately compiled C provider, Rust archive and entry source are identical.
The common Wasm SHA-256 is
`2463c3f837b5133d6a622fe0d690da47cffb464bbda63d2f90f000b27649e41e`.
This differs from the once-optimized V8 input used by the earlier comparison;
that earlier V8 timing is not reused here.

`timing-plan.json` freezes the commands, inputs, sources, tools and executable
identities. `measure.py` is byte-identical to the reviewed bytevector comparison
runner. Its `strict-v8` system selects the common final Wasm; `strict-native`
selects the baseline; `strict-packed` selects the narrower array build.

Run all 21 processes serially on CPU 5. Discard exactly the first process for
each system, then retain all six planned samples per system. The six retained
rounds enumerate all three-system permutations, placing each system twice in
each position. Each process starts fresh. Report the median and full range of
the internal workload clock, with process duration separately retained.
Compilation, instantiation and module initialization precede the workload clock;
JIT work triggered during the workload remains included. No later outliers are
discarded and no within-process extra warmup is added.

The runner verifies frozen identities before every process and at completion,
validates the complete result framing, rejects instrumentation environment
variables, captures failures and timeouts, kills the owned process group and
reaps its leader. Cleanup verifies there are no executing group members;
adopted zombies may remain. A failed sample aborts the campaign. Capture host
affinity, CPU model and frequency-policy state before and after the campaign;
do not claim a fixed frequency. Start only after all agents report their heavy
processes terminal and agree to hold builds, tests and compression.

Full-count correctness, forced-GC storage regressions, and allocation/collection
statistics are separate observations. Their durations do not enter the timing
summary. The diagnostic native allocation count is expected to stay unchanged;
requested bytes and collection frequency may change with the representation.
