# Invariant container and capture storage measurement

Baseline f07d1eb has production code identical to d4f0d42. Investigation worktree:
`/tmp/snail-container-storage-measurement-20261012`. All fixtures and scripts live
under ignored `build/`; production sources remain untouched.

The revised contract is a per-hole invariant layout. All aliases and write
constraints participate before allocation; heterogeneous/unknown-mutator cases
choose common/eqref storage upfront. There is no runtime backing widening.
Append/copy create fresh result holes with directional source-element joins.
Mutating a result must not pessimize a numeric source. Calls allocating fresh
objects may instantiate fresh holes; passing an existing object through two
polymorphic uses must retain one shared hole.

## Discriminating timed kernels

- `vector-f64.scm`, update: runtime-sized distinct nonintegral doubles, repeated
  read/add/write sweeps. Complete checksum occurs after timing. Old float-box
  requests per store should disappear only if real f64 backing/access is used.
- `vector-i64.scm`, update: values start at 2^40, outside i31. Read/add/write
  sweeps discriminate real i64 slots from tagged-small-integer shortcuts.
- `update-f64.scm` and `update-i64.scm` provide isolated positive cases with
  no opaque mutator/append consumer of the same allocation hole. Use these for
  clean update comparisons if generic consumers pessimize the combined modules.
- Same numeric modules, append-direct/opaque/apply: large source arrays, live
  last-result anchor, complete last-result checking outside timing. Generic
  entry must preserve the element invariant; count whether copies/conversions
  happen and inspect actual source/destination backing types. No per-element
  checksum or callback inside the copy timer.
- `managed-pair-vector.scm`: distinct pair references, repeated large-integer
  car updates, shallow-copy alias checks after timing. Separates precise managed
  element refs and pair field layouts from merely renaming generic refs.
- `shared-cell.scm`: a numeric mutable cell shared by updater/observer closures.
  Updater returns unspecified; final scalar observation occurs once afterward,
  avoiding a per-update generic return box hiding removed cell-store boxes.

Final clean cells will be selected after candidate WAT confirms eligible
layouts, not multiplied over every correctness dimension. Pilot common counts
outside retained results toward roughly 0.3–1 s per cell. Size at least 65,536
for streaming/copy kernels; update traffic multiple full sweeps, not tiny vector
control. Keep old d4, same-final-compiler storage-off, storage-on. Unsafe stable
contract equivalents are separate adapter sources after API freeze.

## Representation coverage, separate from timing

`representation-coverage.scm` exercises vector elements, pair/record fields,
immutable numeric captures, shared mutable cells, scalar parameters/returns,
managed references, generic identities and factory allocations. It includes
large I64, NaN, signed zero (reciprocal), bool/Unicode chars, overlap, mixed-layout
append/copy, fresh storage and shallow element identity.

The parent's portable `backend-storage-bindings.scm` (9054cd8) adds early-read
failure and assignments preceding initialization, direct/apply shared-parameter
cells and independent factory cells. Its physical `check-binding-layouts.scm`
helper tests scalar/reference readiness and an RHS failure that leaves an old
payload intact. These are correctness/shape checks, without timing claims.

Coverage must map actual source allocation/access sites to WAT declarations:
array element type, struct field types, field mutability, opcode get/set/copy
and parameter/result types. Declared-but-unused types are not evidence. A heavy
observer records reached constructor/access sites and identifies executed
layouts; field f64 inside an ordinary boxed `$float` does not qualify as a
specialized container/capture. Counter elapsed times are never clean evidence.

Expected shape cases:

- Homogeneous mutable F64/I64 vector and numeric fields: concrete data slots.
- Heterogeneous aliases and opaque unknown mutators: common/eqref at allocation.
- Append/copy result broadened by a string/bool write: generic result, numeric
  source independently concrete when supported by the analysis.
- Same scalar factory input, separate numeric vs heterogeneous allocations:
  either complete-key specialization gives distinct layouts, or both are
  conservatively generic; producer/consumer disagreement is incorrect.
- Reusing an existing mutable vector through identity twice: shared hole and
  common layout across both uses, never an independently freshened numeric view.
- Stable `(Array T)`/`(Storage T)` factory annotations: separately test rejecting
  incompatible writes; do not apply those annotations to portable baselines.

## Reproduction and timing coordination

Use the exact Node/host/tool environment from the preceding report, captured
hashes for every module/source/input and the compiler checkpoint. Parent and
Astra may build during preparation/correctness runs; those durations are not
performance evidence. Request a quiet window before any clean run or CPU/GC
sampling. Original modules stay immutable; instrument copied modules separately.
CPU profiling plus GC traces are an observer mode independent of clean/counter
runs. Add the selected-five regression sweep only if broad vector/pair ABI
changes require it; no full corpus rerun during implementation.
