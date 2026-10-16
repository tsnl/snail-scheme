# SLaTeX

`main.sld` retains all 183 kernel forms after flattening the upstream top-level
blocks. It runs the complete source-processing algorithm 500 times against the
unchanged `inputs/slatex-data/test` input. The original result predicate accepts
any returned value; this port preserves that predicate and adds independent file
observations outside measurement.

The workload's Scheme parser, state, formatting and file operations are ordinary
static Lofi code. No elaborator or host evaluator executes during preparation or
measurement. A closed local Value type preserves heterogeneous mutable objects,
and concrete fixed/rest closure signatures implement dynamic calls. Exact numeric
operations use the ordinary Integer/Rational/Number libraries. Original and
adapted Chez remain separate controls because explicit tags and mutable cells
change the representation cost.

`output-manifest.json` describes all 28,500 final output files as 500 repetitions
of 57 explicit path/size/SHA256 entries. Primary file numbers advance by 57 per
iteration. Every final file matched both Chez controls and the retained complete
V8 execution. The manifest also rejects extra output paths.

`lifecycle.json` retains the complete ordered open/close contract and each opened
resource's read, EOF and write totals. SLaTeX creates, rereads and removes temporary
files in addition to its final outputs. It reads the style file only in the first
iteration, closing it after a partial read and retaining the parsed style state.
Each later iteration still reads the full main input through EOF. Secondary file
numbers advance by two per iteration. The recorded complete worker opens and
closes 94,501 resources; setup closes one configuration input and cleanup has no
remaining resource to close.

The current `def`/`let` source passed all 500 iterations on optimized V8,
native64, original Chez and adapted Chez. Each produced all 28,500 exact output
files. V8 checked every ordered resource cycle; native checked one setup close,
94,501 worker closes and zero cleanup closes. The native build consumed retained
raw Wasm and produced the exact same optimized guest bytes as V8.
[`validation.json`](validation.json) retains commands, source/input/provider and
artifact hashes, compiler snapshot, terminal results and the parity proof.
Both frozen Rust routes also passed the canonical 500 and every output file.
These concurrent correctness executions are not performance samples.

The [public runner replay and integration check](integration.json) also pass.
The public build reproduces the validated raw and optimized Wasm exactly and
executes the full Wasm/native workload through the shared runner. Rebuilding
against the later library-builder and book-example updates retains those exact
guest bytes; the runner's 16 tests and frozen-input checks pass as well.

The syntax-only migration preserves literal spellings. Its checked numeric
inventory accounts for all 373 literals; 338 explicit I64 annotations preserve
the old widths, and every current typed value matches at its target IEEE width.
[`literal-migration.json`](literal-migration.json) records the source locations.
The shared runner invokes `verify.mjs` for the complete V8 resource/file proof,
`native-entry.rs` for native worker/cleanup checks, and checks every output file
for native, both Chez controls and the Rust routes.

Earlier attempts remain retained: one old-surface build failed in emission;
an instrumented inspection and an unmodified identical-source rebuild succeeded,
so that failure remains unreproduced. No product compiler repair was needed.

The shared Value/graph layer received a fresh independent explanation without
repository access and a focused critique of mutation identity, conversion and
cyclic equality. It retains local identity memoization and concrete dispatch.
Original algorithm functions and coherent exhaustive cases can exceed the
ten-line target when keeping the complete operation together exposes its meaning.
