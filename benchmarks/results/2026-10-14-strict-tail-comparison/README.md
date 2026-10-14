# Complete Tail comparison

| Implementation | Median workload seconds | Retained range | Median process seconds |
| --- | ---: | ---: | ---: |
| Strict Snail / V8 | 4.899608 | 4.795116–4.959857 | 4.935504 |
| Original source / Chez | 0.947096 | 0.945897–0.954374 | 0.980090 |
| Adapted source / Chez | 1.806730 | 1.800735–1.811220 | 1.839336 |
| Rust / Wasm / V8 | 0.216239 | 0.214366–0.217704 | 0.241156 |

Strict Snail takes **5.173× original Chez time**, **2.712× adapted Chez time**
and **22.658× Rust/Wasm time**. Every invocation performs all 50 original
reversals of the complete 4,460,056-byte bibliography. All twenty invocations
pass complete byte validation; no samples were replaced or removed. Each median
summarizes four retained process observations, each containing 50 reversals.
This is a descriptive comparison of one workload at its frozen checkpoint.

## Frozen workload and programs

Upstream source/input revision is `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`.
Original input datums remain count 50, `"inputs/bib"`, `"outputs/tail.output"`
and the unused `ignored` datum. Their SHA-256 is
`b06e57a58d1410fbe92f4724a9b36e4cc61f8c110f30e29abdd5aa5a473e9a16`.
The bibliography contains 31,102 LF-terminated lines, valid UTF-8 and no CR.
Its SHA-256 is
`2994b446dfb07d7cf324fb6aa32d519b3f0bd53a582268714adf08df5f45b8d3`.
An independent byte-level LF reversal produces the complete 4,460,056-byte
oracle, SHA-256
`a15bdc3031685b3dcec119172e22a052f36467a9efb9b01e3061b71d2ec3f717`.

The [strict preparation](../2026-10-14-strict-tail/README.md) retains the original
and adapted Chez programs, exact source adaptation, optimized linked Wasm,
library tests, supplemental inputs and separate retained-work evidence.
Its compiler/runtime basis is `97c6b8732d12afdbe6e796cce6933fd728aeab7e`;
all 76 frozen compiler/runtime files and 69 case files remain unchanged. The
strict timing artifact is
`23de40d54791743841fe3e9e93336872bd34ef6a8858607b136eb4cb92d2e33d`.
Its mandatory Binaryen production pass and raw diagnostic form remain recorded.

The Rust timing artifact is a new mandatory Binaryen `-O3` derivative of the
existing release, SHA-256
`4a294c1c083a52380529ec26b7dd348c7c89e689b80afd44161922e0760d9b6f`,
98,180 bytes. The historical 130,477-byte release
`5b690fa3dd93e50d260cdbafbad39a6a98c2e260930f5fd3fd405a8494f4af97`
is retained as a diagnostic input, alongside its complete 40-file source bundle
and full functional record. No Rust source change or release rebuild occurred.
The historical source/tool/version hashes and release profile are preserved;
the historical actual cargo stdout was not recorded. The new optimization
command, tool identity and terminal output are retained exactly.

## Timing and correctness boundaries

Datum decoding, process startup, program loading and initialization precede the
workload clocks. Strict pathname String construction also precedes its clock.
Each timed iteration opens the input, deletes existing output, creates output,
reads and retains every line, writes the reversed lines with LF, and closes the
real files. The original result predicate is always true. Complete output-byte
verification occurs after process completion, outside both clocks, including
for the excluded invocations. The strict host's result assertion and terminal
resource cleanup follow its stopped clock; normal per-iteration closes occur
inside it. The separate process clock includes launch through completion.

Strict stdout must be one exact three-field JSON record with result `"1"` and
null barriers. Chez must print its exact `tail:50` label, elapsed line and CSV
row; Rust must print `Result: ignored` and its exact `tail:50` CSV row. Nonzero
status, stderr, malformed framing, invalid time, absent output or any different
output byte fails the trial. Started attempts and raw stdout/stderr are saved
before decoding or validation; trial files remain available on failure.

