# Reusable strict datum output

This is correctness evidence for the compiler benchmark's output prerequisite.
It contains no benchmark timings or reduced compiler workload. The implementation
starts from `5be3958d38cb6115703bdb9508517bbb92fd08c9` in the isolated
`work/strict-datum-output-20261014` worktree. The implementation commit is
`43c8929` (Add typed datum output and borrowed stdout).

`(snail write)` implements named `write-datum` and `display-datum` functions and
default/explicit-port `write` and `display` overloads. It formats all nine existing
Datum variants and reuses `number->string` for arbitrary exact and complex
numbers. A local graph inspection distinguishes cycles from sharing; explicit
continuations render lists and vectors without machine-stack recursion. Cyclic
graphs use first-output-order definitions/references, including shared string
and bytevector storage. Pair/vector aliases follow existing backing-storage
identity rather than private recursive-view IDs.

`(snail io)` supplies stable `current-output-port`, `output-port=?` and default
character/string/newline overloads. Stdout is a borrowed scalar ID outside the
owned-file registry. Scheme and raw scalar close both leave it usable. Empty
string writes validate the port. The Rust scalar provider is shared by linked
Wasm and native64 and retains no Scheme values or roots.

## Executed checks

| Check | Result |
| --- | --- |
| `scripts/test-strict-write` | 68 exact datum cases, readable round trips, eight graph cases, depth 8192, six terminal failures on raw/optimized linked Wasm and native64 |
| Chez graph oracle | Labels, ordinary sharing expansion and shared-tail notation agree, with the explicit `#vu8` to strict `#u8` spelling adapter |
| Isolated stdout check | Exact Unicode output after both close entry points on all three targets; two native resources released and no standard descriptor closed |
| `scripts/test-strict-io` | All eight existing raw/optimized linked file/input/trap forms pass |
| `cargo test --offline` | All 47 Rust unit tests pass |
| `cargo fmt --all -- --check` | Pass |
| `make test` | All host/compiler tests pass |
| `make check` and `git diff --check` | Pass |

The archive retains sources, exact input/output files, tool identities, Wasm/LLVM
and native artifacts, native input hashes, supervised commands, stdout/stderr,
exit status and process-group cleanup records. Its manifest hashes each member.
The final suite reuses the initial compiled artifacts only after verifying their
Scheme/Rust inputs and the actual native C-host input record.

Two test-host corrections are retained. The first Node driver required a
WebAssembly exception for fatal I/O, but the existing runtime correctly invokes
WASI `proc_exit(1)`; the final driver observes that exit separately from an
explicit Scheme trap. The native host needed the repository's existing atexit
resource observer to expose its release count. That C correction preceded the
native build, and its actual input hash is in `native.native-*/build.json`; the
initial source snapshot predates it. Neither correction changed compiled Scheme
or Rust. An interrupted redundant smoke compilation and the initial missing
observer assertion are also retained.

## Focused simplify review and limits

The pinned simplify workflow used a fresh independent behavioral explainer,
followed by informed critique before implementation. The agreed model separates
graph inspection from rendering: table membership records visits, active entries
detect cycles, repetition selects labelled values, and assigning a label before
children closes cycle edges. The renderer needs no second ancestor history.
Exhaustive atomic formatting dispatch remains together despite exceeding the
ten-line target; the cases explain the complete scalar spelling contract.

Cycle rejection was rejected because compiler diagnostic nodes can contain
parent/child cycles. Always escaping symbols was rejected because ordinary
variable spellings matter. A cdr-only cycle detector would not inventory shared
vectors, strings or bytes. Direct linear identity lookup preserves existing
alias semantics without changing backend representations; its worst case is
node encounters times table entries, as documented in `doc/strict-write.md`.
The pass stopped when those phases and their lifetime decisions were directly
visible in the new module.

The strict reader still rejects graph labels. Cyclic `display` deliberately uses
finite graph notation; Chez's diverging behavior is not reproduced. Strict
symbol/bytevector syntax and the absence of Chez's implicit cycle warning are
documented differences. Current output is fixed stdout; dynamic rebinding and
non-Datum diagnostic objects remain outside this API.
