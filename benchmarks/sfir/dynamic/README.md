# Dynamic type inference

`main.sfir` contains all 229 kernel forms of the upstream dynamic type inferencer.
Each of the 500 canonical iterations reads the complete 83,872-byte
`inputs/dynamic.data`, parses its source forms, constructs and normalizes type
constraints, and runs the original counter-producing traversal. The worker
compares the complete result `((218 . 455) (6 . 1892) (2204 . 446))` with the
unchanged expected datum. `source-coverage.json` records every retained form.

The parser and inference algorithm are ordinary SFIR benchmark code. The product
compiler reads the static file directly; no Scheme elaborator or host evaluator
runs during preparation or measurement. One-off authoring tools resolved the
original bindings before the checked-in source was written.

The source's dynamic objects use a closed local `Value` type. Mutable pair cells,
fixed-element vectors, typed scalar ports, and concrete fixed/rest procedure
signatures expose the representation and its costs. Exact arithmetic uses the
shared Integer/Rational/Number libraries. Source initialization order and mutable
aliases remain explicit. The adapted Chez control retains this representation
and the complete algorithm while using Chez's numeric tower and scalar services;
it is reported separately from the original Chez source.

`lifecycle.json` records the source's intentional unclosed-input behavior. Setup
closes its configuration file. The worker opens 500 input ports and reads every
file through EOF, leaving all 500 open. Host cleanup then closes those handles.
Neither the port nor the verification harness inserts closes into the worker.
There is no automatic GC resource cleanup during the observed worker runs.

The final static source passed all 500 iterations on optimized V8, native64,
original Chez and adapted Chez. Native was built from the retained raw Wasm and
its optimized module was checked byte-for-byte against V8's program module. V8
resource tracing confirmed all input bytes and EOF reads; native release counts
confirmed setup, worker and cleanup ownership. These were concurrent correctness
runs, without a clean timing claim. Frozen corpus registration and Rust controls
are separate runner validation.

The focused simplify review used an independent explanation without repository
access and a follow-up critique of the shared Value/graph layer. Conversion keeps
a local identity memo and records allocated shells before traversing children.
Equality records pairs of identities along each recursive path; list recognition
checks only cdr links. The review retained these direct algorithms, with their
linear memo tables, rather than introducing a generic graph framework. Original
algorithm functions and coherent exhaustive cases can exceed the ten-line target.
