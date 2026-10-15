# Clean Browse retained work

`inspect-retained-work.py` records evidence from the exact successful artifacts
in `build/browse-attempt2`. `retained-work.json` contains their hashes, direct
call paths and operation counts. The archive includes the complete disassembly
and the selected WAT/LLVM/machine-code excerpts under this report directory.

The source recorder `tests/strict-browse/source-map.scm` runs the same frontend,
monomorphization and Wasm emission as the clean build. Its output WAT is byte
identical to `strict-native.wasm.wat`; the map identifies `my-match` as
`function239`, its named-star local loop as `function240`, `investigate` as
`function242`, and its nested loops as `function243`, `function244` and
`function245`. The counted worker loop is `function252`.

| Artifact | Retained clean path from `bench` |
| --- | --- |
| Raw linked Wasm | `export0 → function251 → function252 → function241 → function242 → function243 → function244 → function245 → function239` |
| Binaryen-linked production Wasm | `export0 → function252 → function243 → function244 → function245 → function239` |
| Native-final optimized Wasm | The same optimized Scheme path; scalar services remain imports from `snail.library` |
| Actual native executable after LLVM/LTO | `main → f.105 → f.102`, where `f.102` is `function239`; `f.103` is the named-star loop |

The optimized three investigation loops retain their list-tail recursion.
`function245` still drops the result of a real call to `function239`. The outer
worker retains its count comparison, count increment, opaque barrier, both
result maps, recursive repetition and complete datum-equality predicate.

The optimized matcher retains five direct recursive call sites, two symbol
length/string-construction paths, association lookup, reused-variable append,
the named-star loop and twelve struct construction sites. Its local star loop
retains nine struct construction sites and the call to `append-to-tail!`;
that helper retains the tail-field mutation. These are static sites, not
dynamic allocation counts. Closed Datum and MatchResult types remain concrete
in the WAT; no generic Top fallback is introduced by the adapter.

The native-final function order maps `function239` to LLVM `f.102`, `function240`
to `f.103`, `function252` to `f.108` and the export wrapper to `f.109`. LLVM may
inline the last two into main. Actual executable disassembly confirms a call
from main to `f.105`, a call from there to `f.102`, three ordinary recursive call
sites in `f.102`, and a call back from `f.103`. Allocation slow-path calls also
remain in the matcher. This inspects the final executable, not only its LLVM
input.

These static checks address the discarded matcher result directly. They do not
derive matcher execution from final database equality or from tracing-build
behavior. The five-path internal traces establish ordered agreement only at
the documented counts 1 and 2; full-count clean executions and this retention
inspection provide separate evidence for the canonical 2,000-worker program.
