# Exact native-final Wasm control

The native build starts from production `strict.wasm` (SHA-256
`f047b9cfbebd9127dfde44fb28efd80a9f3da1bd736352218e05e5f325013f46`), then
performs additional Wasm optimization before emitting LLVM. Its final module is
39,444 bytes with SHA-256
`dfb9d40d9544334b3328aa041cbff50d30f40b28a65fc6bb690ea0e62f7e31cd`.

The seven-system plan adds V8 execution of those exact final bytes. One
preparation execution at count 2,500 passes the complete result predicate with
5,000 opacity calls. Its stdout duration is correctness provenance only. The
original production V8 module remains a separate control. No compiler/native
rebuild or repeated source-probe campaign was performed for this correction.

This supplemental archive contains the final Wasm/disassembly, generated LLVM,
compiled provider object, actual Rust runtime archive, complete native build
record, preparation script and full-count validation record. Final build files
are checked against attempt 5's hashes; the Rust archive is checked against the
native build's recorded hash before copying. Earlier preparation evidence is
unchanged.

```sh
python3 benchmarks/strict-suite/replay.py /tmp/matrix-native-final-replay \
  --report benchmarks/results/2026-10-14-strict-matrix-preparation/native-final-control
```