Final output alone does not establish that the first 49 reversals survived.
The preceding strict observer executes the unchanged optimized guest and
establishes 100 opens, 100 closes, 49 deletions and 223,002,800 bytes read and
written. A separate Rust observer establishes those same totals on the exact
new optimized timing artifact, with every file operation between its two
monotonic clock calls. It confirms input close before the first output write
in each Rust iteration. Descriptor mappings attribute returned transferred
bytes, including partial I/O and descriptor reuse, to the canonical files;
datum stdin and terminal stdout are excluded. Observer hosts are never timed.
Source recursion/collection establishes complete line retention before writing;
these records do not establish physical allocation counts.

## Representation and lifetime differences

Strict Scheme keeps a reversed `List<String>` and stores Unicode scalar strings
in owned I32 buffers. Its line reader grows capacity from 64 by doubling and
trims once; its writer transfers characters through the Rust scalar I/O ABI.
The adapted Chez control shares this kernel and its line/capacity/character-write
helpers, using vector products/variants and native Chez strings/ports. Original
Chez uses its unchanged native `get-line` prelude. Adapted Chez already takes
1.908× original Chez time, so source/helpers/representation changes are material
to the original-source comparison.

Rust collects UTF-8 `String` values in a `Vec<String>` with `BufRead::lines`,
then writes their reverse iterator through a buffered byte writer. It creates
output before finishing input collection, drops the input iterator before
writing, and completes flushing and owned-value/output cleanup inside each
timed call. Scheme keeps input open until output closes. GC reclamation and
Rust destruction schedules differ, as do contiguous vector storage, linked
lists, string widths and line/character I/O primitives. The measured gap does
not isolate GC, ownership, line I/O or any individual representation.

The canonical LF/count-50 case agrees completely. Rust parses a nonnegative
Wasm32 `usize` count, unlike Scheme's signed I64 domain. Rust's LF/CRLF handling,
the original Chez prelude's LF-only handling and strict/adapted CR/LF/CRLF
handling differ on other files. No unrelated noncanonical semantics were
rewritten, and this report does not claim equivalence over those domains.

## Protocol, archive and replay

One excluded four-variant cycle precedes four retained cyclic rotations; each
variant occupies every retained ordinal position once. Each process receives
a fresh working directory, the complete bibliography at its original relative
pathname, an empty `outputs/` directory and absent destination. Input staging
occurs before launch. Fresh processes and directories do not imply cold disk
or page caches, and normal buffered writes do not require durable disk flushes.

The coordinated hold paused agent builds, tests, compression and other
executions. Source reading/editing, conversation/tool metadata and uncontrolled
desktop/system activity could remain. The quiet record retains the parent's
clarification of Astra's already completed checkout; no Nucleic builds/tests
ran. After Tail terminated, execution/compression remained held for the next
native campaign. Every process uses logical CPU 5 on the recorded Intel Core
Ultra 7 270K Plus machine, Node 24.19.0/default V8 tiering or Chez 10.4.1.
Node options, coverage and debugging variables are cleared, warnings suppressed,
and no profiler/counter/JIT-policy flags added. Remaining environment is inherited;
selected values and that limit are recorded. All **236 frozen identities**
match before and after the campaign.

`clean.json`, `freeze.json`, `quiet-window.json`, `checks.json`, `summary.json`
and `measure-matched.py` retain the protocol, raw records and both clock summaries.
`artifacts.tar.xz` and `manifest.json` retain all complete trial input/output
files and raw streams, exact sources/hosts/binaries, decoder provenance, Rust
diagnostics and prior strict evidence. Large trial files are held in that
verified archive rather than expanded in the source diff. External tools are
identified by path/hash; dynamic libraries, Rust sysroot/dependencies and the
full inherited environment are not vendored.

Restore and verify every regular archived byte without execution:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/tail-comparison-replay \
  --report benchmarks/results/2026-10-14-strict-tail-comparison
```

Resolve `files/` paths in `replay-plan.json` beneath that destination, retaining
the pinned external tools. Use a fresh cwd with the archived complete bibliography
at `inputs/bib`, empty `outputs/` and absent output per variant. `replay-check.json`
records four actual relocated full-count executions with complete byte checks;
their durations are separate correctness evidence, outside clean samples.

Historical strict coverage is now **33 of 57 workloads**, with **32 paired Chez
comparisons**, combining recorded compiler checkpoints. This is not a complete
rerun on the current compiler, an inference measurement or a whole-suite result.
