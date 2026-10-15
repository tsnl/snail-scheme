# Complete Parsing passes strict correctness preparation

Parsing passes the original **2,500 parses**, complete **28,300-byte input**
and full **`(should return this list)`** predicate on raw linked Wasm,
Binaryen-optimized linked Wasm, actual native64, original Chez and exactly
adapted Chez. The unchanged Rust reference passes native, raw Wasm and optimized
Wasm controls. **Clean timing remains pending.** This preparation does not add
to historical measured coverage.

The compiler and libraries are based on
`45214e314d6f3f4424de47d04368f01ccd98a3af`. The benchmark corpus remains pinned
to `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`. Preparation uses Chibi 0.12,
Node 24.19.0, Binaryen 132, Chez 10.4.1, Rust 1.95 and LLVM 22.1.8. The source
adapter, generated programs, tool paths and hashes are retained with the
preparation. No compiler, frontend, collector or reusable library changed.

## Source behavior and representation

The full 936-line source retains all generated scanner states 0 through 41 and
the recursive LL(1) grammar. The adapter supplies existing Symbol and Datum
operations and eight typed `Ref` bindings for the mutable lexical fields.
The original list-based character loader, recursive parser, prefix copying,
and simultaneous `do` updates remain. There is no replacement parser, generic
fallback or benchmark-specific compiler optimization.

The actual timed lambda invokes `parsing-benchmark` once. That procedure loads
the complete file, accumulating characters in reverse order before reversing
the list and making the string, then parses the string 2,500 times. The source
comment describing loading before timing does not match the executable
harness. The strict worker therefore loads inside the worker, including when
the parse count is zero. The two opacity calls occur once at worker entry.
The configuration port closes before worker entry and the data port closes
before parsing begins.

Token kinds remain interned symbols, loader temporaries remain homogeneous
character lists, diagnostic names remain homogeneous symbol lists, and parsed
values use the existing closed Datum representation. The optional argument
list contains Datum values; selected count and path arguments are projected
once, retaining defaults and ignored extra Datum arguments. There is no
additional scanner-state record alongside the eight mutable bindings.

Several upstream behaviors are deliberately preserved:

- `#\~` is the scanner EOF sentinel, including when it occurs in file data.
- A parsed interned symbol `eof` stops the outer parser and returns its prior
  datum. Some incomplete syntax at EOF recovers by returning `eof`.
- Character construction returns the first token character, `#`, rather than
  decoding the character token. Strings lose their delimiters without escape
  decoding.
- An unterminated identifier or comment can repeatedly consume the EOF
  sentinel until reaching the original 1,024-character token limit.
- `pseudoAppend` copies the whole prefix spine while sharing its elements and
  the actual supplied terminus.

Every kernel edit is occurrence-count checked. Reversal checks and removes the
introduced declarations, reverses the recorded substitutions, and recovers the
exact original kernel. Harness edits and the complete adapted Chez program
also reverse exactly. Separate observation edits have their own reversible
ledgers. Exact reversal accounts for all source changes; behavior is supported
by the controls and observations below.

The supported count domain is nonnegative I64. Negative counts are excluded:
the upstream increasing counter does not reach a negative target, while the
strict counter is bounded. The existing Datum numeric service supports
I64/F64/complex values and rejects rational or oversized exact numbers. Those
unsupported values are absent from the canonical input. This is a bounded
workload port, not unrestricted numerical equivalence with Chez. The original
scanner's accepted numeric syntax remains an additional boundary.

Fatal diagnostic fragments emitted by the program are compared exactly.
Uncaught exception banners and payload presentation differ between hosts.
The unreachable reset/retry text after the scanner's fatal error remains; one
unreachable Unit expression supplies the strict branch result type.

## Correctness and separate observations

Fourteen ordinary fixtures run on all five Scheme paths and all three Rust
paths. They include the complete canonical input; the same full data at counts
one and two; an incorrect final element; zero parses and its wrong expected
result; empty input; both EOF mechanisms; EOF recovery in a list and quote;
quasiquote/unquote/splicing; mixed lists, vectors, strings, characters and
numbers; and an accepted 1,024-character identifier. Complete result equality
is required, including every list element and the proper ending.

Five fatal cases run on all five Scheme paths: malformed dotted-list syntax,
incomplete character syntax, unterminated string, unterminated comment and an
over-limit identifier. Program-emitted diagnostics and failure categories
match. Wasm host observations require complete file reads through physical EOF,
the expected closes and no terminal cleanup of a leaked file. Native checks
the setup and worker resource-release counts. The canonical final Wasm module
used for native lowering also passes independently in V8.

