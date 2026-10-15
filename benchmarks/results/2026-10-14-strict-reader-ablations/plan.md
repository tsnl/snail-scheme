# Independent reader ablations

This is the historical plan declared before preparation on 2026-10-14.
The prospective wording below describes that preparation stage. Preparation,
freeze and the 60-process campaign are now complete; [README.md](README.md)
and [audit.json](audit.json) supersede its readiness statements. The frozen
machine-readable timing plan and measured artifacts remain unchanged.

All three sources start at `c0ba036499de55622538fc4c077fb8951b510502`, which
contains the reader diagnostics and Browse's concrete datum helpers. Their
compiler code, selected Chibi/Node/Binaryen tools, original workload sources,
input files and counts remain the same. Candidate library/provider source
differences are explicit; no older native or production artifact is substituted.

- **Baseline:** unchanged current compiler and libraries.
- **A, delimiters:** replace membership in the twelve constant delimiter scalars
  with direct Scheme scalar equality. EOF and Unicode whitespace keep their
  original short-circuit order; lookahead and atom staging stay unchanged.
- **B, staging:** keep A's original delimiter-string scan. Stage an ordinary
  atom once, preserving numeric parsing, numeric errors, identifier checking
  and symbol interning order. Move the existing data-only `ReadResult` into
  datum and re-export the unchanged reader API. The datum wrapper keeps handles
  private and closes or consumes exactly once before returning, with no user
  callback while owned. Only parsed nonnumbers may transition into interned
  text; parsed numbers/errors remain rejected. Quoted-symbol Text handling
  remains unchanged. Chez's existing scalar mock retains parsed text and
  mirrors this ownership transition.

The pinned simplify explanation/review is owned by root. It preferred a shared
existing result over a new public result hierarchy or callbacks. Code inspection
must retain any extra intermediate result constructors in the evidence rather
than presuming Binaryen or V8 removes them.

After the numerical campaign's explicit release, prepare each candidate with
the existing reader workload builder. Reuse `scripts/test-strict-reader` for
the complete original 84 streams/errors/UTF-8 cases and A's focused delimiter
adjacency/member/nonmember extensions. Check all twelve members, EOF,
Unicode whitespace and representative nonmembers through public reader inputs.
B's module-final datum tests use Browse's established exact test-body extraction
and the existing raw/optimized/native builder and hosts. Rust transition tests
check consumed successful/rejected handles, survivors and duplicate symbols.
Complete canonical field streams, every full-count EOF/close cycle, malformed
ordering and trapped cleanup must pass. Sum1 remains 25 complete reads of its
100,000-number file; Read1 remains 2,500 reads through all five datums.

Relevant Scheme/Rust formatting and unit checks run before source commits and
artifact freezing. Rust provider changes require actual native execution as
well as raw and optimized linked-Wasm execution in Node. Typechecking and the
reference Chez adaptations must work after the shared result moves.

The clean campaign reuses the reviewed `measure-seven.py` runner unchanged,
with its accepted frozen supervisor dependency closure and origin checks.
Only production linked Wasm/V8 is timed: `strict-v8-baseline`,
`strict-v8-delimiters`, and `strict-v8-staging`. Each workload has one
predetermined discarded round followed by nine retained rounds. Three-position
rotation gives each candidate three appearances in every within-round position.
This is **60 fresh processes** at full canonical counts. Run Sum1 before Read1,
serially on CPU 5, with normal V8 tiering, no instrumentation or heap overrides,
the original setup-before-clock host, and both workload/process clocks retained.
Every result must pass. No sample replacement or adaptive exclusions are planned.

Freeze the exact commands, inputs, source/tool/artifact identities and accepted
supervisor modules before requesting a quiet release. All preparation handles
must be terminal first. Root coordinates the quiet window; builds, guests,
profiling, compression and publication pause during it. Any failed campaign
remains retained and is not silently repaired. The OS file cache is uncontrolled;
the discard round warms it. Report medians and observed ranges, with no
confidence-interval claim and no conflation with the earlier allocator basis.
