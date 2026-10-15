# Rust partial evaluation and parsing correctness checkpoint

Both unchanged canonical workloads pass in Rust/WASIp1 on Node/V8 and in the
independent compiled original Chez controls. These are correctness observations;
embedded elapsed times are not retained performance samples.

| Workload | Original count | Original result predicate |
| --- | ---: | --- |
| `peval` | 2,000 | Ten residual programs; the tenth is the constant alphabet reversal procedure |
| `parsing` | One outer invocation, 2,500 inner parses | Complete `(should return this list)` from the original file |

[Peval validation](peval-validation.json) includes a complete ten-example audit
after timing. It compares lexical alpha equivalence because R7RS leaves map
application order unspecified; Rust chooses left-to-right renaming. The audit
preserves free/quoted symbols and rejects capture and swapped parameter uses.
Canonical validation retains the original exact tenth-result predicate.

A subsequent [oracle review](alpha-oracle-review.json) found that the original
checker ignored trailing lambda/let/letrec body expressions. The corrected
checker compares every body in lexical scope and rejects malformed binders.
Five test groups pass, and independently executing the archived Wasm and original
Chez oracle still produces equivalent complete ten-example results. The original
archive and observations are preserved; this review adds no performance samples.

[Parsing validation](parsing-validation.json) includes complete small lists,
vectors, dotted tails, strings, characters and numbers, wrong-result rejection,
original EOF recovery and zero inner repetitions. The generated lexer/LL(1)
algorithm retains temporary list-tail copying and source action quirks. Native
checks additionally cover copying/sharing identity and lexer errors/limits.

[Artifacts](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-13-rust-peval-parsing/artifacts.tar.xz) freeze both Rust source snapshots, quoted data,
small-input fixtures, original Scheme source/compiled controls, Wasm executables,
input files, native check logs and separate original-source oracles. `files.json`
inside the archive hashes every regular file. Archive SHA-256:
`2379a332d8112975cbf242260d32bd4540cd1e0e49e0b8a760bfbf1e44bb1c66`.
Each validation JSON records exact tool paths/versions/hashes and per-case source,
input, Wasm and Chez hashes.

Extract the archive into `/tmp/rust-peval-parsing`. From
`/tmp/rust-peval-parsing/peval/cases/peval`, run:

```sh
node --no-warnings ../../reference-source/run-wasi.mjs program.wasm < input.txt
scheme --program program.so < input.txt
```

Use the analogous `parsing/cases/parsing` directory for parsing. The archive's
relative input links expose the original and small files to WASI. Source rebuilds
use the snapshot's Cargo manifest, pinned lockfile, release profile and recorded
Rust toolchain. Original controls can be rebuilt from `program.scm` at Chez
optimization level 2.

[Retained-work metadata](retained-work.json) hashes the archived disassemblies.
Peval's optimized `main` contains a loop calling alpha conversion and
specialization at WAT lines 18817/18831, advancing 24 bytes through all 240 bytes
of ten result slots. Each result is stored before the full result list crosses
the optimizer boundary. Complete result audits occur after the workload timer.
Allocation/interner/domain differences are described in
[the porting contracts](../../wasm-reference/PORTING.md).

This checkpoint covers these two workloads. The all-57 implementation task
remains active, with 52 sources, 51 default canonical successes, the recorded
default Ackermann stack failure and a separate passing heap-frame variant.
Five implementations and independent simplification reviews remain pending.