This gives **158 correctness and diagnostic executions**: 70 ordinary Scheme
cases, 25 Scheme rejections, 20 Scheme observation cases, one native-final V8
case and 42 Rust cases. The unchanged Rust binary also passes four existing
unit tests covering data, source quirks, lexical failures and prefix/suffix
identity.

The four observation cases run on original Chez, adapted Chez, raw linked
Wasm in V8, optimized linked Wasm in V8 and actual native. The byte streams
must match exactly across all five systems:

| Observation | Bytes per system | SHA-256 |
| --- | ---: | --- |
| Complete input, accepted tokens and top-level datums | 341,345 | `117b18c5467795f4dc8dbd03c9105fd04e0330752b9183a7a70c74eb8ccb80cf` |
| Small mixed input, ordered values | 1,579 | `892596f8a2fce7e576bc35750b1cded0c012eb9f0d257c3c62564c9e915f9b96` |
| Sharing, mutation and sequential reset | 386 | `55119e6886ea8e241f49f509e208100c97427383eaff5c0f3c368ef4352e4250` |
| Complete 2,500-parse work counts | 724 | `dc09b9243ecc7d2ba5af3ef01d06c01a972323b7c569aef7d38c0b0417cd13bf` |

Token observations include the accepted token kind and the source token-value
field, including its stale text on punctuation. Datum observations serialize
each semantic field and preserve symbol/string and numeric distinctions.
The complete-input stream observes every top-level datum encountered during
one complete parse. Full-count counters cover **79 named source procedures**;
`scannererror` and the anonymous loader callback have no individual entry
counter. The loader itself and all 42 generated scanner states are counted.

| Source procedure, original full count | Entries |
| --- | ---: |
| `parsing-benchmark` | 1 |
| `read-file-as-string` | 1 |
| `parse-string` | 2,500 |
| `accept` | 10,755,000 |
| `consumechar` | 70,750,000 |
| `parse-datum` | 7,867,500 |
| `makeSym` | 4,775,000 |
| `pseudoAppend` | 7,802,500 |
| `parse-error` | 2,500 |

The final `parse-error` entries are the source's ordinary EOF recovery, not
fatal failures. The retained counter file includes all 79 entries. These are
source-operation counts in separate instrumented programs; they are not
physical allocation totals or observations of the clean optimizer's behavior.

Identity probes require fresh prefix pairs, shared repeated elements, the
exact shared suffix, and identity for an empty prefix. Mutating the copy's
first field must leave the original prefix intact; mutating a shared element
or suffix must be visible through the copy. A parse-A/parse-B/parse-A sequence
holds earlier results while checking complete values, fresh result spines and
interned symbol identity. No artificial scanner-interleaving API is introduced.

## Controls, continuation and retained evidence

Adapted Chez executes the identical typed kernel, existing Datum/reader bodies
and explicit scalar compatibility services. Its representation uses Chez
vectors and native numbers; strict code uses WasmGC data, specialized arrays
and the Rust scalar ABI. The Rust reference retains its independent state
machine, `LinkedList` character loading, interned `Rc` symbols, immutable `Rc`
pairs and destruction schedule. These controls do not establish equal
allocations or isolate collector, layout or generated-code costs.

Preparation completed by continuation. The canonical binaries and all ordinary
and fatal cases succeeded before the first observer-only Chez compile failed
on a missing `cflonum?` import. A second attempt exposed a conflicting
`string-copy!` import. Both failed directories and the initial failed
supervisor manifest remain intact. Corrected observer imports passed all four
observations. The exact-native-final V8 and independent Rust controls also
completed. Subsequent driver simplification preserves all generated compiled
Scheme inputs byte-for-byte; successful canonical builds were reused.

The [focused simplify review](simplify-review.md) records two fresh independent
behavioral explanations and the decisions they informed. The evidence retains
the initial adapter snapshot, final source identity, exact reverse ledgers,
original/adapted source, raw/optimized/native artifacts, native LLVM, scalar
providers, input bytes, ordered traces and terminal process records. The
continuation manifest identifies reused artifacts separately from new checks.
No preparation elapsed field is a clean performance sample.

To perform a new complete preparation, use a fresh output directory:

```sh
python3 benchmarks/strict-suite/measure.py prepare \
  --output build/parsing-prepared --benchmarks parsing \
  --compiler-basis 45214e3
```

The retained working evidence is under
`/tmp/snail-strict-parsing-20261014/build/parsing-preparation-1`.
Compressed packaging and clean comparative timing are pending coordinated
CPU windows. Absolute paths in command records describe the original
executions; replay elsewhere requires verified path mapping and pinned tools.
