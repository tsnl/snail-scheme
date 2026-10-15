# Neutral behavioral brief: simplex preparation

Prepare one complete pinned R7RS benchmark for a concrete typed Scheme compiler,
without changing that compiler or the other prepared benchmarks. Preparation
must preserve evidence and failures; it is distinct from clean measurement.
The parent owns a fresh independent explanation and review after this checkpoint.

The input is the entire upstream program and input file. The canonical input
requests one million invocations, supplies 740.0, and expects a two-element list
containing the index vectors #(4 1 3 2) and #(0 5 7 6). The original work function
ignores its argument but still receives it through an opaque hiding call on
every invocation. Each invocation constructs the same fresh 6-by-5 floating
tableau and runs a two-phase simplex procedure. Its loops, pivot tie decisions,
floating expression order, matrix updates and index-vector updates must remain.
The canonical predicate examines only the last result, after all repetitions.

The procedure can return infeasible, unbounded, or a solved pair of index
vectors. The target requires concrete storage and explicit mutable cells; the
adaptation may express these existing distinctions and assignments but may not
repair the algorithm, replace the kernel or shorten the canonical workload.
The unchanged original must run on Chez. The exact adapted algorithm text must
also run on Chez, with equivalent cell and result representations and the
original observable final predicate. Representation costs must be disclosed.

Preparation produces exact sources, patches explaining adaptations, full input,
compiler/tool identities, raw and optimized linked Wasm, both Chez controls,
commands, statuses and validation outputs. It must establish that earlier
generated sources are unchanged. Independent diagnostic observations must not
change canonical exports, liveness or timed work. The intended measurement uses
default V8 and remains unauthorized until parent review and a quiet window.

Small cases must expose all three result forms, ordinary and tied pivots,
duplicate constraints, greater-equal and equality constraints, a zero RHS,
unboundedness before and after a pivot, and no improving objective coefficient.
Compare the entire result, every final tableau value and the ordered matrix
stores against the original. Check changed values and structure, including
signed zero, rather than accepting only a checksum. Independently exercise the
complete canonical predicate and the original explicit argument guards.

Mathematical correctness is a separate question from preserving source behavior.
An independent small rational LP model can enumerate feasible boundary vertices
and normalized nonnegative recession directions. The original algorithm agrees
with that model on eleven supplied finite cases, including canonical optimum
681/40. However, for max x subject to x = 2 and x >= 0, its unmodified kernel
returns unbounded. This input meets its explicit guards. Preserve and disclose
that observed discrepancy; do not make an unexpected disagreement pass as an
independent mathematical success.

Inspect the exact optimized canonical module to establish which matrix, pivot,
traversal, result and repetition work remains. Static Wasm evidence does not
establish machine-code allocation counts or equal collector pressure across
systems. The archive must restore and verify its regular-file payload and run
bounded correctness checks without starting clean measurements.
