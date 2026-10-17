# Roots and tail calls

Roots include live reference locals/operands, globals, tables, mutable static
literal reference slots and Rust-owned ABI table entries. A collection excludes
stale temporary slots. Nonfinal types carry their concrete type identity and
parent chain; recursive group canonicalization preserves Wasm equivalence and
inherited field layout. A sibling cast traps. The frontend's existing rejection
of cyclic datum-label literals remains; mutable literal graphs can form cycles
at runtime and are traced correctly.

Reference locals live directly in writable root slots. Reference temporaries
have private storage: a collecting call publishes its live operands and held
arguments, then reloads relocated values into that storage before subsequent
uses. LLVM promotes the private storage and supplies branch/loop phi nodes.
Derived addresses never survive collection; they are recomputed from repaired
bases. The Rust array constructor also roots its own initializer when the array
contains references. A caller's root does not repair a helper's by-value copy.

Temporary publication skips a store when the same private reference cell already
matches that exact active root slot. Every collecting call still publishes its
complete active count and restores every live temporary, including duplicates.
Collection rewrites the published slot; restoration then repairs the private
cell, so the equality survives movement. Ordinary labels and returning guest or
unknown native calls discard this evidence. Only direct allocation/collection
and a private trap-success edge preserve it. Raw SSA reference parameters always
publish their value; their spelling does not prove an unchanged address.

The root ABI requires generated modules to define `native_gc_relocatable_roots`.
Objects emitted before this contract must be regenerated from Wasm before
linking with this runtime; otherwise linking fails on that missing symbol.
Existing statically linked executables retain their own runtime and behavior.
Foreign code must publish writable roots and reload them after collecting calls,
or pin rooted objects with `native_gc_pin`/`native_gc_unpin`. Pinning alone does
not keep an object alive. These unsafe pin operations set/clear one bit; callers
must coordinate overlapping leases and unpin only after all raw-pointer uses end.

Each record's immutable field descriptor is resolved once before tracing its
edges. Marking makes no callbacks and neither mutates nor mutably borrows the
owned offset storage, so a growing worklist cannot invalidate it. Each offset
is checked against the object's payload extent before its field is read;
pointer-shaped scalar words remain unscanned.

Guest functions use LLVM `tailcc`; C imports and exported adapters keep the C
convention. A tail transfer resolves its target and performs all checks before
unlinking the caller's root frame. Outgoing values remain in native ABI locations;
the callee links reference arguments before any allocation or callback. No
asynchronous collector observes the transfer. Tests force collection immediately
before unlink and after callee entry and execute changing-arity tail calls with a
256-KiB stack and bounded root depth.


Direct-call collection effects are solved over the resolved Wasm call graph.
Imports, dynamic calls, allocation and unknown operations are conservatively
collecting. A call proved noncollecting needs no temporary root publication.
Derived array addresses are therefore safe only until the next collecting call.
The collector is synchronous; there is no concurrent trace of an unlinked frame.
