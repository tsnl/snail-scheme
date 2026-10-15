# Focused simplify review

The review scope was the new wc worker, scalar result bridge, owner adapter,
linked behavioral checks, and benchmark preparation/timing driver. The landed
frontend, compiler, Rust provider, and existing benchmark modules stayed outside
the refactoring scope.

A fresh explainer received the purpose, native read/status and counter types,
observable list result, delimiter/Unicode/error rules, ownership requirements,
and pinned corpus/count. It received no implementation or helper decomposition.
Its explanation identified four necessary state values: lines, words,
characters, and whether a word has started. Every decoded scalar increments
characters; only newline increments lines; only space/newline clear word state;
another scalar increments words only when outside a word. EOF changes nothing.
The explainer corrected an example: `λ😀 \nZ` contains five Unicode scalars.

Informed comparison then checked the implementation against that explanation.
The I32 read helper raises the saved error immediately. The native state loop
submits three I64 scalars only at successful EOF. The owner adapter retains the
input wrapper through all reads and final list allocation; intermediate GC
references stay on the traced Wasm operand stack. Repeated EOF must overwrite a
previous result with zero counts. Process-fatal errors must never expose the
previous result. The linked checks exercise those cases and root balance.

Keeping the scalar sink is justified by the small diagnostic interface. Native
multiple-result support or a broader GC ABI would add compiler work outside this
experiment. Clearing the result globals before each invocation is unnecessary:
normal completion overwrites all three together, and errors cannot return. The
synchronous, non-overlapping restriction remains beside the globals; the frozen
provider contract and experiment documentation state that it makes no Scheme
callbacks.

The local code comparison separated execution-source archiving, per-variant
linked checks, and Chez predicate validation into complete operations. Worker
helpers directly name character reading, delimiter classification, and counting.
The driver keeps larger ordered build/verification batches together; its nested
measurement loop exposes rotating order, fresh-process execution, sample
preservation, rejection of invalid results, and affinity restoration. These
orchestration and test operations exceed the ten-line target where retaining the
whole operation makes its contract visible. The list-extraction test helper also
keeps its ownership transition and `finally` cleanup together.

The pass stopped after the state transitions, ownership, scalar sink, preparation
identities, and timing boundary were visible and verified. No broader cleanup or
speculative interface was justified. Linked Node execution and the exact original
corpus/result predicate passed before clean timing. Archive restoration and
revalidation are recorded separately after packaging.
