# Fixed storage constraints

The storage pass runs over resolved IR after the original source contracts have
been checked. Its holes describe reachable values and allocation identities;
they are distinct from rigid `All` variables. Dependency tasks propagate joins
until no hole changes. Equivalent capture locations collapse deterministically
to the oldest hole. An existing allocation site conservatively joins all its
reachable invocation contexts.

Each mutable vector allocation has one element hole. Aliases retain that
allocation identity, so every reachable write contributes to the same hole.
An unknown mutator or foreign escape makes all reachable mutable slots generic.
A fresh copy has its own element hole with source-to-result dependencies:
changing the copy can broaden its storage without changing the source layout.
There is no runtime layout promotion.

The implemented vector codecs cover signed 64-bit exact integers, floating
point values, booleans, characters, and managed references. Codec identity
includes the semantic boxing recipe: an integer, boolean, and character can all
use `i32` without becoming interchangeable. The wrapper's layout and backing
reference are immutable. Numeric backing arrays contain primitive Wasm values;
reference arrays contain typed GC references. Mixed types use generic slots.

Known allocation sites choose a codec after solving. Known element reads and
writes use native scalar/reference entries; a physical layout guard handles a
generic adapter's boxed allocation without changing object identity. Generic
factories remain generic. Bulk copy validates both ranges before mutation and
uses `array.copy` for equal codecs. It never consumes a multiple-value envelope.

Public vectors are distinct from raw `$slots` used for call arguments and native
multiple values. An AWI `values` envelope retains its public vector owner, so
later slot writes remain visible. Calling through AWI materializes transport
slots when needed. Scheme and Rust retain managed references; no numeric GC
address is exposed.

Closure copies retain explicit source identity. The solver joins each family's
ordered capture holes, including whether a binding can receive an unconsumed
foreign values envelope. A semantic type alone cannot authorize scalar storage
at a boundary that has not consumed its value. Typed capture/cell and pair/record
field lowering, richer element summaries in monomorphization, and the explicit
unsafe `Array`/`Storage` interface are subsequent parts of this refactor; they are
not implemented by this initial vector-storage checkpoint.

`scripts/test-storage` checks linked execution with storage enabled and disabled
and inspects emitted allocation/access sites for actual concrete arrays. The
compiler parameter `storage-optimizations-enabled` in `(snail-scheme wasm-storage)`
disables the physical container optimization without changing source checks.
