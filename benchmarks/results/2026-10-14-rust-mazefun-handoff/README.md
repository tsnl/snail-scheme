# Corrected canonical Rust Mazefun handoff

This handoff freezes the original 10,000 complete `make-maze(11,11)` calls and
the full supplied 121-cell grid. It contains **no clean timing samples or
performance claim**. The [source audit](source-review.md) covers shuffle, ordered
flooding, persistent sharing, the complete predicate and representation/lifetime
differences. Typed-source Chez remains a separate control in the
[strict Mazefun preparation](../2026-10-14-strict-mazefun/README.md).

Source correction `cbbe0cc7e13d82315f46d01fa90e61ab489a31e6` fixes the driver:
string/vector kinds and longer symbol spellings no longer satisfy grid equality;
signed nonpositive counts retain original initial false; even dimensions return
symbol `error`; negative odd dimensions keep the original empty construction
behavior. Exact signed labels remain visible. The direct timed predicate compares
the untouched decoded datum, with no invalid sentinel or second expected grid.
Successful comparison precedes stopped-clock capture. Rust rejection panics
without normal result/CSV; original Chez prints `INCORRECT`.

The corrected artifact is
`4e1f45f9c925dde00788408ab97b262c77c7201967c7b49768970bcd50efd885`
(125,246 bytes), built offline from the exact 101-file project snapshot with Rust
1.95/LLVM 22.1.2, release opt-level 3, LTO, one codegen unit and panic-abort.
[Build provenance](build-provenance.json) retains actual verbose rustc commands,
selected environment, tool/executable hashes and the complete build log. External
sysroot/dependency binaries and the full inherited environment are not vendored.
The canonical kernel is recoverable byte-for-byte after only explanatory comment,
function-name and relocated parity-assertion reversals, recorded in
[kernel identity](kernel-source-identity.json).

Historical artifact
`3135aee9c875779a11061aa679e5734d4d8e1fb90e529c48b2bba06ac6679cd8`
(126,070 bytes), its 49-file source snapshot, original input, validation and
disassembly remain unchanged under `historical/`. Historical full-count success
remains evidence for that artifact. Separate historical probes retain its actual
false acceptances of string/long-symbol/vector expectations and its failures on
zero-count false and even-dimension error; the old CSV durations are not clean
samples or observations of the corrected artifact.

[handoff.json](handoff.json) gives immutable source/artifact/host/input identities,
exact command/cwd/stdin and acceptance rules. The input is still count 10,000,
11 by 11, SHA256
`38c693aaa745e91ed261ff5c4e4999126ab70c6d4c4b55c61510ba0eef3b3644`.
Startup, compilation, instantiation and input decoding are untimed. Initial false,
every cave/hole/shuffle/flood/result construction, intermediate and prior-result
cleanup and full supplied-result equality are timed. Result/CSV printing and final
result cleanup follow clock capture. Reject failures, missing/partial results or
missing/wrong/non-numeric CSV rows. The complete canonical serialization is 266
bytes including newline, SHA256
`542def81e0d8c5e0b1e9006b0a5d1edff63abd25e77649088893b7b586c14a76`.

Rust uses persistent `Rc` cave/shuffle/result lists, inline coordinate/wall values
and character marks. Temporary neighbors, IDs, hole collection and output mapping
use vectors. Coordinate/neighbor/ID/append/size-pair objects and strict I64/product/
variant layouts differ. Reverse iterators invoke pure matrix callbacks in reverse
while producing increasing lists. All hole/shuffle/neighbor/flood value order is
preserved; matching physical allocation/evaluation schedules are not claimed.
Last-owner intermediate cleanup happens inside each invocation. The prior result
stays owned during construction of its replacement and is released afterward;
the final result is released after stopped clock and output. Scheme collection
has different reclamation and liveness behavior.

[Supplemental correctness](supplemental-correctness.json) preserves 72 actual
corrected-Wasm/original-Chez executions of 36 targeted fixtures: canonical counts
1/2/10,000, complete small/non-square/skinny grids, even/zero/negative dimensions,
nonpositive counts, exact signed labels, and result-kind/list-shape/late-mark
rejections. Fourteen original complete-output oracles supply all dimension results.
The frozen suite runner additionally passes 16 executions of four committed
regression fixtures, recorded in [fixture checks](fixture-correctness.json).
The [parent check](parent-canonical-check.json) independently executes the same
frozen full-count artifact and checks all 121 mark symbols and parentheses.

The [retained-work audit](retained-work.json) derives a separate 24-site observer
from the exact release disassembly. Erasing only counter insertions recovers that
text exactly. Feature-limited assembly performs no reoptimization. Every selected
kernel counter scales exactly across repetitions:

| Executed observer site | Count 1 | Count 2 | Count 10,000 |
| --- | ---: | ---: | ---: |
| Complete maze invocation | 1 | 2 | 10,000 |
| Initial cave cells | 121 | 242 | 1,210,000 |
| Shuffle advances | 60 | 120 | 600,000 |
| Piercing attempts | 60 | 120 | 600,000 |
| Flood entries including no-ops | 1,250 | 2,500 | 12,500,000 |
| Neighbor entries | 720 | 1,440 | 7,200,000 |
| Complete output mark nodes | 121 | 242 | 1,210,000 |
| Complete output row nodes | 11 | 22 | 110,000 |
| Final row comparisons | 11 | 11 | 11 |
| Final mark comparisons | 121 | 121 | 121 |

Full-count wrong-last-mark rejection keeps every kernel count unchanged, reaches
all 121 mark comparisons and reads only the starting clock, with no result/CSV
print. Successful runs read two clocks. Prior-result top-level release counts
are `N-1` inside timing; the final release follows both prints. Zero-count false
performs no kernel work. Counters describe observer residual functions/sites,
including only retained write-function entries rather than inlined write levels.
They are not total allocation, V8 physical GC allocation, native instruction or
uninstrumented timing counts. The canonical artifact has no observer code.

Ten native tests, fmt, release Wasm Clippy and `make check` pass. A fresh
no-history/no-files Sol 6.1 max explanation and one informed critique accept the
direct state/predicate correction, with no further kernel refactor; the
[bounded review](independent-review.json) records the decision. The reader/domain
claim is restricted to canonical boolean/symbol/proper-list syntax, signed decimal
i64 count/dimensions and manageable Wasm32 storage. Alternate boolean/numeric
syntax, escaped boolean/numeric-like symbols, proper dotted-tail list encodings,
malformed trailing input and exceptional/huge resource behavior remain outside it.
Other structural/SLaTeX reviews remain separate.

`artifacts.tar.xz` and [manifest.json](manifest.json) preserve corrected and
historical source, binaries, hosts/input, complete outputs, raw observations,
observer artifacts, source patch and build/tool/review provenance. Failed observer
preparations remain under `failed-attempts/`: a newline assumption and unsupported
Binaryen compact imports. Both failures left the canonical program unchanged.
The [archive verifier](archive-verification.json) restores every mapped byte;
[relocated replay](replay-check.json) separately checks count-one Rust/original
Chez output and unchanged source/tool/artifact hashes. Preparation scripts retain
their original layout assumptions. The [protocol](protocol.md) makes restoration,
relocated commands and future unshortened quiet timing explicit. Parent controls
that campaign. The live checkpoint selects this corrected artifact while keeping
historical evidence separate; the full-suite historical archive is unchanged.
