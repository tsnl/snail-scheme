# Full native String preparation

The original `string` workload passes in raw Wasm, optimized Wasm, untouched
original Chez and the adapted-source Chez control: all 100 repetitions, ten
reset-and-grow trials per repetition, threshold 500,000 and final length 524,278.
This archive contains correctness and retained-work evidence, with no clean
performance observations. Compiler basis `2def9941eb85f211e116e6955799fdc9ef561da8`
and source port `3238d8234b9ace81a2c7cf30b4486d5bb92f524d` are frozen;
[compiler-identity.json](compiler-identity.json) records all 52 compiler/build
file hashes and exact source identity.

The compiler adds concrete Unicode String, represented by one WasmGC I32 array
with a private mutability word followed by Unicode scalar values. Literals are
readonly; constructors and copies are fresh and mutable, including empty copies.
Checked native primitives enforce destination permissions through aliases,
unsigned length/index limits and atomic overlapping `array.copy` semantics.
Ordinary Scheme functions implement append, substring, copying and content
comparison. Character conversion checks Unicode scalar range and excludes
surrogates. The frontend and scalar-only extern boundary remain unchanged.

The source adapter adds one explicit Ref for the mutable global and replaces
its reads/writes through six counted edit groups. Every original append,
substring, literal, loop, reset and unused trial-counter step remains. The first
append has five segments; two substrings copy the right and left halves of its
odd-length result, sharing the midpoint; the final append copies those halves.
The independent complete-character oracle is `56 + old + 789123 + old + 45`.
It is used only by probes, never as a replacement for the timed algorithm.

The adapted Chez control uses the identical kernel and portable vector Ref
helpers. Three counted surrounding-harness changes use the same numeric result
initializer and reconstruct the original initial false value from the loop
counter for equality and failure printing. Reversing all edits must recover the
complete original source byte for byte. The original Chez source is untouched.
Strict checks the original Boolean-or-I64 `equal?` predicate inside `bench` and
returns an acceptance flag. Nonpositive repetition counts accept only `#f`;
integer zero and `#t` remain distinct. Native failure text reports the rejected
flag, while both Chez controls print the original actual value.

The port accepts decimal I64 counts/thresholds and Boolean-or-I64 expectations.
Large JSON integers become decimal strings before JavaScript's BigInt conversion;
large thresholds remain subject to finite engine storage limits. The actual
threshold crosses the value-returning identity import once per positive outer
iteration. Validation checks that count, including zero calls for nonpositive
repetitions. Threshold opacity alone does not make string contents observable:
the canonical predicate checks only length, and legal elimination of unobserved
payload work would not be a semantic error.

[Correctness evidence](correctness-summary.json) contains twelve canonical runs
at counts 1, 2 and 100; thirteen complete-character/store cases across four
systems; five independent-alias cases across four systems; and fifteen harness
boundary cases across four systems, totaling 144 checks. The complete canonical
524,278-character value is compared, not merely hashed or reduced to its length.
Small traces compare both growth stores and all ten resets. Seeds cover empty,
NUL, non-ASCII, supplementary, combining and maximum Unicode scalars. Aliases
retain the old string, first append, both substrings and final append across
allocations; each is mutated separately while the other four must stay unchanged.
Zero/negative counts, false versus integer zero, signed I64 boundaries and wrong
expected lengths are checked. These extra observations exist only in separate
probe modules.

The [retention audit](retention-audit.json) inspects the canonical optimized
module, whose only exports are `bench` and `main`. Its repetition loop passes the
identity import's returned threshold into the ten-trial routine. Both growth
stores, all four fresh character buffers and the substring/append copy loops
remain in optimized WAT. Separate count-1, count-2 and count-100 diagnostics
subtract setup. At count 100 they complete 60,000 String array constructors,
135,000 copy spans covering 3,145,167,000 Unicode scalars, and 31,000 global Ref
stores (1,000 resets plus 30,000 growth replacements). Counters increment only
after successful operations; erasing observers recovers all nine original
function forms exactly. These are completed instruction requests, not physical
allocator events or performance samples.

Default-tier V8 code from the unchanged canonical binary retains array bump
allocation and slow paths, zero initialization, scalar copy loops and external
bulk `array_copy_wrapper` calls. Both growth stores remain in its TurboFan
trial routine. The ordinary variadic append implementation also retains
homogeneous List String argument spines; the character-array count excludes
that support representation. Original/adapted Chez strings and an eventual
Rust ASCII/UTF-8 control have different physical layouts. This report neither
normalizes those costs nor claims equal allocation or total physical bytes.

All 283 strict compiler contracts pass, including twelve new native String/Char
contracts in raw and optimized actual Node execution. All twenty extern
contracts, `make test` and `make check` pass. The port adds no further compiler
changes, and all 26 previous specifications and generated strict sources remain
byte-identical. The first two preparation attempts passed canonical and payload
checks but rejected unprovided `map`/`list` conveniences in the isolated alias
probe. Those failures are retained; the probe now uses direct recursion/cons.

The fresh no-history/no-file Sol 6.1 maximum-reasoning explanations and critical
debates are recorded in [simplify-review.md](simplify-review.md) and
[native-string-review.md](native-string-review.md). Parent-owned source/tests
and the parent agent's separate String implementation review complete the stated
review boundary. This is not an independent observer source-code audit.

Restore and hash-verify the complete archive without running workloads:

```sh
python3 benchmarks/strict-suite/replay.py /tmp/strict-string-replay \
  --report benchmarks/results/2026-10-14-strict-string
```

All 2,234 archived files were restored and hash-verified. Restored raw and
optimized Wasm and both Chez controls passed the count-2 canonical input;
[replay-check.json](replay-check.json) records these diagnostic-only executions.
