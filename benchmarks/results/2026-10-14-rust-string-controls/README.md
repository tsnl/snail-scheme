# Rust String storage controls and Puzzle handoff

This report freezes correctness and retained-work evidence for the separate
[String controls](../../string-reference-controls/README.md), source commit
`15b685c9f67a6d194d10013425efe1d8919e848f`, above the preserved full-suite integration
`748dbb75fe78e4ffd9a401ff194ad2591646cb75`. It also preserves the already validated
canonical Rust Puzzle timing handoff. It contains no performance samples and
does not change canonical57 coverage: 57 sources, 56 default full-count passes,
with the default recursive Ackermann stack failure still separate from the
optional heap-frame implementation.

The four String modes retain the original 100 invocations, ten trials each,
threshold500000 and expected length524278. Each growth constructs four fresh
owned buffers and both overlapping substring copies. Complete original-size
Node/Wasm checks, threshold boundaries and wrong-result checks pass in all four
modes. The unchanged original Chez driver passes full input and small/wrong
checks; an additional untimed original-source oracle agrees on every payload
element, including threshold500000. Complete audits recompute an extra trial
after timing; they are not the last timed output.

Separate instrumented runs confirm the retained optimized Wasm operations:

| Mode | Element bytes | Selected allocations | Requested bytes | Reached zero fills |
| --- | ---: | ---: | ---: | ---: |
| byte | 1 | 61,000 | 3,145,173,000 | 0 |
| u32 | 4 | 61,000 | 12,580,692,000 | 0 |
| byte-zeroed | 1 | 61,000 | 3,145,173,000 | 61,000 |
| u32-zeroed | 4 | 61,000 | 12,580,692,000 | 61,000 |

The selected count includes 1,000 seeds and 60,000 growth allocations. Zeroed
fills cover the logical requested byte volumes. These are reached Wasm
instructions and allocation requests, not newly resident pages or physical
traffic. Removing the instrumentation recovers the exact original optimized
WAT; full-count unmodified reassembly gates precede instrumented checks. All48
complete-payload replays pass on both transformed artifacts. Five native tests,
formatting and release Wasm Clippy with denied warnings also pass.

Both fresh no-history/no-file explanations and informed debates are complete.
The [review account](focused-review.md) records ownership, opacity, predicate
and instrumentation reasoning; [retained-work.json](retained-work.json) ties
the source claims to exact disassembly lines and dynamic evidence. Earlier
immutable handoffs and probe records retain their then-pending review/source
fields. The new [supplement](source-review-supplement.json) supplies completed
current status without rewriting those historical files. Older full-suite
review cohorts and the portable full-suite timing driver remain separate work.

The Puzzle handoff reuses artifact
`6922c6bc58940ee87ea46e9f6b886ae88a94709e23316b19b0e89aaeb10228bd`,
count1000, size511, result2005, with 44 verified exact-source files. It records
the local nonescaping continuation's Boolean-return adaptation, persistent
board/template ownership and scalar predicate boundary. Its full-board checks
are native tests; actual Wasm full-count/small/wrong checks establish the supplied
scalar predicate. Its new build-workflow supplement corrects a historical-build
selection detail while preserving the immutable handoff and provenance hashes.

`artifacts.tar.xz` contains144 content-addressed blobs and the exact
`manifest.json`. Its SHA256 is
`31474655bef0756a8d15f21b042c5b1ccf8047af6747daafc26242f58ec74f6f`
(601,048 bytes). Every blob's length/hash and all243 original path mappings were
verified after packing; [archive-verification.json](archive-verification.json)
records those checks. `restore_paths` maps these same blobs into a portable
scratch layout, while `mapped_files` preserves the original absolute provenance.
The archive includes sources, pinned tools/environment records, verbose build
log, primary/reassembled/instrumented binaries and disassembly, original Chez
source/binary/oracles, raw validation output, the two failed preparation attempts,
and both timing handoffs. Relocated commands require substituting file paths
while retaining tools, stdin, modes, working directory and predicates. External
tool binaries and Cargo registry packages are identified rather than vendored.
