# Preparation protocol

The source authority is the complete pinned R7RS Nucleic program at
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`, with the original three input datums
`50`, `()` and `33.797594890762724`. Run from the isolated Nucleic checkout with
the tools supplied by the repository development environment:

```sh
BINARYEN_CORES=1 python3 benchmarks/strict-suite/measure.py prepare \
  --output build/nucleic-prepared-attempt-1 --benchmarks nucleic \
  --compiler-basis 94787a4
```

That compiler basis includes scalar trigonometry (`6dadbea`), identity-table IR
copying (`37cac19`) and query-local dependency reachability (`94787a4`) on base
`71c6cfb`. The benchmark adapter and driver are frozen as source bytes and hashes;
they were uncommitted while preparing. A later port commit does not rewrite the
recorded earlier driver commit.

Each complete Scheme compile, runtime link and native build has a 1,200-second
bound. A timed-out build receives SIGTERM as a process group, up to five seconds for the leader and captured pipes,
then SIGKILL is attempted independently on remaining group members. Captured output, exit status, timeout and elapsed
duration are retained. The inspected build chain invokes children synchronously
without detaching. Separate fixtures cover a child that ignores SIGTERM with inherited pipes and
with both output streams closed; the latter demonstrates the original cleanup
gap and its correction. This
is bounded ownership of these build tools, not a general supervisor for daemons;
buffered output is persisted when a build completes or times out.

Both production targets retain mandatory Binaryen optimization. Raw linked Wasm
uses the explicitly diagnostic prune-only linker mode. Native builds start from
the optimized Scheme Wasm, apply their own mandatory Binaryen preparation, then
mechanically translate it to LLVM and link the same Rust scalar library through
C linkage. This can change Wasm bytes again, so the native intermediate has its
own identity. Each actual native executable, provider, entry source, LLVM file,
optimized Wasm and build record is retained.

Counts 1, 2 and 50 run with the original complete algorithm input in original
Chez, adapted Chez, raw linked Wasm, optimized linked Wasm and native code.
Separate full-kernel probes compare all database values, ordered solutions,
geometry and mutation behavior. Wrong and near-boundary expected values and
nonpositive counts exercise the original numeric predicate and initial false
result. The final ratio predicate is never substituted with the probe tolerance.

Build, validation and diagnostic process durations are provenance only. This
preparation has no discarded/retained timing rounds, no clean medians and no
cross-language speed claim. A later comparison needs its own coordinated quiet
window and retained-work review; it must retain all 50 searches and disclose
representation, arithmetic and ownership differences, including the separately
reviewed Rust reference.

The compiler fixes additionally run `make test`, `make check`, Rust unit tests
and formatting, backend/build integration tests, and the complete strict
contract suite. The latter is split into four disjoint fixture lists with
independent output directories and exact aggregate coverage. No timeout or
interrupted suite is counted as passing; earlier interrupted/failed attempts
remain in the archive.

The timeout cleanup changed after successful preparation. Original helper and
metadata remain in `nucleic-source-amendment`; its explicit amendment proves
that only the timeout function changed and all generated source/artifacts retain
their identities. The checked preparation metadata records both source versions.

A separate native timing entry was subsequently prepared without changing the
Scheme module, LLVM, provider object or Rust library. It parses count and
initializes the module before a CLOCK_MONOTONIC bracket around `worker(count)`,
then formats output and runs cleanup after the bracket. Counts 1, 2 and 50 pass,
and expected 30.0 is rejected. Its first entry version included count parsing
inside the bracket; that preliminary entry/build remains recorded, and the final
version moves parsing outside. The untouched Chez harness places j0 before its
repeat loop and reads j1 after successful `ok?` evaluation, so both its ratio
predicate and the strict worker's ratio predicate fall inside their clocks.

Clean performance observations, when published, belong to a separate comparison
report. The preparation archive contains the reviewed timing entry and frozen
command plan, not that campaign's measured samples.
