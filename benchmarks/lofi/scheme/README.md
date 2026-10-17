# Scheme interpreter

`main.sld` is the complete upstream interpreter written as ordinary, statically
checked Lofi. All 260 non-import, non-driver source forms remain, including the
interpreter's compiler, environment, macro machinery and primitive registration.
The measured worker evaluates the unchanged sorting program 100,000 times and
compares the complete 30-string result with the original expected list. Input
reading and primitive-environment initialization precede the worker.

The interpreter's language is benchmark data. The product compiler reads only the
static `.sld` file; neither the corpus runner nor execution invokes a Scheme
expander, converter, host evaluator or product interpreter. `source-coverage.json`
records every upstream form in order. The old frontend was used once as an
uncommitted authoring tool; its output is now ordinary source.

`Value` is a closed benchmark-local data type. Pairs own two explicit mutable
cells; vectors have fixed element type `Value`; numbers retain the ordinary
Integer/Rational/Number libraries; ports retain their typed handles. Every
`Procedure` case has a concrete fixed or rest signature. Dynamic calls check that
case and its arity. Source binding cells retain mutual scope, initialization order,
and errors for reads before initialization. Only a Boolean false is false.

Graph conversion allocates a mutable node before visiting its children, preserving
sharing and cycles. Equality remembers already-compared pair/vector identities;
`list?` uses cycle detection. These operations are workload code. Linear identity
memo tables and explicit tags have costs that remain visible in comparisons.
String comparisons use Unicode full folding; character comparisons use simple
character folding. The adapted Chez control retains these Value records, mutable
links, closure cases and source algorithm, while using Chez's numeric tower and
scalar services. It must remain distinct from the unchanged original Chez control.

`probes.scm` contains 26 separate observations covering arbitrary exact arithmetic,
rounding, complex promotion, Unicode expansions, cyclic pairs/vectors, aliasing,
rest calls, callbacks, scope, macros and interpreter control forms.
`chez-observe.scm` runs them through the original interpreter. `verify.mjs` runs
both those probes and the complete canonical worker against a compiled module
exporting `observe`, `bench` and `configured-count`, with its scalar provider.
The current working directory must contain this case's `input.txt` and `probes.scm`.

The shared reader does not support external datum labels. The two examples in
`unsupported-reader-labels.scm` are explicitly unsupported cases, not passing
observations. The canonical input does not use this syntax. Constructor-created
sharing and cycles remain covered by the supported probes.

Full canonical execution and all 26 supported probes passed optimized V8 and
native64. The final validation uses a separate V8 scalar provider and proves
native's retained optimized Wasm byte-identical to V8's program. An earlier native
attempt optimized an already optimized module again; it is retained as separate
correctness evidence and is not the parity result. Original/adapted Chez passed
as well. These concurrent correctness runs provide no clean timing claim. The
later [current-source frozen checkpoint](../evidence/20261015-dynamic-scheme.md)
compiles the unchanged current source and passes all six canonical routes,
including both Rust controls. Its verifier adds ordered phase checks: the
configuration and probe file each open and close once, followed by no canonical
worker or cleanup file activity. Native release counts are setup 1, probes 1,
worker 0 and cleanup 0. The original-Chez oracle separately passes all 26 probes;
the Rust controls run the complete canonical sorting predicate. The case remains
unmeasured.

The [integration review](../evidence/20261015-two-ports-review.json) repeats the
canonical worker and probes with the current scalar runtime and native lowering.
It reuses the retained guest after checking source-form identity, rebuilds both
providers, and again checks optimized guest byte equality.

The focused simplify review used an independent explanation with no repository
access, followed by a critique against the implementation. It retained the closed
value cases and exhaustive dispatch because they expose the interpreter's dynamic
boundary. Conversion memoizes a shell before visiting children; mutable string
and bytevector wrappers preserve their underlying object's identity. Equality
tracks pairs of identities along each recursive path, which closes cycles while
still checking every sibling. A global work queue would add state without a
demonstrated need for these inputs. The implementation does not promise bounded
stack usage for arbitrarily deep graphs. Upstream algorithm functions and
exhaustive cases may exceed the repository's ten-line target.
