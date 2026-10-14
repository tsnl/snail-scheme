# Combined reader preparation and comparison plan

This historical plan was declared before combined preparation finished on
2026-10-14. Its prospective wording describes that stage. Correctness, freeze
and the 44-process campaign are now complete; [README.md](README.md) and
[audit.json](audit.json) record actual status. The independent A/B source commits,
successful campaign and this campaign's frozen artifacts/plan remain unchanged.

The candidate starts at `c0ba036499de55622538fc4c077fb8951b510502` and combines
only A's direct scalar delimiter checks and B's single owned atom staging,
including the shared existing result placement and necessary Chez scalar mock.
The combined source commit is `20b4d2100c3640c50fb535a70956d0b4128a9554`.
The compiler remains identical to the baseline; Scheme still owns parsing,
buffers, datums and collection, while Rust supplies scalar services. The extra
shared read-value/read-error constructors are part of the candidate unless
actual retained-code evidence establishes otherwise; no V8 elimination claim
follows from Wasm construction sites.

Reuse the existing current baseline artifacts from the independent campaign;
verify their frozen identities. Build and validate the combined candidate with
the same compiler/tool basis and existing reader runners. Require the complete
95-case reader corpus, direct unchanged delimiter inputs against baseline,
module-final public datum tests, Rust ownership transitions, Scheme formatting
and tests, and counts 1, 2 and full 25/2,500 on raw/optimized linked Wasm, actual
native and the original/adapted Chez references. Preserve complete canonical
streams, per-worker file/EOF/close cycles, final predicates, malformed/error
priority, trapped cleanup and existing Browse identity/list/decimal semantics.

After correctness, freeze a production V8 comparison using the independent
report's unchanged reviewed runner and complete accepted supervisor closure.
Use two systems, `strict-v8-baseline` and `strict-v8-combined`, and two workloads,
Sum1 then Read1. Each system/workload has one predetermined discard and ten
retained executions. Alternate the two within-round positions so each system
appears five times in each retained position: **44 fresh processes**, serially
on CPU 5, at full original counts. Keep normal V8 tiering/heap policy, original
setup-before-clock host, complete results and both workload/process clocks.
No instrumentation, adaptive exclusions or replacement samples are planned.

All preparation handles must be polled terminal, and root must review the frozen
plan and explicitly release a separate quiet window before timing begins. During
that window other builds, guests, profiles, compression and publication remain
held. Retain any failed campaign. Report observed medians/ranges without adding
the independent percentages or implying confidence intervals. The OS file cache
and CPU frequency remain uncontrolled and disclosed.
