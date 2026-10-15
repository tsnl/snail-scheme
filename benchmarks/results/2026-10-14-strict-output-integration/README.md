# Combined strict writer and Unicode validation

The writer and Unicode additions pass together at
`0a92160cc264bb6eef22dc37bec4e3440856132b`. The shared Rust runtime was rebuilt
from the combined source; neither feature's standalone runtime cache was used.
The parent inspected the graph traversal, scalar I/O ownership, Unicode
providers and string-ordering loop before this integration check.

All seven commands completed successfully: `make test`, `make check`,
`cargo test --offline` (47 tests), `cargo fmt --all -- --check`,
`scripts/test-strict-write`, `scripts/test-strict-text`, and
`scripts/test-strict-io`. The outer process reached actual exit 0, tool chunk
`2e3655`. Source identities and the tested Git revision remained unchanged
through the checks.

Writer checks execute 68 exact write/display cases and readable round trips,
eight graph cases, depth 8,192, stdout ownership/defaults and six terminal
failures on raw linked Wasm, optimized linked Wasm and native64. Unicode checks
execute 3,390 scalar cases, 148 string comparisons, mutation checks and 16
malformed raw-scalar failures on each target. The eight existing linked I/O
regression forms also pass. These are correctness checks, with no performance
measurement or claim that the complete compiler benchmark is ready.

[checks.json](checks.json) records commands, identities and validation summaries.
[diagnostics.tar.gz](diagnostics.tar.gz) retains 857 source, capture and command
files; every member was read back against [archive.json](archive.json).
The archive also records identities of 98 omitted Wasm/LLVM/native artifacts
that remain in the isolated build tree. Artifact inspection and the individual
fresh behavioral reviews remain in the
[writer evidence](../2026-10-14-strict-datum-output/README.md) and
[Unicode evidence](../2026-10-14-strict-unicode-text/README.md).

No implementation changed during parent review. The graph table's linear
identity lookup preserves the existing storage contract, the Unicode boundary
reuses established property tables, and the string loop requires no cached
ordering or auxiliary representation. Further refactoring was not justified by
this integration pass.
