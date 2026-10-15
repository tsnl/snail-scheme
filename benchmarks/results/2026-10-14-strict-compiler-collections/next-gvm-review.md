# Next VM-data module: independent model and source-informed corrections

This is a prepared implementation brief for the unfinished complete compiler
port. No VM-data implementation or execution claim follows from this review.
The fresh Astra/max explainer `/root/strict_compiler_workload/explain_compiler_gvm`
received no files or history, only required observations and unresolved domains.
It first derived a model, then revised it after the source facts below. Both
turns completed; no review-capacity limitation remains.

## Independent explanation

The model retained encoded integer operands with a linear first-match table,
concrete frames, proper/improper argument patterns, fixed callback signatures,
mutable block state, optional destinations/counts, and comments with newest-first
lookup. It separated absent liveness from a live variable and a live closure
list, including an empty successful list. It rejected a universal object box
for literal/procedure payloads whose exact domains remain under audit.

The initial model suggested an existential liveness scan, instruction identities
for all cases, and comments associated directly with instructions. The source
comparison below corrected those simplifications before implementation.

## Source facts and informed critique

Paths/lines refer to the unchanged `benchmarks/r7rs-benchmarks/src/compiler.scm`.

- Operand interning at 3457 scans occupied entries from zero, compares both
  components with source `eqv?`, and checks capacity only after a miss. At
  capacity an existing entry still succeeds. A successful insert increments
  allocated count before writing its slot; overflow changes neither count nor
  slots. Preserve the 10,000-slot table and all six encoded operand ranges.
- Frames at 3501 retain slot/register/closed/live list aliases. Equality at 3508
  compares size only. Truncation at 3509 takes
  `nth-after(old-slots, old-size - new-size)`, including the helper's negative
  count identity behavior. Slot search at 3527 reverses the slots, starts at 1,
  and returns its current index at exhaustion.
- Liveness at 3517 checks distinguished-variable membership first, then executes
  the original complete ordered set-intersection before testing emptiness. A
  short-circuit existential scan would remove required traversal/allocation.
  Its successful closure-list result remains distinct from absence even when
  empty. The dump consumer at 8587 separately tests source `pair?`; an empty
  successful payload must follow its non-pair path, including ordinary host
  failure if the original caller invariant is violated.
- Pattern construction at 3573 starts with an exact parameter count ending in
  empty, or a threshold `parameter-count - 1` for rest arguments. It decrements
  and prepends exact counts down to the minimum. Keep the loop, improper tail,
  and behavior for unusual metadata. Do not replace it with an interval or add
  a minimum/count validity rule.
- Procedure construction at 3532 allocates first, then stores a specialization
  callback returning that same descriptor. Actual specialization callbacks at
  10460–10478 are pure: self/captured descriptor selection plus the pure
  declaration chain scan at 876. Their factories can abort while resolving a
  captured primitive; the stored callbacks do not need CompilerResult.
  Specialization input is CompilerEnvironment, not a flattened declaration list.
  Apply/branch generators at 9296 and 9400 have fixed signatures and can abort.
- Graph construction at 3583/3599 creates unset entry/branch slots and appends
  each new block immediately. Both relationship lists at 3624/3627 contain
  blocks, established by the reachability traversal at 3817. Stable block and
  procedure identity can use their actual freshly allocated mutable field cells.
  There is no demonstrated need for a dummy identity allocation on every
  immutable instruction. Label-number mutation at 3650 must remain visible
  through aliases.
- Label kinds at 3639–3647 are simple, entry, return, task-entry, task-return.
  Only entry carries parameter count, minimum, rest Bool and closed Bool. Unset
  graph entry/branch fields correspond to source empty-list sentinels and must
  fail on premature consuming access. Zero is a valid initialized value.
- Comments at 3684–3688 have a separately shared mutable root. Two instructions
  can observe later prepends through that root. Keys compare by Symbol identity,
  duplicate keys remain, and lookup stops at the first/newest match. A stored
  absent source shadows an older present source. Represent lookup absence
  separately from a present source entry containing absent source. Here source
  means the complete CompilerSource object returned by `node-source`, including
  its code and location; it must not be reduced to its location alone.

## Agreed implementation boundary

Frames and patterns can be implemented with their real existing list/variable
dependencies. Position contexts use symbol/position keys and encoded operands;
contexts that own blocks must wait for the real recursive declarations.
Complete the recursive procedure/block/instruction group together. The literal/
procedure object payload and result-type-descriptor audit remains a prerequisite
for their operations. Do not fabricate successful placeholder objects or erase
callbacks into Datum.

Useful probes include truncation sharing in both size directions; size-only
equality; empty/all-live/middle-empty slot search; successful empty closure
liveness; exact proper/improper pattern shape and unusual metadata; duplicate
lookup at full table; nonmutating overflow; shared comment mutation and absent
source shadowing; label mutation through aliases; uninitialized versus zero
fields; block identity duplicate suppression; and self-specialization identity.
Inspect or instrument the original intersection call separately: a Boolean-only
test cannot establish that its full algorithmic work remains.
