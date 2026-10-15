# Focused String representation explanation and debate

Scope is the new private String choice, allocation, indexing, permission and copy
operations in `strict-wasm.sld`, their focused integration fixtures and TOUR.md.
Existing frontend/typeclass architecture and other backends remain outside the
refactoring. The parent owns independent review, inspection and informed debate.

A fresh Sol 6.1 maximum-reasoning explainer received the neutral behavioral brief,
with no conversation history, repository files, implementation, diffs or tools.
Its first model retained a wrapper for identity, length and permissions. The
parent challenged the necessity of that wrapper: identity is fixed, length is
fixed, flat storage has a permission cell, and source String typing plus the
existing explicit Top witness establish the semantic type. The revised model
requires no short wrapper. Short String identity is the array itself; long
String identity is its immutable owner. A nonnullable private WasmGC eq reference
carries only those two cases, without source Top conversion or dynamic fallback.
A physical array test selects storage after the String contract is established;
it never decides whether an arbitrary source value is semantically a String.
Headerless backing blocks must never escape into String slots.

The chosen short representation is `[permission, Unicode scalars]` in one native
i32 array. It contains at most 8,192 scalars, so both scalar forms retain bounded
payload allocations; its permission cell adds four bytes. Fresh empty values
are distinct length-one arrays. Array length is unsigned-extended to I64 before
subtracting the header. The unchanged full I64 construction/index checks prevent
negative or wrapped arguments from addressing the permission cell.

Long values contain permission, unsigned scalar length, a full first native i32
array and a nonempty block directory. The directory is now required, since no
short value uses an owner. Every directory slot is installed while the directory
and first array remain rooted native locals. Publishing the owner establishes
complete initialization. Independent mutable values never share payload arrays.

Copy checks permission, at <= target length, end <= source length, start <= end,
and end-start <= target length-at before narrowing or writing. Two flat values
then use one native i32 array.copy, including overlapping self-copies. Other
copies use bounded forward or backward spans. Different storage forms cannot
share identity; descending spans remain necessary for rightward same-owner
copies. Empty copies perform no backing lookup.

The debate identified a header edge hazard: if a flat physical scalar index is
p = i + 1, it has p preceding payload elements through that element, not p + 1.
The implementation avoids interpreting physical indices as logical room. Span
room uses logical cursors before adding the header: an exclusive flat end in
1..8,192 has exactly end preceding scalars. The same logical block-room formula
therefore applies to short values, and complete logical prevalidation bounds
partial last blocks. Physical offset conversion occurs only at array.copy.

A single reference array containing allocation-free i31 characters for short
values and block references for long values was considered. Full-u32 length,
kind and permission require metadata beyond one i31. It also changes scalar
storage to reference width and introduces reference-array scanning/copy/barrier
costs. Those engine costs are unresolved; the native-i32 choice preserves the
measured payload type and changes only the necessary storage case. No claim is
made that the unmeasured reference-array alternative is slower.

The implementation stays in one cohesive lowering module. Constructors,
validated copy dispatch, native directional transitions, literal construction
and exhaustive layout/runtime definition dispatch exceed the ten-line target
where keeping one complete guarantee visible aids review. Scalar read/write
emission remains one complete operation. Other new helpers establish one
permission, length, index, block, physical offset or span-room operation.
Focused correctness and scalar/growth controls decide whether the draft is
worth retaining; exact performance is deferred to a coordinated CPU window.
