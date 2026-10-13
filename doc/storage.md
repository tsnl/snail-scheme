# Fixed storage constraints

The storage pass runs over resolved IR after the original source contracts have
been checked. Its holes describe reachable values and allocation identities;
they are distinct from rigid `All` variables. Dependency tasks propagate joins
until no hole changes. Equivalent capture locations collapse deterministically
to the oldest hole. An existing allocation site conservatively joins all its
reachable invocation contexts.

An initial solve supplies container shape hints to monomorphization. These hints
distinguish copies without claiming an immutable element contract. The emitter
then records emitted specialized and ordinary call targets. A final solve pins
those choices and follows their dependencies, including generic entries whose
bodies bridge to concrete workers. Dynamic closure calls retain their flow
edges; a declined specialized call follows its emitted ordinary target. A fresh
backend module selects all physical layouts from that final solution; it does not
retain tentative layouts from the earlier emission. Ambiguous calls remain conservative.
Generic bodies retained for adapters can become unreachable after call selection.
They keep generic calls; only expressions actually scanned by the final solution
retain pins. Backend queries cannot turn an unexecuted body into a reached one.

Each mutable vector allocation has one element hole. Aliases retain that
allocation identity, so every reachable write contributes to the same hole.
An unknown mutator or foreign escape makes ordinary reachable mutable slots
generic. Explicit constructor-established Array contracts remain enforced at
every alias boundary; their nested mutable referents still escape normally.
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
factories can retain boxed instances. Literal pairs and vectors currently retain
generic payload slots, even when their syntax contains only numeric values;
inference of their element constraints remains a precision improvement.
Bulk copy validates both ranges before mutation and uses `array.copy` for equal codecs. It never consumes a multiple-value envelope.

Public vectors are distinct from raw `$slots` used for call arguments and native
multiple values. An AWI `values` envelope retains its public vector owner, so
later slot writes remain visible. Calling through AWI materializes transport
slots when needed. Scheme and Rust retain managed references; no numeric GC
address is exposed.

Closure copies retain explicit source identity. The solver joins each family's
ordered capture holes, including whether a binding can receive an unconsumed
foreign values envelope. A semantic type alone cannot authorize scalar storage
at a boundary that has not consumed its value. Each family has one immutable
environment struct shared by its generic entry and specialized workers. Concrete
mutable or early-captured bindings use shared typed cells. Payloads and their
initialized state are separate: any successful write makes the location readable,
and a later source initializer overwrites the same location. Capturing a location
never reads it. Unknown raw callback parameters retain their envelopes until the
original source consumption point.

Locals and globals also use solved concrete storage. A binding has one payload;
there is no generic mirror beside a scalar cache. Concrete reference storage is
nullable until initialization, while initialized reads recover its non-null type.
Incoming parameters are separate ABI locals, so a mutable parameter can use a
concrete worker argument and initialize its shared cell without boxing.

Pairs have separate car and cdr holes. Known rest arguments also have a distinct
pair allocation for each spine position, so unrelated positional values do not
force every field to share a representation. Records have one hole per nominal
field. Constructor values flow into their named fields; omitted unannotated
fields include `Unspecified`, and duplicate constructor names retain the last
value after every supplied value has been read. Unknown names keep the generic
constructor and its original error order.

Native pair and record payloads live directly in the identity-bearing Wasm
struct. Category supertypes admit boxed and native instances; no per-field cell
or additional wrapper is needed. Record structs retain their nominal descriptor.
Accessors check that descriptor before field lookup. Generic bridges read and
write raw carriers without consuming a values envelope, while concrete access
requires both a semantic type and canonical single-value ingress. A physical
layout check lets the same accessor accept a boxed instance produced by an
opaque factory. Aliases and cyclic references continue to refer to one object.

The unsafe [Array/Storage interface](unsafe.md) adds explicit invariant contracts.
A managed witness chooses a semantic codec at construction, including for empty
arrays. The existing vector wrapper stores that immutable contract; there is no
extra identity wrapper. An ordinary vector annotation cannot seal storage.
Generic and AWI writes validate raw carriers against the original contract.
Mixed-codec copying into a contracted destination validates the complete range
before any write. Eqref contracts retain raw envelopes and their live owners.
Specialization preserves Array/Storage types rather than replacing them with
uncontracted shape hints, and concrete Array facts can select native access even
when no allocation identity is available.

`scripts/test-storage` checks linked execution with storage enabled and disabled
and inspects emitted allocation/access sites for concrete arrays, bindings, and
pair/record structs. The compiler parameter `storage-optimizations-enabled` in `(snail-scheme wasm-storage)`
disables inferred concrete container and binding payloads without changing source
checks. It also changes shape-driven specialization choices: emitted copies,
callback adapters, and downstream inlining can differ. Comparisons must account
for those call changes as well as payload storage. Explicit Array contracts retain
their required physical layouts and native access in this mode; they are not part
of the ordinary storage ablation. Both modes keep closure environments as structs.

`scripts/test-arrays` checks the explicit interface in optimized, storage-disabled,
and guarded modes, including source rejection, actual linked Wasm, AWI mutation
and raw envelope behavior, and native array call sites.
