# Rust Ray source, result and lifetime audit

The corrected reference preserves the original full50 renders, resolution1,
33-sphere scene and complete ASCII PGM output. Its rendering region is byte
identical to the historical Rust source: SHA256
`ed9d2858a58dd486765089d3ef4eef87fa260293a8d922d10e7de2d48aa4fbac`.
Only the result/count driver and signed-count reporting contract change.

Each invocation constructs all three large spheres and the nested5-by6 grid,
then reverses the complete Vec to reproduce source prepending. Row-major pixels
normalize the eye-to-image direction and traverse every sphere. The smaller
quadratic root remains eligible even when negative; a zero quadratic coefficient
uses the linear root. Actual intersections undergo Euclidean distance, with
strict less-than updates and finite1e308 initial distance. Center-minus-hit
normalization, color multiplication and ties-to-even rounding remain unchanged.
There is no positive-root filtering, squared-distance substitution or scene cache.

Rust stores Point/Sphere fields inline and visits a contiguous Vec; temporary
root/hit options remain values. Original Scheme constructs world cons cells,
point/sphere vectors and its returned hit vector. Strict Scheme uses immutable
products and explicit option/hit wrappers, with a Ref for the world. Allocation,
tags, field widths and reclamation differ. Rust frees its scene before returning
from each invocation, inside the timer. Original Scheme retains its global world
until the next invocation resets it, and retains the final world afterward.
No allocation or lifetime parity is claimed.

Each invocation deletes an existing path, creates an owned file, formats every
decimal pixel/newline into an8192-byte BufWriter, explicitly flushes, then drops
the writer/file before returning. All these operations are timed. Linux Node/WASI
syscall diagnostics reconstruct every separately closed image: full50 with an
initially absent output has50opens/49unlinks/50closes,200writes and1,475,850bytes;
count2 with an existing sentinel has2opens/2unlinks/2closes and59,034bytes.
Every one of these52 images is the complete canonical PGM. File drop releases
the handle but does not propagate close errors; general close-error equivalence
is outside this checked contract. Buffering and file adapters also differ.

The result starts at false inside the started workload clock, as in common.scm.
Signed i64 repetitions update it to symbol ok only after a successful invocation.
Zero/negative counts perform no scene or file work and retain false. An explicit
Datum Atom-kind/value guard rejects string ok, compounds and wrong values. The
shared reporter accepts a Display count so negative CSV labels remain exact;
other callers still supply usize. The predicate precedes stopped-clock capture.
On rejection Rust panics without normal CSV, while Chez prints INCORRECT without
capturing its stopped jiffy clock. No per-invocation result allocation was added.

The small shared reader encodes canonical false as Atom spelling#f. Alternate
boolean/numeric spellings and escaped boolean-like symbols are outside this
snapshot's equivalence. Counts must fit i64; nonnegative extents/storage must fit
Wasm32. The checked scene is finite. No general reader or exceptional/nonfinite
geometry rewrite is included.

Actual corrected Wasm and untouched original Chez pass32 complete-image,
result-kind, nonpositive-count, signed-label and path checks. The existing suite
runner additionally passes16 executions of the four regression fixtures. Two
syscall runs prove all52 complete outputs/lifecycles. These are correctness
observations, not clean performance samples. Original full-count validation and
its old source/artifact are preserved separately.

The exact release Wasm retains scene/grid/reverse work, both sphere branches,
Euclidean/discriminant/normal square roots, full raster/formatting, file lifecycle
and the final predicate. It hoists ray-invariant a/4a/2a within each pixel before
the sphere walk. No extra barriers counteract this compiler optimization. Static
Wasm and full-output evidence do not establish V8 physical allocation or machine
instruction counts.

A fresh Sol6.1-max explainer received no history/files and then one informed
critique. It accepted the private static result literals plus explicit Datum-kind
guard; a result enum would add no demonstrated guarantee. It accepted the11-line
driver as one visible parse/clock/repeat/predicate/report operation. Scene data
construction, intersection arithmetic and complete file output remain cohesive
operations rather than being split to meet a count. No geometry refactor was
warranted. The review does not complete other structural/SLaTeX cohorts.
