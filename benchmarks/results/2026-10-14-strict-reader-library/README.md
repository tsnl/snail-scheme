# Strict typed reader library correctness

The reusable `(snail datum)` and `(snail read)` libraries pass linked raw Wasm,
mandatory Binaryen-optimized Wasm and actual native64 checks. This is library
correctness preparation, without clean performance measurements or an increase
in the historical measured-workload count. The starting compiler is
`87d22a4675eb6b79c466a67e04632e1b95b04c5d`; the upstream input revision is
`85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`.

The integration review independently verifies all 3,352 archive members and
replays both complete canonical streams on all three execution paths, plus five
native cases with collection forced at every allocation. After integration as
`69c5171`, the complete suite passes again with the newer native allocator.
`integration-review.json` retains those checks, the 300 terminal command records
and resulting artifact identities. These additional checks are not timings.

Scheme owns incremental tokenization, syntax, recursive datums, explicit mutable
pair fields and structural equality. The same Rust scalar exports provide UTF-8
input, owned temporary numeric-token handles and stable strict symbol identities
on both backends. No operation converts through `Top` or legacy Scheme roots.
The [implemented contract](../../../doc/strict-reader.md) states numeric,
identifier, lifetime and unsupported-syntax boundaries.

The final suite is `build/strict-reader-1792001303769628063` in the archive. All
30 valid streams compare every datum field with an independent native Chez
reader. The canonical Read1 file produces five datums and 16,576 observed fields;
the canonical Sum1 file produces 100,000 numeric datums and 300,000 fields.
Both canonical files are byte-for-byte untouched. This is one complete internal
stream observation per input, not the future 25/2,500-invocation workload run.
There are also 51 syntax-error cases and three malformed/truncated UTF-8 cases
on each target. Repeated EOF, buffer growth around capacity boundaries, Unicode
scalars, mutable string independence, pair aliases, persistent symbol identities,
fresh symbol spelling copies and negative structural equality are checked.

Chez's R6RS bytevector spelling, long Boolean spelling, named character aliases
and bar-symbol hexadecimal escapes differ from the selected reader syntax.
Only explicitly named edge fixtures use alternative oracle spelling; their
original and oracle bytes are retained. No such adaptation is applied to either
canonical data file. Numeric observations retain exactness and binary64 bits,
with all NaNs represented by a common observation token. Tests cover signed zero,
exact decimal boundaries, complex promotion and both polar axes. The strict
wrapper preserves exact zero magnitude and exact zero angle after prefix
exactness is applied; nontrivial polar conversion keeps the existing Rust
helper's trigonometric boundary. Transcendental bit equality is not claimed.

All relevant regression checks pass: 42 Rust tests, `cargo fmt --all -- --check`,
`make test`, `make check`, `scripts/test-build`, `scripts/test-backend`, and all
eight linked raw/optimized `scripts/test-strict-io` cases. The final reader suite
also records executable tool identities, source hashes, compiler commands,
generated Wasm/LLVM/provider-object identities and native build provenance.
The native backend performs its own final Wasm optimization; its final module
is archived separately from the production V8 module.

Every executed build or probe has bounded supervision and retained output.
The new reader runner owns each process group, kills remaining group members,
reaps the leader and checks that no executing descendants remain. Earlier
diagnostic commands and regression suites use the retained bounded group runner.
All recorded groups are terminal. Expected UTF-8 failures are nonzero exits, not
timeouts. Failed attempts remain in the archive: unsupported wildcard-match
syntax, a parenthesis error, oracle spelling/classification mistakes, the polar
normalization mismatch, formatting corrections and a Chibi version-query flag.
Early exploratory commands retain their command/error records; complete
per-attempt source snapshots begin with the full reader-suite attempts.

The pinned simplify review used a fresh Astra/max explainer with no conversation
history, files or tools, followed by one informed critique. It motivated explicit
owned token state transitions, stable symbol-domain boundaries, affirmative
identifier validation and visible port-owned lookahead. Large functions remain
only where coherent exhaustive dispatch, token lifecycle or test/process
supervision is clearer together: numeric normalization, reader syntax/container
cases, datum equality and the test runner. The landed frontend is unchanged.

`manifest.json` inventories archive members; `archive-verification.json` verifies
every member against that inventory. The archive includes all reader attempts,
original test inputs, complete observations, the final runnable artifacts,
native runtime archive and I/O regression evidence. Correctness-run elapsed
times in command records are not benchmark measurements.
