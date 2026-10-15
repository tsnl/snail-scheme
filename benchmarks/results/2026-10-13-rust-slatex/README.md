# Complete SLaTeX reference validation

Rust/WASI and the untouched original Chez implementation pass the original
500 repetitions over `inputs/slatex-data/test`. Every generated filename,
byte count and SHA-256 digest agrees: **28,500 files, 2,865,500 bytes per system**.
The original result predicate always returns true. Complete-file comparisons
are additional checks after execution, outside either workload timer.
These runs are correctness evidence and contain no performance samples.

[Validation summary](validation-summary.json) retains source/tool/binary hashes,
execution diagnostics and complete-file-set hashes. The exact original report,
including every file digest, is [compressed separately](validation.json.xz).
[The archive](artifacts.tar.xz) contains frozen Rust sources, original inputs,
the compiled original Chez source/binary, the linked Wasm binary, every generated
Rust/Chez file, and retained-work disassembly. All 57,178 regular files and nine
normalized relative links were independently replayed against its manifest.
[Archive metadata](archive.json) records that verification and its SHA-256.

The exact runtime source is SHA-256
`33d77cf4d434098324b5b9deb392a71c2d36a09b13a93d04c6ff5b6d7ebb0d1a`;
the actual Wasm is
`9796ffad9d8020de28bc28f3c852faa5628c4b04938065b268da3f3810ecd0f4`.
The upstream revision is `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`.

Three independent complete file graphs cover fonting/quotation/case/alignment,
aliases/database controls/math/protected regions, and repeated includes plus
Scheme input. [Supplemental checks](supplemental-checks.json) verify destructive
character escaping and tab cleanup, and reject corrupted, missing or extra
generated files and changed plain-TeX marker contents. The supplemental runner
adds those tests and correct isolated directories for future wrong-result
probes; the frozen canonical runner is preserved. SLaTeX cannot reject a wrong
expected datum because its original predicate ignores both expected datums.

[Retained-work evidence](retained-work.json) identifies the optimized Wasm loop's
file-processing call, actual Scheme formatting and character-list mapping,
and WASI reads/writes. Only the input filename crosses an explicit optimizer
barrier. No extra result traversal or validation was inserted into timing.

Token databases, scanner state, auxiliary counters and two 200-character line
buffers persist as in the source. Include saves/restores the primary counter;
all 500 repetitions generate their accumulated file set. Character lists use
owned boxes and destructive append/reverse; quote frames are boxed and their
outer stacks/databases use vectors. Rust ownership replaces tracing collection.
The source's Unix path/newline rules and mismatched arrow-escape rewrite are
preserved. Long scanner, delimiter and trigger dispatches keep atomic state
transitions together. The focused independent simplify review remains pending.

Reproduce linked validation from this checkout with:

```sh
cargo build --offline --release --target wasm32-wasip1 \
  --manifest-path benchmarks/wasm-reference/Cargo.toml --bin slatex
python3 benchmarks/wasm-reference/suite.py --benchmarks slatex --checks full \
  --output build/slatex-reproduction
```

The suite uses isolated execution directories and compares complete outputs.
Extracting `artifacts.tar.xz` exposes `full/validation.json`, `full/cases/slatex`,
`full/reference-source`, `full/inputs`, `retained-work/slatex.wat` and the
per-file `manifest.json`. The recorded command paths describe the original
execution; run commands can be rebuilt around the extracted paths.
