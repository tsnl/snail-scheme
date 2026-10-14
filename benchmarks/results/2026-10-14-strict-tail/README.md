# Complete Tail preparation

All 50 original reversals of the complete `inputs/bib` pass in linked raw and
optimized Wasm, untouched Chez, the adapted Chez control, and native execution.
The input contains 4,460,056 bytes and 31,102 LF-terminated lines. Every output
byte matches the independent reversed-line oracle. This report contains no
clean performance samples; durations in execution records are provenance only.

Upstream revision is `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`.
The strict input prerequisite and frozen compiler basis is
`97c6b8732d12afdbe6e796cce6933fd728aeab7e`. Preparation ran with uncommitted
driver/adapter edits, as in the existing suite workflow; `prepared.json` keeps
that earlier driver commit. The archived source bytes and SHA-256 hashes are
authoritative. All 76 frozen compiler/runtime files and 69 case files verify.
Additional native compiler inputs are frozen against the native build record.

Canonical input SHA-256 is
`2994b446dfb07d7cf324fb6aa32d519b3f0bd53a582268714adf08df5f45b8d3`.
The complete 4,460,056-byte output SHA-256 is
`a15bdc3031685b3dcec119172e22a052f36467a9efb9b01e3061b71d2ec3f717`.
Both files are archived. The original result predicate remains always true;
complete bytes and lifecycle checks are separate from that predicate.

## Source and library behavior

The complete original source and input are retained. Three counted kernel edits
extract String from `LineResult`, rename its EOF predicate for the Chez control,
and replace `for-each` with an explicitly typed traversal. Signatures declare
the existing concrete roles. Reversing the substitutions recovers the original
kernel exactly. No input slice, streaming reversal, host bulk file operation,
sorting, reduced repetition count or alternate algorithm replaces the source.

Each iteration opens input, deletes existing output, opens output, reads all
lines into a reversed Scheme list, writes each line followed by LF, closes
output, then closes input. The original callback nesting keeps that close order.
Pathnames are decoded before the workload; actual path staging, opens, reads,
line construction, list retention, writes and closes repeat inside it. The
actual Chez reader accepts the original count and pathname datums. Counts use
I64; the unused fourth datum is read without restricting its value.

`(snail io)` now exposes concrete `InputPort` and `LineResult` types. Rust owns
buffered files and transfers only scalar code points, EOF `-1`, and integer
resource IDs. Existing `host::TextInput` supplies UTF-8 decoding and one-character
lookahead. Scheme constructs strings with a local buffer that starts empty,
grows from 64 characters by doubling, and trims once at line end. Exact fits
reuse their buffer. This bounds copying without a GC allocation per character.
The String limit is checked before appending further content, so a terminator
after an exact maximum-length line would remain valid.

CR, LF and CRLF terminate one line; other Unicode scalars, including NUL, are
preserved. Empty lines have fresh mutable strings and remain distinct from EOF.
A final unterminated line appears once. Malformed/truncated UTF-8 and read errors
trap after releasing Rust-owned resources. A shared Ref makes public close
idempotent across aliases; raw stale or wrong-direction handles still fail.
The host cleanup boundary covers initialization and callback traps.

The adapted Chez control shares the exact kernel and the strict library's
`read-line`, CR lookahead, line-loop, capacity-growth and character-write bodies.
Preparation hashes each definition and verifies it occurs exactly once. Chez
uses vector line variants and native ports. Its compatibility character-copy
loop implements the same bounded copy operation; its allocation/layout and
primitive costs are not physically identical to WasmGC or the native backend.

## Controls and edge cases

The pinned upstream Chez prelude maps `read-line` to `get-line`. Actual execution
shows that it recognizes only LF and retains CR. The strict library and adapted
Chez follow the repository text-reader contract for CR/LF/CRLF. The canonical
bibliography contains no CR, so both controls agree byte-for-byte on the full
workload. On CR fixtures, the archive retains and checks each control's exact
different bytes; it does not silently rewrite the original Chez program.

| Check | Executions | Contract |
| --- | ---: | --- |
| Canonical bibliography | 12 | Counts 1, 2 and 50 in original/adapted Chez and raw/optimized linked Wasm |
| Canonical native | 1 | All 50 repetitions, complete bytes, 100 observed resource releases |
| Supplemental files | 95 | Nineteen cases in both Chez forms, both Wasm forms and native |
| Separate optimized work audit | 1 | Unchanged optimized binary, full original count/input and observed WASI work |

The nineteen file cases cover empty input/lines, terminated and unterminated
final lines, CR/LF/CRLF, embedded NUL, supplementary/max Unicode scalars, Unicode
non-line separators, 63/64/65 and 127/128/129 character boundaries, existing output
replacement, zero/negative counts and fifty repeated small-file reversals.
Every complete input and output is retained as bytes. Nonpositive counts leave
the existing output untouched and still pass the original always-true predicate.
Wasm diagnostics check ordered opens, deletions and output-before-input closes.

The separate audit uses the unchanged optimized binary
`23de40d54791743841fe3e9e93336872bd34ef6a8858607b136eb4cb92d2e33d`.
Starting without output, it observes 100 opens, 100 closes, 49 deletions,
223,002,800 bytes read and 223,002,800 bytes written across all 50 repetitions.
Removing the audit host additions restores the canonical host text exactly.
WASI traces establish physical EOF/write ordering; buffering means they alone
do not establish when Scheme first called its writer. The unchanged source
recursion establishes that all lines are retained before that call.

The existing full-suite Rust Tail reference was inspected, not changed or timed.
It uses `BufRead::lines` (LF/CRLF), a `Vec<String>` of UTF-8 strings, and drops the
consumed input iterator before output writes. Scheme uses `List<String>`, keeps
input open until output closes, and strict Strings store Unicode scalars. The
Rust input parser also accepts only nonnegative counts. These boundaries must
remain explicit in a later comparison; canonical LF/count-50 agreement alone
does not establish matching noncanonical or resource-lifetime behavior.

## Verification and archive

`make test`, `make check`, all 35 Rust tests, Rust formatting, the full strict-I/O
Node tests, the focused native input tests, `scripts/test-backend` and
`scripts/test-build` pass. Actual linked Wasm and native tests cover malformed
UTF-8, CR lookahead failures, aliases, stale/wrong-direction handles, callback and
initialization traps, real read failures, storage independence, and growth up to
65,537 Unicode characters. Native input tests force collection on allocation.
All 32 preceding port specifications and generated strict programs remain exact.
The [focused review](review.md) records the independent behavioral explanation,
informed critique and deliberate exceptions to the ten-line target.

The archive retains ready preparation, the preliminary successful preparation's
records, exact sources and binaries, original input/output, complete file
fixtures, the separate audit host and commands, native provider inputs/runtime,
and focused library test artifacts. The initial formatting-check failure is
retained separately. Binaryen optimization remains mandatory for both production
targets; the raw linked Wasm is a diagnostic form only.

Restore and verify every archived byte without executing a workload:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-tail-replay \
  --report benchmarks/results/2026-10-14-strict-tail
```

The [protocol](protocol.md) gives the preparation and future comparison boundary.
Original absolute command paths remain unchanged in the records; hash replay
verifies contents and does not promise those temporary paths exist after restore.
