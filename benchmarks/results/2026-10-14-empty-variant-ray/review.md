# Focused implementation and measurement review

The independent implementation explanation narrowed an initial pooling idea to
zero-field immutable constructors. The existing concrete layout registry supplies
the identity. There is no second registry, runtime lookup or aggregate pooling.
Each private global is emitted after bodies and first-class workers have discovered
their layouts. The source binding's initialization state remains separate.

The informed critique checked nominal generic identity, Wasm structural type
canonicalization, first-class constructor workers, source alias readiness,
effectful operator evaluation and root lifetime. Constructors with fields retain
ordinary evaluation and allocation. Mutable cells and containers retain their
identity. These facts are exercised by focused source contracts, actual native
execution with forced collection, and complete Ray output checks.

The sharing contract does not promise fresh immutable reference identity or prompt
collection. The present foreign boundary and selected worker exports are scalar
only. Generated `main` itself enforces one-shot execution, including reentrancy;
this is not merely a host convention. Private singleton globals never mark a
source binding initialized or execute a source-level constructor function.

An independent Sol 6.1 reviewer, with no conversation history or source access,
first explained the four-way measurement protocol. It then read `measure.py`
and the unchanged Ray host for informed critique. It found no material issue and
requested no implementation change or additional experiment.

The review explicitly corrected a timer-scope misunderstanding: Ray's original
guest predicate checks the sentinel result `1`. The complete 29,517-byte output
comparison happens after every process exits, outside both clocks. Raw process
outcomes are saved before this validation. Any failure stops the campaign and
prevents publication of a successful-subset summary.

The primary comparisons are candidate versus baseline within each executor.
Global construction and retention can move work outside the workload clock;
launch-through-exit process time is reported independently. V8's small result
conversion/assertion is inside its workload interval. Cross-executor ratios
include both runtime paths and are not isolated collector or ABI comparisons.

Eight rotated retained cycles balance each variant's position twice. CPU affinity
does not reserve CPU 5, and paused agent work does not exclude desktop or other
system activity. The record preserves environment removal rules, not the entire
inherited environment. Close results need their retained ranges, not significance
claims. Separate allocation statistics describe instrumented executions only;
their durations are excluded from the clean comparison.
