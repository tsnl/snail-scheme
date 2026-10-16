# Complete Earley preparation

The complete 657-line Feeley Earley workload is ported and correctness-validated.
Canonical input remains count **1**, length **15**, expected **2674440**. The
benchmark still builds the parse and materializes its complete tree list before
taking its length. `make-parser`, the forward/backward passes, `parse->parsed?`,
`parse->trees` and `parse->nb-trees` are represented. No compiler or runtime source
changed. No clean measurements or coverage increment are reported here.

Implementation commit: `14a84bd1f64ef4faac23b9b3aa54062d9c55c010`.
Frozen compiler basis: `011833645d88aae50c3c47a4eb6fa008136034c0`.
Upstream: `85f6acdc4cc4e2b857f307ba56bd0ba931dcccd1`.
The parent integration has historical coverage 35/57, with 34 paired Chez
comparisons before Earley; the older inventory counts in this branch are not a
new measurement. Source and commands are preserved in `artifacts.tar.xz`; its
member hashes are listed in `manifest.json`.

## Source equivalence and scope

[earley_port.py](../../strict-suite/earley_port.py) applies 93 counted reversible
edit rules, matching 190 occurrences. Reversing them restores the complete
original kernel byte for byte. Both source forms retain the original author
header, comments and loops. The complete original Chez program uses the untouched
kernel and harness. The adapted Chez program uses exactly the strict program's
adapted kernel and helpers, with a small Chez representation prelude. Its original
benchmark harness is unchanged. `source-edits.json`, `source-proof.json`, both
kernels, both complete programs and the exact input are archived.

| Source role | Concrete representation and limits |
| --- | --- |
| Grammar definitions, lexer tokens and rule names | Distinct products, with ordered immutable lists for rules and token classes. |
| Grammar atom equality | Closed atom vocabulary `s a x y e v + = unknown`; `s/a` are canonical and the rest exercise documented grammar and rejected inputs. This is not general Scheme symbol support. Lexer user-info is restricted to the same vocabulary. |
| Parser description and parse result | Products retain the lexer and all three stored query functions, as well as their vectors and state. |
| Heterogeneous state vectors | A `State` has one mutable `Ref I64` work-list head and a vector of optional configurations. The source initialization loop remains; every head is `-1` before use. |
| Configuration vectors | A product contains `Vector (Optional I64)`. Original offsets remain: work link at 0, old tail/head at 1/2, new tail/head at 3/4 and origin links at `5+i`. False is distinct from `-3`, `-1` and zero. |
| Heterogeneous tree elements | Closed recursive name/token/child variants with ordered list spines. Copied prefixes and shared suffixes/children follow the source. |
| Exact numbers and expected result | Kernel integers use I64. The actual Chez reader classifies the expected datum as false, exact I64, or another value; the guest retains the complete original equality decision for this result domain. Exact `10/2` matches 5; inexact `5.0` does not. This does not implement arbitrary precision integers. |

The explicit `earley-append` helper reverses each prefix and then rebuilds it
onto the original suffix. This bounds stack use for the final list of millions
of trees and preserves order, element identity and suffix sharing. It allocates
one extra temporary prefix spine compared with a direct recursive append.
Original and adapted Chez controls expose this cost. It is an adapter difference,
not a change to the parser's derivation loops or a count-only replacement.
The strict harness uses one scalar host opacity barrier per invocation and keeps
the input vector/list construction inside the guest workload. Both Chez forms
retain the original `hide` dispatch. These harness costs and the additional
product/option/ref wrappers are not claimed to have identical allocation costs.

## Correctness evidence

Final preparation is `build/earley-prepare-04`, frozen from the implementation
commit. Its 14 fixtures pass the expected acceptance/rejection decision on all
five targets: raw linked Wasm, optimized linked Wasm, mechanical native,
original Chez and adapted Chez. These are 70 harness executions. Fixtures cover
the full canonical input, supplementary count 2, small trees, exact ratio,
incorrect integer, inexact number, false, symbol, list, vector, empty input,
zero count with false/numeric expectations and negative count. Expected failures
are checked as predicate failures, not merely nonzero process exits.

Separate probes emit complete scalar encodings on all five targets:

- Command 0: **1930 observations**, 15 parser cases, complete ordered trees for
  canonical lengths 0–5, direct goal tokens, unknown tokens and queries, the
  documented nullable/ambiguous grammar, duplicate productions and an empty
  production. All five encodings match exactly. An independent recursive tree
  oracle compares every canonical small tree and its multiplicity; original Chez
  establishes the source enumeration order. The oracle does not run the workload.
- Command 1: **121 observations** of configuration slots, state/configuration
  identity, mutation through an existing alias, merge/adjoin/union/filter
  operations and all sentinel distinctions. An independent slot model matches.
- Command 2: **54 observations** of a lexer closure with a mutable captured call
  count, duplicate/unknown classes, later changed classification, user-info
  preservation and span queries through the stored parse functions.

The additional final-common Wasm artifact passes all 14 fixtures on Node. The
timer-only native relink passes fresh canonical, small and wrong-result checks.
Both complete Chez clocks and both V8 timing modes are checked in fresh processes.
Validation clocks and process durations are diagnostic records, not clean samples.

## Retained work and optimization differences

