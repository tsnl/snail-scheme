# Focused Parsing adapter review

The pinned simplify skill was applied to the new Parsing adapter and its small
preparation/host integration. Compiler passes, the landed frontend and shared
library implementations stayed outside the refactoring scope. Both explainers
were fresh Astra/max agents with no inherited conversation and no repository
or implementation access. The parent inspected code, challenged the models,
made edits and checked the evidence.

## Representation and source behavior

The first explanation separated the generated scanner/grammar from the typed
boundaries it needs. Debate covered actual harness timing, the two EOF
mechanisms, simultaneous updates, unreachable scanner-error continuation,
optional arguments and prefix/suffix identity.

The resulting implementation keeps the source's eight mutable lexical fields
as eight Ref bindings. It does not add a redundant state record. Concrete
Symbol kinds avoid another token-name mapping representation. Parser results
use the existing Datum sum; loader and diagnostic lists keep homogeneous
types. The original prefix-copy routine remains recursive and preserves
element and suffix identity. Original defaults and ignored extra Datum
arguments remain; negative counts are explicitly outside the supported domain.

A no-history semantic model did not justify replacing the generated grammar,
modernizing source quirks or treating the comment about untimed loading as the
contract. The actual executable harness determines the timing boundary.

## Preparation and evidence

The second explanation described an explicit sequence: verify source inputs,
generate and reverse adaptations, build canonical artifacts, validate complete
fixtures, run separate observations, and retain exact identities. The debate
distinguished byte reversal from semantic equivalence and named-operation
counters from every procedure invocation. It also clarified that the exact
native-final V8 execution is a separate canonical check, beyond the five
instrumented systems.

The driver now exposes complete operations for quoted-literal discovery,
symbol declarations, reversible harness construction, fixture creation,
compiled-result validation, rejection framing, observer source generation,
trace validation, Rust construction, and fixture orchestration. Failed ordered
comparisons retain their full trace before comparison. Observation edits now
have counted reverse ledgers as well as the workload edits. Source and observer
generation remain byte-identical to the successfully compiled artifacts.

The existing literal replacement ledger was retained. Forward/reverse
occurrence checks, explicit prefix removal and exact restored-source equality
already establish the intended integrity guarantee. Replacing it with an
offset-edit framework would add a second representation without strengthening
that guarantee. A general resumable workflow framework was also rejected:
one concrete continuation record can identify prior failures, unchanged build
inputs, reused artifacts and new successful observations.

Functions target ten lines of logic. A few cohesive operations remain longer:
the quoted-literal classification, ordered adaptation pipeline, source-file
batch, three host rejection-frame cases, ordered instrumentation edits and
five-system trace comparison. Keeping their complete case distinctions and
proof checks together makes their contracts visible. Generated Scheme grammar,
exhaustive signatures, fixture tables and identity assertions also remain
together rather than being split into arbitrary fragments.

The pass stopped after the stages and invariants were explicit and byte
identity checks showed no benchmark change. Further emitted-code edits would
require new evidence without a supported simplification benefit. During the
coordinated timing pause, verification is restricted to source identities and
retained records; no workload is rerun or recompiled.
