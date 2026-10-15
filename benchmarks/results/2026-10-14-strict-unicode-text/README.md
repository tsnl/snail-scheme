# Strict Unicode and String helpers

Implementation commit `2035bc2` adds the compiler's missing Unicode character
helpers and binary `string<?` in `(snail text)`. It starts from
`5be3958d38cb6115703bdb9508517bbb92fd08c9` in the separate
`work/strict-unicode-text-20261014` worktree. The completed writer worktree is
untouched. This evidence contains no benchmark timings or reduced compiler.

Three new typed Rust exports validate raw scalars and reuse existing simple
lowercase, Alphabetic and decimal-digit operations. Whitespace directly binds
the strict reader's existing scalar provider. The Scheme string loop checks
both ends and then the first unequal scalar; it never transfers a String to
Rust or changes input contents. No compiler algorithm or backend representation
changed. See [the contract](../../../doc/strict-text.md).

## Actual target checks

`scripts/test-strict-text` passes on raw linked Wasm, optimized linked Wasm and
native64. Each target executes 3,390 scalar cases and 148 String comparisons,
including empty/equal strings, proper prefixes, NUL, normalization differences,
BMP/supplementary ordering and long equal prefixes. Repeated comparisons after
four mutations check current contents; comparison with the same String is false.

The independent Python Unicode 16.0.0 oracle covers every changed lowercase
mapping and every decimal digit, plus fixed Alphabetic/White_Space cases and
seeded scalar samples. Its only full-to-simple lowercase correction is U+0130.
Superscript and Roman numeric characters are excluded from decimal membership.
Four newer native casing pairs remain unchanged under the existing Unicode16
mapping. All observed scalar fields also agree exactly between the three targets.

The tested Rust toolchain's native property version is 17.0.0, recorded by the
archived `char::UNICODE_VERSION` probe. Existing simple casing/decimal tables are
Unicode16. Alphabetic and whitespace intentionally retain the ordinary runtime's
native Rust property semantics rather than claiming an independent version pin.

Each target executes 16 deliberately malformed raw-scalar cases: four providers
times surrogate endpoints, U+110000 and U+FFFFFFFF. They report the expected fatal
diagnostic after flushing/releasing a pending file. WASI descriptor interception
and the existing native atexit observer verify release before terminal failure.
Native strings run with allocation-triggered collection enabled.

`cargo test --offline` passes all 46 tests on this base;
`cargo fmt --all -- --check`, `make test`, `make check` and `git diff --check` pass.
The archive retains both successful corpus runs, complete scalar output, cases,
source snapshots, tools, Wasm/LLVM/native artifacts, terminal records and process
cleanup. Every archive member was verified against `archive.json`.

## Review status

The pinned simplify workflow obtained a fresh no-history, no-files behavioral
explanation from a Sol6.1/max explainer. [review.json](review.json) keeps that
independent model separate from the implementing agent's later source comparison.
The local comparison selected direct Char externs, existing I32 predicate
encoding, the exact reader whitespace service and a single ordinary String loop.
Every production function stays within the ten-line logic target.

The follow-up informed debate is **pending**. Delegation returned
`agent thread limit reached`; the parent explicitly directed implementation and
actual-target checks to proceed while recording that incomplete review step.
This evidence does not claim the debate or the complete simplify review finished.

The benchmark-only Chez bridge remains the compiler agent's responsibility.
This worktree starts before the writer commit, so its standalone runtime cache
must not replace the combined compiler runtime without rebuilding after integration.
