# Frozen Rust Destruc handoff

This handoff reuses the validated canonical Rust/WASIp1 executable for 4,000
invocations of `destructive(600,50)`. The exact original input and complete
ten-row expected result are preserved; row lengths are
`3,3,4,4,5,5,5,5,5,21`. All 60 cell values participate in the final predicate.
No canonical source or binary changed, no canonical rebuild occurred, and no
clean timings were run for this handoff. Work started in an isolated worktree
above `767fced0cf11663c60061f3195266769310d7097`.

[handoff.json](handoff.json) records artifact
`864395a09bda5cf03515c065585d7b77eb9cc3aa7d9961dd5ca4c94ce60ed074`
(123,858 bytes), the exact 45-file build-source snapshot, Node/WASI host, original
stdin, commands, tool identities, complete output predicate and timer boundaries.
Its source module SHA256,
`d96cd84dfa8c2ba66a3fabcb2519112dd2d143ea8e0c0c21a6ae48d8d329d666`,
matches the current integrated source. Historical full-count Node/Wasm and
original Chez success remain in the unchanged validation report.
[build-provenance.json](build-provenance.json) keeps the offline release
workflow/profile and original reader/library snapshot; the historical record
does not include a verbose rustc log or full inherited build environment.

The [source audit](source-review.md) traces growth, descending iteration labels,
both length walks, half-prefix writes and transfer of actual detached suffix
cells. Ten outer Vec slots replace the outer mutable list spine; inner cells
remain linked, uniquely owned Boxes with inline empty/integer payloads. Disjoint
rows permit ownership transfer without copying or a general mutable-pair arena.
Strict Scheme instead uses mutable nominal nodes, head/tail Refs and Item
variants; original Scheme uses mutable pairs and GC. Rust and the explicit strict
kernel both split the source before destination writes, while Rust scans target
length earlier. Reclamation, container layout, integer widths and traversal
timing differ and are part of this comparison.

The [retention audit](retained-work.json) ties these operations to the exact
optimized Wasm. It retains the original count loops, growth/append walks,
prefix stores, tail transfers and recursive cleanup. Rust converts its complete
final rows into generic datums, including decimal integer atoms, then compares
every value inside timing. This existing extra materialization differs from
Scheme's direct equal? comparison. Discarded tails and previous invocation
results free inside timing. Final datums and the last owned rows survive the
stopped clock and reporting, then free afterward. No extra per-node audit or
opacity was added to the frozen timed loops.

[Supplemental correctness](supplemental-correctness.json) contains 33 actual
runtime executions. A separately compiled original Chez oracle retains the
unchanged destructive procedure, replacing only its final driver invocation
with untimed complete observations. Twelve shapes cover zero/small inputs,
empty payloads and odd/even split sizes; a thirteenth repeats a small case.
Every Rust result element and row length agrees with the complete original
oracle. Both frozen Rust and original Chez reject same-size first-value
corruption, final-row truncation and a wrong empty payload. Their raw CSV
durations are correctness evidence, not clean performance samples.

The native suffix-pointer unit test remains separate from these actual-Wasm
value checks. A full Wasm identity/allocation/mutation trace and a fresh
independent no-file mutable-list explanation/debate are not claimed. The older
review cohort remains pending. Nonnegative Wasm32 inputs, owned acyclic rows,
canonical integer spellings and bounded destructor depth limit equivalence
outside the checked inputs. Default Ackermann failure and the optional variant
remain separate elsewhere in the full suite.

`artifacts.tar.xz` contains all 61 frozen handoff files as 61 verified blobs;
its SHA256 is
`275bd6511293d4ae877ed6ff59b598b95a14a2c566095d46a603d79163f788d5`
(178,320 bytes). [manifest.json](manifest.json) maps relative file paths to
content hashes; [archive-verification.json](archive-verification.json) records
every successful post-pack blob check. The archive preserves sources, binaries,
exact input, old and supplemental observations, complete original Chez oracle,
tool/build provenance and disassembly. Restore each `files[path]` entry from
`blobs/SHA` beneath a chosen scratch directory, verify its SHA256, then substitute
relocated file paths while keeping exact tool identities, CLI, stdin, working
directory policy and result contract. Clean comparison remains parent-coordinated
and uses the original 4,000 repetitions.
