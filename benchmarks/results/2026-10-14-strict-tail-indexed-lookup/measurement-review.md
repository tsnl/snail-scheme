# Focused independent explanation and owner review

The pinned [simplify skill](../../../.agents/skills/simplify/SKILL.md) was applied
to the new provider-experiment preparation/probe code and narrow adaptation of
the established Tail timing driver. The fresh
`/root/rust_mazefun_handoff/explain_tail_provider_experiment` used Sol 6.1 at max
reasoning with no inherited history, tools, files, implementation or diff.
Its neutral brief described resource identity, scalar semantics, ownership,
cleanup, matched builds and full workload evidence without selecting a container.
One informed critique followed; the owner supplied only relevant actual facts,
inspected/edited code, and ran checks. The explainer completed and released its
slot before timing preparation closed.

Accepted invariants: issue IDs before filesystem open, never reuse them, keep a
newly opened Port locally owned until publication, end every RefCell borrow
before cleanup, remove before explicit flush/drop, take the whole container
before final release, preserve ascending issued-ID order through holes, continue
after returned flush failures, and preserve primary diagnostic precedence.
Successful publication near `I32_MAX` is impractical for the candidate; tests
cover reservation/exhaustion arithmetic without allocating billions of slots.
Vec holes and allocation-failure/host-trap limits are disclosed rather than
promoted to production guarantees. The scalar ABI keeps negative I32 bit
patterns on its existing `u32` unknown/closed error path.

The critique requested a sparse private-helper history, actual Wasm cleanup
through a hole with returned WASI EIO, and primary-error precedence with that
additional flush failure. All are implemented for both configurations. A
private Result-returning failed-open check does not imply that a fatal public
instance can resume. Actual fatal probes use fresh instances and check disposal
before the nonreturning diagnostic; final close-all is their permitted cleanup.
Unused legacy ABI imports in the diagnostic runtime have explicit throwing
stubs: passing probes establish those imports were never called. Full linked
Tail artifacts retain the normal strict import contract.

Owner clarification: each Tail iteration reads the same unchanged bibliography
and writes the same reversed oracle. The explainer's conditional concern about
even-count alternating reversals does not describe this source. The diagnostic
observer nevertheless compares every byte of all 50 materialized outputs after
output close, alongside complete transfer/lifecycle checks. These extra host
reads/hashes are absent from the clean measurement host.

Parent review accepted `plan.md`, the representation transformation and scalar
probe contracts, then identified that a timeout of an immediate subprocess can
leave descendants. The first attempt remains untouched with a relocation map.
Future commands own new process groups, kill those groups on timeout, and
record remaining executing descendants. Synthetic parent/child timeout checks
passed for preparation and timing paths. Group inspection/cleanup occurs after
the clean process clock; raw outcome/streams precede result/file validation.
The parent independently reviewed and accepted the paired measurement contract.

The common `cfg(test)` sparse-history addition compiles out of both release
providers. Source snapshots differ only in `src/strict_io.rs`; exact reverse
transformation recovers the baseline. Same-path builds plus original toolchain,
pre-link program and Binaryen commands reproduce the historical optimized
baseline byte-for-byte. The candidate is independently linked and optimized.
Whole-module optimization may differ; this is an end-to-end source ablation,
rather than a universal isolated lookup-cost measurement.

Functions retain one visible complete operation. Longer exact transformation
inventories, source/build transactions, raw process ownership/error handling,
full contract validation, concrete scalar cases and campaign freezing exceed
the ten-line target deliberately: splitting them would hide operand/ownership,
clock or failure boundaries. No generic experiment framework or production
cleanup was introduced. Checks were bounded to the relevant six unit tests and
10 actual scalar cases per configuration, two full linked Tail validations,
framing/supervisor checks and frozen-file validation; no broad suite was rerun.