[retention-audit.json](retention-audit.json) is generated by
[inspect-retention.py](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-strict-earley-preparation/inspect-retention.py). A separately compiled function
location map connects original raw function indices to the strict source. Its
source bytes match the final preparation. Both optimized modules have 58 defined
functions and the same static direct-call/`ref.func` reachability names. Their
exported `bench` reaches the recursive derivation, Cartesian combination and
final length traversal; it does not call the alternative counting query instead.
The audit treats indirect calls separately and does not infer runtime allocation
counts from static sites.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Once-optimized production Wasm | 24240 | `923ee2e96a8d4ee9c252af935d138b1faf07625e14428568ed17b1d06ea01956` |
| Final common Wasm read by native lowering | 28961 | `2f2d788d5851dd964550b26054d5cf034dc598015a163b79378aa7a214029ea5` |

The bytes differ because `build-native --wasm` invokes the same mandatory
Binaryen 132 pipeline again: `-g`, the explicit Wasm feature flags, `-O3`,
`--closed-world`, `--always-inline-max-function-size=40`, `--converge`.
Further recursive helper inlining/unrolling grows hot code. For example, outer
tree-list append in function137 and inner tree-part append in function146 each
grow from 28 to 48 static spine-allocation sites. Reachable function names and
tree type shapes remain the same. The five-system plan measures both V8 build
artifacts rather than changing the production policy during this campaign.

The raw types retain full rule-name, token and child payloads. Both optimized
artifacts retain the outer tree-list and inner tree-part list spines, but remove
the unused rule-name type and the name/token/child fields and tags. Empty variant
allocations remain at some sites. Complete source materialization, complete probe
outputs and reachable canonical tree-spine generation are supported; identical
payload/edge allocation across optimized and original implementations is not.
The canonical caller does not use the acceptance/count query closures, so their
unused fields and code can also disappear; the separate probes exercise all
three source query APIs and their function-valued boundaries.
This is not an isolated collector comparison.

## Native resource boundary and retained failures

The default **256 MiB** native arena exhausts on the full canonical workload.
That failure is retained in attempt03. The same executable succeeds with the
explicit `SNAIL_GC_HEAP_BYTES=1073741824` override. The final preparation and
proposed timing plan retain that **1 GiB reservation**; it is not an implicit
runtime policy change.

One separate diagnostic execution of the same attempt03 binary recorded maximum
RSS **984944 KiB**, arena usage **974880768 bytes**, and last/peak live bytes at
collection observations **239603216**. It performed 50 collections and recorded
170726272 allocations / 3630484968 cumulative allocated bytes. Reservation,
resident memory, arena usage and observed live bytes are different quantities.
The observed live peak does not prove that the maximum live heap stayed below
256 MiB between collections. GC statistics and `/usr/bin/time`-style resource
measurement are excluded from the clean plan.

The archive retains every preparation attempt and its raw logs:

1. Attempt01: an adapter type signature had an unmatched parenthesis; compilation
   failed. The adapter declaration was corrected.
2. Attempt02: full raw Wasm overflowed the host stack in a direct recursive append
   helper. The explicit reverse/rebuild helper above corrected it.
3. Attempt03: full raw/optimized Wasm passed; native default arena exhaustion was
   preserved, followed by separately named same-binary 1 GiB diagnostics.
4. The first complete-tree observer used `map` for output side effects. Chez's
   unspecified map evaluation order changed the observation order. An explicit
   traversal fixed the observer only; the failed comparison and observer source
   remain. `earley-probe-02` and final attempt04 pass.
5. The first function-location diagnostic lacked the compiler trace context;
   its raw failure and corrected diagnostic are preserved. The first retention
   reader also lacked inline-export support; its diagnostic is recorded.

The generic preparation command returns process status zero even when a case's
metadata says failed. This report uses the per-case records, not that outer
exit status, to distinguish these attempts. No failed benchmark run was silently
retried or relabeled.

All subprocesses have explicit deadlines. Cleanup kills the owned process
group, reaps its leader and verifies that no live group members remain, even
when the leader exits or closes its pipes first. Adopted zombies may remain;
they are stopped, not proof that every descendant was reaped. Separate
closed-pipe and inherited-pipe descendant checks exercise this policy for both
the port supervisor and the timing runner.

## Frozen clean plan

[timing-plan.md](timing-plan.md) explains the five systems and clock boundaries;
[timing-plan.json](timing-plan.json) freezes exact identities and the 30-process
schedule. [measure-five.py](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-14-strict-earley-preparation/measure-five.py) verifies without running by default.
An explicit parent quiet-window release is still required before `--run`.
No Rust reference is presented as an authority or timing system.

The focused [simplify review](simplify-review.md) records the independent
behavioral explanation, informed critique and remaining cohesive size exceptions.
Compiler/frontend structure, strict specialization and typeclass design are
unchanged. Correctness checks and archive verification are recorded alongside
this report.

Parent stack integration on `3dcce40` preserves the generated strict program,
adapted kernel and adapted Chez program byte for byte for both Earley and
bytevector conversion. All 84 Earley and 83 bytevector compiler-file identities
remain unchanged. [stack-integration.json](stack-integration.json) records this
source correspondence; it is not a new compilation or measurement run.
