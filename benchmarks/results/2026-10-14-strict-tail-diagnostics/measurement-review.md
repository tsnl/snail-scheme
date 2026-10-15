# Bounded explanation and verification

Applied the pinned [simplify skill](../../../.agents/skills/simplify/SKILL.md)
to the new diagnostic driver. The fresh
`/root/rust_mazefun_handoff/explain_tail_diagnostics` agent used Sol 6.1 at max
reasoning with no history, tools, files, code, diff or prior proposals. Its
neutral brief requested full-workload profiling and separate operational
counts, preserved behavior/lifetimes, and complete output/lifecycle validation.
One informed critique followed the independent explanation; the parent owned
all inspection, implementation and checks. The child is completed.

Accepted points: await profiler start acknowledgment before the workload clock;
stop immediately after that clock; retain every boundary marker and failed
attempt; use actual sampled intervals and keep inclusive totals separate.
Counters capture original operands once, append scalar locals/globals, count
requests before services and completed constructors/copies after completion,
reset after initialization, snapshot before guest result inspection, and prove
exact textual erasure. Complete files and repetition lifecycles remain checked
outside the workload timer. Buffered WASI work and direct linked scalar calls
remain distinct. Physical allocations cannot be inferred from source or site
counts. Intermediate output contents are not inferred from final-byte and
lifecycle evidence.

Rejected alternatives: profiling a rebuilt/instrumented guest as if unchanged;
reoptimizing counter insertions; evaluating array lengths twice; adding reference
locals; summing inclusive ancestors; charging unresolved frames to GC; and
claiming lookup-only or allocator-only costs from combined Rust frames.

The driver keeps its cohesive exact-host transformations, WAT insertion ledger,
raw process attempt, full contract validator and summary operation together.
Helpers exceed the ten-line target where one complete transformation, atomic
run/validation transaction, concrete site inventory, weighted ancestor walk or
prediction comparison would be obscured by splitting. Longer `profile`,
`counters`, `execute`, `validate_files_and_lifecycle`, `make_profile_host`,
`build_counters`, `frame_weights`, `verify_predictions` and `summarize` operations
were reviewed as those bounded exceptions; no forwarding framework was added.
The parent independently inspected `plan.md` and `diagnose.py` and approved
their profile/counter boundaries and full byte/lifecycle checks.

Verification: unchanged-guest full-count profile passed; counter assembly and
full-count execution passed; all pre/post original identities matched; 13
independent count predictions matched; all profile intervals were nonnegative
and exclusive weights partitioned the observed interval total. No broad suite,
new clean campaign, source optimization or representation change was needed
for this first pass.
