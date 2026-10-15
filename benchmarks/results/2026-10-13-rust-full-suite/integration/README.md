# Rust-only draft integration

This layer imports the completed Rust source/evidence checkpoint
`cf83cda276fb07a0996dacc3d9fb2a364959e49a` above published draft
`b6f17305d3e97a3bcc08843183968c721e4e7094`. That base contains five reference
executables. The import adds the remaining 52, their shared data and algorithms,
correctness runners, fixtures, port contracts and nine Rust evidence directories.
It modifies Cargo inputs, the expanded datum reader, the reader-rejection arm in
`deriv`, and the reference README. The TOUR change is confined to the Rust
reference section. Strict compiler/runtime sources are unchanged.

[`checks.json`](checks.json) records the complete imported file/hash list and
exact source/evidence delta. All 162 imported files match the source checkpoint.
The original `cat`, `wc`, `graphs` and `lattice` sources, Node host, historical
five-case runners and all eight historical report files match the published base.
Every historical artifact and original absolute-path report remains unchanged.
The import's whitespace check reports three existing trailing blank lines in a
frozen native-check log, original type-data asset and runner. Those exact bytes
are preserved and the warnings are recorded; new integration metadata has no
whitespace warnings.

Formatting, all-suite native tests and release Wasm Clippy with warnings denied
pass. The native log contains 100 passing test executions, including shared
Compiler tests executed again in its example. [`linked-replay.json`](linked-replay.json)
records eight small correctness probes using binaries and hosts relocated from
the verified content store: Compiler and String, Node/Wasm and original Chez,
correct results and deliberately wrong expected results. The original guest
predicates remain active. These runs produce no performance samples.

The existing full-count evidence remains 57 source implementations and 56 default
canonical successes, with recursive Ackermann's default stack failure and its
optional heap-frame success recorded separately. The integration does not rebuild
or rewrite the canonical binaries or repeat unchanged long validations.
[`pending-reviews.json`](pending-reviews.json) expands the outstanding independent
review labels into bounded cohorts, while preserving completed review scope.
This is a draft correctness layer; independent source review remains unfinished.
