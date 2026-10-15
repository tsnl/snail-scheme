# Full Tail diagnostics

The exact optimized Snail guest spends most sampled time in linked Rust scalar
I/O and UTF-8 work. Four frame groups account for **73.14% of weighted profile
intervals**. A separate counter guest confirms **223,002,850 scalar reads and
223,002,800 scalar writes**, plus substantial Scheme line construction. This
supports a narrowly controlled provider experiment; it does not establish a
lookup-only, allocator-only, or GC explanation.

The [clean comparison](../2026-10-14-strict-tail-comparison/README.md) remains
unchanged: full count 50, original 4,460,056-byte bibliography, medians 4.899608 s
Snail, 0.947096 s original Chez, 1.806730 s adapted Chez and 0.216239 s Rust/Wasm.
This report adds one profiler execution and one separate counter execution.
Their durations are diagnostics and do not enter those medians. The worktree
starts from `916ce7a7c2ca4d39a832275acbf1812b5390a1ab`; no production source,
library, compiler, input, or optimized reference artifact changed.

## Profile of the unchanged guest

The guest SHA-256 is
`23de40d54791743841fe3e9e93336872bd34ef6a8858607b136eb4cb92d2e33d`.
The inspector profiler starts after initialization; its start acknowledgment
precedes the original workload clock, and its stop follows that clock's end.
The configured interval is 1,000 us. There are 4,610 samples with 4,943,758 us
of nonnegative observed `timeDeltas`, a 4,944,594 us profile span including an 836 us
unsampled tail. Weighting uses the actual deltas, merges equal frames across
call-tree nodes, and partitions exclusive intervals. Inclusive ancestors are
preserved separately in [findings.json](findings.json) and overlap.

| Exclusive frame or group | Weighted intervals | Share |
| --- | ---: | ---: |
| Rust `read-character` | 1,980,013 us | 40.05% |
| Rust `write-character` | 1,147,592 us | 23.21% |
| Rust `read_utf8_char` | 324,116 us | 6.56% |
| Rust UTF-8 validation | 163,988 us | 3.32% |
| Scheme output loop, `function57` | 367,514 us | 7.43% |
| Scheme line builder, `function52` | 356,587 us | 7.21% |
| Identified V8 garbage collector frame | 256,117 us | 5.18% |
| String copy helper | 44,376 us | 0.90% |
| String allocation helper | 29,430 us | 0.60% |

The scalar provider frames combine `RefCell` borrowing, `BTreeMap` lookup,
direction/error checks, codec work and buffered I/O. Inlining changes where
samples appear. Calls from Scheme into these Rust services are direct linked
Wasm calls. Buffering means a scalar call is not one JavaScript crossing or one
syscall; separate WASI frames are visible in the raw call tree. The retained
observer measures file bytes and lifecycles, not actual `fd_read`/`fd_write`
request counts. The identified GC share neither measures every allocation cost
nor supports subtraction of GC from another runtime's total.

The enclosing profile begins roughly 7.4 ms before the workload clock; profiler
submission/acknowledgment/completion and workload clock markers are archived.
The raw profile bounds numerically fall inside the corresponding submission
and completion brackets, consistent with a shared monotonic domain on this
host. This is an observed alignment, not a portable clock conversion promise.
Shares use the enclosing sampled window without interpolating exact timer
boundaries. Sampling, inspector activity and file observation add overhead.

## Separate executed work counters

Erasing every added WAT statement recovers the original optimized WAT exactly.
Only scalar I32 locals and I64 counter globals are appended after original
declarations. Each original length operand is evaluated once, captured with
`local.tee`, and used for the count; reference lifetimes receive no extra locals.
No functions/imports are added. Binaryen assembles this diagnostic derivative
without reoptimizing it. Host counter reset follows initialization; snapshot
immediately follows the workload clock and precedes guest result inspection.

| Work across all 50 repetitions | Executed count |
| --- | ---: |
| Completed line results and reversed list nodes, each | 1,555,100 |
| Completed EOF variants | 50 |
| String requests and completed primary arrays, each | 7,032,450 |
| Line buffer growth requests | 3,939,050 |
| Final trim requests | 1,538,300 |
| Requested/completed primary I32 cells | 754,545,300 |
| Completed nonempty `array.copy` sites | 3,922,250 |
| Copied I32 cells | 437,191,700 |
| Directory/secondary arrays | 0 |

Independent input statistics and the source growth rule predict the matching
13 site/cell totals. The ASCII bibliography has 31,102 nonempty LF-terminated
lines, maximum 537 characters. Each retained line starts with an empty String,
grows from capacity 64 by doubling, and trims unless exact. There are 5,477,350
copy-helper requests, including 1,555,100 zero-length first-growth copies that
execute no `array.copy`. Logical requested character storage totals 3,018,181,200
bytes and logical copied character payload totals 1,748,766,800 bytes. These
are operands/site counts, rather than physical heap allocation, bytes moved by
the engine, live memory, or GC collections.

Both full-count runs passed all 4,460,056 final output bytes and unchanged input,
result `1`, 100 successful opens/closes, 49 deletions, ordered input/output
cleanup per repetition and 223,002,800 observed file bytes in each direction.
Every repeat's transfer volume and lifecycle were observed; the byte oracle
checks the final actual output file. No claim is made about independently hashed
intermediate output contents or host chunk ordering within a repeat.

## Scope and next question

Original Chez uses native `get-line`/`put-string`. Adapted Chez uses the Scheme
character loops with native port operations and is 1.908 times original Chez
time. Rust uses buffered UTF-8 `Vec<String>` lines and writes strings; it closes
input before output writing, while Scheme keeps input until output closes.
Rust's nonnegative count parser and CR/LF handling differ outside this canonical
count-50 LF input. Scheme Unicode I32 buffers, list nodes, Rust UTF-8 storage,
lifetimes and runtime implementations all remain material differences. The
sampled medians and this profile do not isolate any one of them.

The parent authorized a separate diagnostic provider experiment: replace only
the ID lookup container, preserving scalar ABI, borrowing, codec, buffering,
cleanup order and the exact Scheme program. The baseline/candidate must be
rebuilt from one frozen source/toolchain, fully linked through mandatory
Binaryen, validated before coordinated timing, and reported separately. An
indexed table retains holes proportional to historical opens and is not an
authorized production representation.

## Reproduction and closed evidence

[diagnose.py](diagnose.py) records actual commands and raw attempts before
validation. `profile` and `counters` create fresh real file trees, clear Node
injection variables, reject `LD_PRELOAD`, and pin execution to CPU 5. `summarize`
recomputes weighted shares and independently checks the growth/copy predictions.
Absolute original paths are preserved in the records and archive mappings.

`artifacts.tar.xz` and `manifest.json` retain complete raw profiles, clock
markers, actual input/output files, WAT/counter and host erasure ledgers,
commands, identities, source predictions, two failed preparation attempts, all
original strict case/compiler files and the prior clean-comparison archive.
External tools are identified by path/hash rather than vendored. The archive
is restored and every regular file hash checked in `archive-verification.json`;
that integrity check adds no timing or guest execution. The two preparation
failures happened before a counter guest was assembled or run: one unmatched
indentation, then an unscoped String-call match. Their source/error records
remain intact. [measurement-review.md](measurement-review.md) records the
bounded independent explanation and critique.
