# Types

## Types

Scalars are `U8`, `I32`, `I64`, `F32`, `F64`, `Bool`, `Char` and `Unit`.
`Any` is a value of any type, used with `type-convert`.
`String` is an immutable sequence of Unicode scalars. `(Vector T)` is an
immutable sequence and `(Array T)` a mutable one whose elements are unboxed,
`(Unboxed T)`: a scalar, a reference or a struct of one unboxed field, each one
Wasm slot, so an array of points is refused and a struct of arrays stands in
for it, as typed arrays do in JavaScript; `(MutVector T)` grows at its end over
such an array. `(Ref T)` is a mutable cell, the one struct with a mutable
field, which `(snail core base)` declares ([data](#data)). `Bytes` is `(Vector U8)`, stored packed. A byte vector literal,
`#u8(137 80 78 71)`, compiles to a data segment of exactly its bytes, so a
program can carry large binary data, such as images; it cannot be a
pattern. `(include-bytes "pixel.png")` is another spelling of the literal
holding a file's bytes, with the path relative to the file it is written
in. It is replaced when the source is read, so a macro cannot compute the
path, and nothing else may be named `include-bytes`. A large file is better
linked than included: see [linked files](#linked-files).

A function type is `(-> Param ... Result)`, optionally followed by an
[effect row](effects.md): `(-> String Unit ! console)`. Two other arrows
are written the same way: `(FnOnce Param ... Result)` is called at most
once, and `(Fn Param ... Result)` has no environment, a reference to code
alone ([ownership](ownership.md#closures-without-an-environment)). A
polymorphic signature quantifies type and row variables and lists its
class requirements:

```scheme
(: map (All (A B e) (-> (-> A B ! e) (List A) (List B) ! e)))
(: sum (All (T) (requires (Num T)) (-> (List T) T T)))
```

A type variable is linear unless the signature requires `(Copy T)`, which
a body needs to use a `T` twice or to discard one
([ownership](ownership.md)).

Integer literals check against any integer or float type and are
range-checked; float literals check against `F32` or `F64`. A literal whose
type nothing determines defaults to `I64` or `F64`. Values never convert
implicitly: use `i64->i32`, `i32->f64` and the other conversions. Integer
arithmetic wraps.

Unannotated top-level functions are generalized over the type variables no
constraint mentions. Other unannotated definitions, and functions whose
types involve a class constraint, keep one type, which later uses in the
same library may decide. A library is checked before the libraries that
import it, so their uses never decide its types: `(define key-left 1)` is an
`I64` wherever it is imported, and a value meant as an `I32` elsewhere needs
the signature `(: key-left I32)`. Polymorphic definitions with constraints,
and polymorphic values that are not functions, need signatures.

## Data

```scheme
(struct (Vec3 T)
  ((x T)
   (y T)
   (z T)))

(enum Shape
  (Circle ((radius F64)))
  (Polygon ((points (List (Vec3 F64)))))
  (Empty))
```

A struct `Name` defines the constructor `Name`, accessors `Name-field` and pure
replacements `Name-field-set`. A struct is a value: its fields are immutable,
and a program that changes one holds it in a cell, `(Ref Name)`, and writes a
*place*, the cell's content or a field read from it, with `set!` or
`replace!`: `(set! (::count (ref-get r)) 1)`. Reading or writing a cell
performs `mut`. `Ref` is the one struct with a mutable field, and a pattern can
only skip its content, with `_` ([ownership](ownership.md)). An enum defines a
constructor and accessors per case, and its fields are immutable. Cases are constructors, not types, and are
always applied: `(Empty)`.

A field is also read by its label alone: `(::label s)` reads the field
`label` of whatever struct `s` is, and `(::from::x s)` reads `x` of what
`from` holds. Each label is a typeclass, `(::label R T)`, over the record
type and the field's type, with the one method `::label`; a struct without
mutable fields has an instance per field, and the record's type decides
the field's, so a path needs no annotation where the record's type is
known. A library may declare an instance for a type that computes the
field, and a generic function requires one, `(requires (::label R
String))`, to read the field of any record that has it. Names beginning
with `::` are reserved for paths.

```scheme
{{#include ../../../tests/programs/field-paths.sld:paths}}
```

Patterns are `_`, variables, literals (numbers, characters, strings,
booleans) and constructor patterns, nested freely. `(List T)` is an ordinary
enum with cases `Nil` and `Cons`.

## Typeclasses

A typeclass declares methods over its parameters; instances may be generic
and may require other instances:

```scheme
(typeclass (Describe T)
  (: describe (-> T String)))

(instance (Describe (List T))
  (requires (Describe T))
  (define (describe items)
    (string-join (map describe items) ", ")))
```

The checker chooses each instance when it checks a use and records that
choice; monomorphization copies the chosen method for each type, so no
dictionary exists at run time. Instance heads must not overlap. Classes have
no superclasses: a signature lists every class it needs. Unbound names in an
instance head are its type variables.

### Rows as parameters

A class may take a row as a parameter. A parameter its methods write after
`!` is a row, and the others are types. Each instance writes its row in its
head, so the instances of one class may perform different effects:

```scheme
{{#include ../../../tests/programs/classes-effects.sld:store}}
```

A use performs what its instance's head says. Reading a `Directory`
prints, so `fetch-twice` at a `Directory` performs `console`; at a `Table`
it is total, and a total function may call it. The row is found from the
types, not matched: the types choose the instance, which must be the only
one for them whatever rows the others write, and its row is charged to the
call, as a call is charged what its callee performs. A generic function
that requires `(Store e S)` performs `e`, which its signature names, and
each caller is charged what its own type's instance performs. A
requirement may give a closed row instead, as `(Store (!) S)`, which admits
only the types whose instance performs no more.

An instance's row is closed, or ends with a row variable that its
requirements of row classes give theirs, which the types they are given
decide:

```scheme
{{#include ../../../tests/programs/classes-effects.sld:logged}}
```

Fetching from a `(Logged Table)` performs `log`, and from a
`(Logged Directory)`, `log` and `console`. A head's row names no control
effect. `Drop` and `Clone` are classes over a row too
([releasing](ownership.md#releasing)), whose rows are found from a type's
structure where it has no instance.

Arithmetic and comparison are the classes `Num`, `Ord`, `Integral` and
`Fractional`; `Show` converts values to text, and `Drop` releases them
([ownership](ownership.md#releasing)).

## Effects

Every function type has an effect row, the effects calling it may perform,
and a function without `!` is total. [Effects and handlers](effects.md)
covers rows, their inference and polymorphism, local mutation, declaring
and handling effects, control operations with a one-shot `resume`, latent
rows and defaults.

## Proposed callable typeclass

**Design for review, not implemented.** Replace function arrows with
`impl Fun` contracts, and use `fun` for named function definitions:

```scheme
(: square (impl (Fun I64 I64)))
(fun (square n)
  (* n n))
```

`Fun` is a typeclass describing callability. It is not a concrete function
type or a universal closure representation. The definition determines an
anonymous concrete implementation type, associated with that definition,
which must satisfy the stated `Fun` contract. A caller does not choose
`square`'s implementation type. For a generic definition, that type is
instantiated with the definition's type parameters.

An `impl (Fun ...)` annotation on a class method similarly constrains an
anonymous associated implementation type supplied by each instance's
method definition. For example, the `ask` method of `(Ask T)` has contract
`impl (Fun T)`, while each provider supplies its own concrete callable.
Do not require every provider's closure to have the same representation.

Argument-position `impl` has a different quantifier: the caller chooses a
concrete callable type satisfying the constraint, and the consumer is
generic over it. The distinction parallels `impl Ref` arguments
([places](#proposed-places-and-locators)). Stored and returned opaque
implementations need explicit quantification rules; neither position
silently erases a family of implementation types into one runtime object.
`define` continues to bind ordinary values.

The callable contract preserves the following evidence:

| Contract | What the checker must establish |
| --- | --- |
| Argument types | Each call supplies the required arguments. |
| Result type | Continuing the call produces a value of this type. |
| Entry provider requirements | The caller supplies the outstanding providers for this invocation; ambient handlers are not automatically captured. |
| Resumption requirements | Each suspension accepts the remaining computation's requirements, and its eventual caller supplies the outstanding providers. |
| Invocation effects | The call context permits the effects of execution under the selected providers; deferred obligations remain visible. |
| Call multiplicity | The consumer calls or releases the value as its ownership permits. |

A generic `map` needs a concrete callable from `A` to `B` that permits
repeated calls. A consumer that invokes its argument once can accept a
one-shot callable under the appropriate ownership rule. `Copy` alone does
not establish callability. A one-shot continuation cannot satisfy a
repeated-call requirement. The current `FnOnce` ownership rule remains the
baseline: consume it by calling or dropping it exactly once, including
any effects of dropping its captures ([ownership](ownership.md)). The
precise multiplicity notation and internal `Fun` class parameterization
remain open; the examples omit these details rather than define a new
multiplicity default.

Both ordinary and control-capable implementations satisfy this calling
interface. `ctl` is not a subclass of ordinary functions. It identifies
an implementation that needs continuation access; typed core metadata records
its calling convention before control lowering. A repeatable callable may
suspend and a one-shot callable may return directly. Specialization must
preserve both facts.

The compiler supplies callable evidence for functions, closures and
capability methods. Whether arbitrary user data may implement `Fun` is a
separate extension. Monomorphization keys on concrete callable types and
provider implementation types, including their statically selected method
code and control behavior. An instance may capture ordinary runtime data:
two instances of the same implementation with different captured strings
share code. An effectful closure or resumption keeps its outstanding
providers as invocation parameters; its code must remain generic over those
parameters until the relevant invocation sites are specialized.

Capabilities following `!` become explicit provider arguments in the
[lowered core subsets](compilers.md#proposed-lowering-to-typed-snail-core-subsets).
Instances in scope at the call site supply them. The proposed
[effect transitions](effects.md#resumption-effects-and-effect-transitions)
distinguish entry requirements from resumption requirements; the latter
remain part of the control operation's contract instead of becoming an
implicit capture of the entry provider environment. Both invocation and
cleanup effects remain checked. Control operations still need delimiters,
and resumption restores internally established handler scopes.

Migration must cover signatures, function definitions, bootstrap forms,
macros, formatting, highlighting and diagnostics together. Examples of
the proposed surface use `(impl (Fun ...))`, never a bare `(fun ...)` as
a concrete type. The spelling of `Fn` and `FnOnce`, old-form compatibility
and anonymous-function syntax remain review questions.

## Proposed places and locators

**Design for review, not implemented.** A place is a concrete type; `Ref`
is the capability implemented by places that select a value of a given
type. Generic consumers accept `impl Ref T` and preserve the concrete
place type for specialization. There is no conversion to a single
concrete `Ref T`, runtime path descriptor or accessor-function dictionary.
The names below are proposed; the implemented `Ref` above is still the
current cell type.

### Concrete places

Write the internal shape schematically as `Place<Base, Path>`. `Base`
identifies the root storage representation and `Path` describes the
access steps at the type level. Allocating mutable storage for a `Point`
returns a root place with an empty path. The backing storage is always
allocated on the GC heap, including when bound to a local variable.

Projection composes paths. If `p` is a root place selecting a record,
`p.position.x` produces a concrete place type whose path identifies both
fields. It does not first copy `position` into a temporary. The root and
field path determine the selected type; neither the caller nor inference
can choose a different target type for the same place type. A computed
getter does not establish storage, and writable-field evidence must obey
the defining library's access rules.

For managed roots and paths consisting only of inline fields, the runtime
value is just the root managed reference. All path steps are erased by specialization;
projection allocates no locator object and installs no runtime dispatch.
The emitted accesses use fixed field indices, as WasmGC requires
([instruction syntax](https://webassembly.github.io/spec/core/text/instructions.html)).
The place keeps its root alive through that reference. Replacing the root's
content leaves a retained place selecting the same field in the new value.

### Reference capability and argument sugar

`Ref T` describes access to storage containing `T`. Internally its evidence
relates a concrete place type `P` to its unique selected type `T`; write
that relation as `(Ref P T)`. The compiler derives it from valid place
construction and projection. User instances cannot assert arbitrary
storage layouts. Using the proposed parenthesized signature spelling:

```scheme
(: zero! (impl (Fun (impl (Ref I64)) Unit ! mut)))
(fun (zero! target)
  (ref-set! target 0))
```

This elaborates to a universally quantified argument type, schematically:

```scheme
(: zero!
   (All (P)
     (requires (Ref P I64))
     (impl (Fun P Unit ! mut))))
```

The caller chooses `P`. Calling `zero!` on two different field paths
specializes it for their distinct place types; both write an `I64` without
boxing or converting either place. Each argument-position `impl` introduces
an independent type variable. A named `P` expresses that two arguments, or
an argument and a result, must have the same concrete place type.

The capability admits reading, writing and swapping with `mut` recorded.
Reading must satisfy the existing copying rules for the selected value.
Managed place handles are unrestricted even though their contents have a
separate type: duplicating a handle preserves aliasing and does not copy the
stored object. The compiler can derive `(Copy P)` from its place evidence;
this implication must be explicit in checking, since current user classes
have no superclasses. Existing restrictions on shared cell contents remain:
linear values cannot be stored there without a separate ownership and
finalization design. This proposal does not permit moving a linear value
out of aliased storage or silently dropping one on replacement.

`impl Ref T` in an argument is static polymorphism, not an existential
container. Different place types cannot be put in one homogeneous list or
returned from different branches merely because they select the same `T`.
Such code must keep its alternatives explicit or invoke the generic
consumer within each branch. Returned or stored opaque `impl` types need
a separate language rule; this proposal introduces no automatic erasure.
The same principle applies to the [callable class](#proposed-callable-typeclass).

### GC-heap storage for local variables

All place-backed storage is allocated on the WasmGC heap, including
storage for local variables. A local allocation returns the same concrete
root place as any other allocation. Field projection composes the same
static paths, and generic consumers use the same `impl Ref T` capability.
Source scope does not select a different storage representation.

There are no stack allocations, stack-place types or stack-borrow
lifetimes in this design. The compiler must not replace this storage with
Wasm locals as an allocation-elimination strategy. A Wasm local can hold
the managed root reference; the referenced storage remains a GC object.
Every alias retains that same root.

The managed root remains valid when retained by a closure or saved
continuation: GC follows the reference when control lowering unwinds the
Wasm activation. Existing restrictions on storing linear values in shared
cells still apply; managed lifetime alone is not a resource-finalization
policy.

Exact allocation syntax and automatic versus explicit reads remain open.
Tests must establish GC-backed storage for local allocations, two aliases
observing writes across a call, and a place retained across a suspension.
The Place/Ref distinction is identical in each case.

### Array element places

A dynamic array index is runtime data. The static path records an indexing
step, but not the index's value: `array[i]` and `array[j]` have the same
concrete place type when their array types agree. They carry different
indices. An indexed place therefore contains the selected array reference
and index, while its path description still disappears during
specialization. No specialization is generated for each numeric index.

There is at most one dynamic index per place, and its indexing step is
the leaf. Native array elements cannot contain inline struct fields, so a
place cannot continue through fields inside an array element. Reaching
through an element that holds an explicit reference reads that reference
and establishes a new root. For an array of arrays, selecting `a[i][j]`
first reads the inner array at `i`; the resulting element place retains
only the inner array and `j`. This is a property of each resulting place,
not a limit on the number of indexing expressions in source code. Reads
used to obtain a new root still perform their declared effects.

Evaluate the receiver and index once, check bounds when constructing the
place, and retain the selected fixed-length array. Later reads and writes
use that reference and index; bounds checks may be removed only when their
validity is proved. No unchecked truncation of a source integer to a Wasm
index is permitted. A reference stored in an element is a value: reaching
through it requires a dereference step whose construction retains the
selected target. Updating that element later does not retarget an already
constructed place into the old target.

Growable containers need a separate invalidation or stable-storage rule;
a saved element place must not silently follow a reallocated buffer.
Enum payload projection also needs a case-validity rule. Neither extension
is implied by ordinary struct projection or fixed-array indexing.

### Native array layout contract

Arrays admit only element types explicitly supported by the native Wasm
array representation. Arrays of struct values are compile-time errors,
including single-field structs; this deliberately tightens today's
`Unboxed` exception for a one-slot struct. The compiler must not silently
box elements, transpose a record into several arrays, or pack heterogeneous
fields into bytes to make such an array compile.

Scalar and packed element types use their declared native storage mapping.
Explicit managed-reference elements remain possible, with their indirection
visible in the source type. A reference capability is not itself an element
representation: an array of `impl Ref T` cannot erase heterogeneous place
types. A concrete place may be an element only when its representation is
one supported native reference; an array-element place carrying both a root
and an index does not qualify. Source struct values remain rejected even
when an implementation could box them into references.

This guarantees the representation category and absence of hidden element
boxing or layout conversion. Physical GC object headers, byte offsets and
alignment are still engine choices; native WasmGC storage does not expose a
C-compatible memory layout. Future inline aggregates would require an
explicit extension of the array contract, not a silent change in layout.

The WasmGC [post-MVP nested-data design](https://github.com/WebAssembly/gc/blob/main/proposals/gc/Post-MVP.md#nested-data-structures)
sketches inline arrays of structs and interior references. At the time of
this review it is not listed as an active staged proposal in the
[proposal tracker](https://github.com/WebAssembly/proposals); the design
must not depend on a delivery date. The active
[Multibyte Array Access proposal](https://github.com/WebAssembly/multibyte-array-access/blob/main/proposals/multibyte-array-access/Overview.md)
addresses wider accesses through numeric arrays, not arbitrary inline
aggregates containing managed references.

### Implementation evidence

Checking must produce structured path evidence and preserve the concrete
place type through substitution, interfaces and monomorphization. Lowering
must consume that evidence instead of recovering writable storage from the
syntax of a getter call. Keep root and dynamic-index evaluation order,
GC liveness and aliasing rules beside the code that implements them.

Acceptance tests must pass a root place and distinct field places to one
generic consumer, retain a place across root replacement, and read and
write checked array-element places with runtime indices. Rejections must
cover computed getters used as storage, inconsistent target types,
implicit place erasure, linear cell contents, every struct-array shape
and indexed places used as native array elements. Execute linked Wasm and
inspect the relevant lowering to establish that field-only places retain
only a root and that access uses static field indices. Bootstrap and
compiled execution must agree.

## Foreign functions

`extern` declares a total foreign function; the declaration is the boundary's
unsafe assumption.

A foreign call may take a final `String` or `Bytes` argument. The compiler
copies it into the runtime's staging buffer just before the call. A String
arrives as its Unicode scalar count, with four bytes per scalar in staging.
Bytes arrive as an `i32` address: a little-endian `u32` length followed by
that many packed bytes. The host reads the current memory buffer and copies
any bytes it retains before returning or awaiting; later calls reuse staging.
Imports are leaves and must not call back into Snail-Core while reading staging.

An exposed function passes scalars directly and managed values as opaque engine
references. JavaScript can retain those references and pass them to synchronous
Wasm constructors/projectors, but cannot inspect their fields or substitute a
JavaScript object, string or typed array. Exposed `String` and `Bytes` are managed
arrays; the staging convention above applies to calls into foreign imports.
Affine values, including records that contain them, cannot cross this unrestricted
boundary. Exposed signatures remain monomorphic and their effects need host bindings.
The host must respect the declared Snail-Core types: Wasm representation checks do not
prove nominal identity or permit treating immutable `Bytes` as a mutable `Array`.

An exposed `(Option Any)` crosses as `null` for `None` or the opaque `Any`
payload for `Some`. The wrapper converts at the boundary; internal Options
keep their normal enum representation. Plain `Any` remains non-nullable.
This exception applies only to exposed parameters/results; a host import
returning `(Option Any)` still expects its ordinary enum. A host builds no
managed value for a typed host operation: its imports take and answer
scalars, and the library builds the result from them, in the waiting task's
own call ([the native boundary](../runtimes/networking.md#wasm-boundary)).
A task's handlers are evidence its saved frames hold, so nothing about them
crosses the host. See
[waiting on the host](../runtimes/tasks.md#waiting-on-the-host).

`unsafe-cast` is unchecked, like `unsafe-total`
([local mutation](effects.md#local-mutation)): it turns a `Funcref`, a
function another module exports, into a function of whatever type the
context expects (`(snail shell wasm)`). `dynamic-cast` is its checked
counterpart, for a function a plugin exposes with `dynamic`: it makes the
function only if the policy it is given accepts the signature of the
expected type ([plugins](compilers.md#plugins)).

## Linked files

`(snail shell resource)` ties a file to a library as one of its dependencies
instead of embedding it, as Python's `importlib.resources` addresses a
package's data, and the library reads it when it needs it:

```scheme
(import
 (snail core base)
 (only (snail shell task) tasks)
 (snail shell resource))

(: hero Resource)
(define hero (link-file "art/hero.png"))

(: hero-bytes (-> Bytes ! resource tasks))
(define (hero-bytes)
  (read-resource hero))
```

- **Found beside the library.** The path is relative to the file the form is
  written in, as `include-bytes`'s is, a `generate-library` recipe's for a
  producer's own forms, and may not leave its directory: `.`
  and `..` are resolved, and an absolute path, an empty name or a path that
  climbs out is an error. A file that is missing fails the build with the
  library and the path.
- **Shipped by content.** The build places the file as an object of the
  program's store, at `STORE/sha256/DIGEST`, where DIGEST is the SHA-256
  of its bytes in hex, in every build that produces one: project program
  and browser targets, `scripts/snail-tool run` and `compile`, and the
  development loop. A linked program's store is `store/` beside
  `program.wasm`; a per-library build's `modules.json` names its store,
  relative to itself, and lists each object with its size. The name is
  never a path or a library's: libraries that link the same bytes ship one
  object, an object is written once and never rewritten, and a file's name
  changes exactly when its bytes do. The module itself records what it
  links: `link-file` becomes a call to an import from `snail.runtime.link`
  named for the digest, which answers the file's handle. Editing a linked
  file therefore compiles again the library that links it, and its
  importers, whose modules name the new digest.
- **A handle, not the bytes.** `link-file` evaluates to a `Resource`, which
  names a file and nothing more. The type is exported without its
  constructor, so a program cannot make one from a string: holding a
  `Resource` is evidence that its file ships. `(read-resource r)` returns the
  file's `Bytes` and performs `resource`, an effect with host defaults on
  Node, in the browser and on wasmtime. It is not `fs`: a page has no
  filesystem, and a program with none still reads its own files.

**A file is read when the program asks for it.** A host reads nothing a
module links when it instantiates the module. `read-resource` waits for the
host as a task does (`through-host` in `(snail shell task)`), so it performs
`tasks` and runs in a task. The first read of a file reads it, Node and
wasmtime from the payload's directory and the browser by fetching beside the
page's module, and later reads of it from the same module return the same
bytes. A file the program never reads is never fetched, so a library may link
far more than any one program uses. A file that cannot be read traps the task
that reads it. The bytes under a digest never change, so a host keeps what it
has read by digest: a module linked again reads a file it still links without
fetching it, and an edited file, under its new digest, is read anew. For the
same reason a server may let a browser cache the store for good, as the
development server does.

## Dynamic values

`Any` holds an unrestricted value together with its type's identity.
Affine values cannot cross this boundary. Nor can a function that performs
effects, wherever it sits in the value's type, or a value of a type
variable, which may be one: a type's identity has no effect rows, so such a
function could come back out claiming to perform nothing, and run where
nothing handles what it does (`tests/programs/error-any-control-function.sld`).
`type-convert` and `type-test` refuse these types when they are written, so
an `Any` never holds a function with effects.
`(type-convert e Any)` wraps a value; `(type-convert e T)` unwraps an `Any`,
panicking if it does not hold a `T`, and `(type-test e T)` asks whether it
does. A type's identity describes its structure, its fields and cases, so a
struct whose fields change, even under the same name, is another type: a
program relinked with that change cannot take an old value for a new one.
Converting a value to the type it already has does nothing, and a value
converted to `Any` and straight back is never wrapped, so conversions can be
inserted liberally where typed code meets dynamic code.

```scheme
(define items (list (type-convert 42 Any) (type-convert "text" Any)))
(+ 1 (type-convert (car items) I64))
```
