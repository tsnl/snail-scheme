# TODO

Completed work lives in git history. Keep this list to open items, and keep
proposed language changes separate from implemented behavior.

## Language

- [ ] Specify general first-class Scheme variadic procedures and their lowering
  to fixed-arity calls. The current typed Scheme subset requires proper parameter
  lists; collection packing macros are implemented separately.
- [ ] Add explicit overflow-checking arithmetic operations.
- [ ] Add constrained generic instances and serialization derivation for
  parameterized data declarations.
- [ ] Extend Scheme beyond the documented typed subset: quoted data, general
  truthiness, mutation and other R7RS requirements.
- [ ] Specify procedural transformer evaluation and phase interfaces.

## Formalization

Formalization and proof tooling are deferred. They are not prerequisites for
documentation improvements. The [Ott/Rocq experiment in draft PR #325](https://github.com/tsnl/snail-scheme/pull/325)
explores generated definitions and formation proofs.

- [ ] Review the Ott grammar and named inference rules against the implemented
  language, then generate the corresponding book sections from that source.
- [ ] Add machine-checked proofs incrementally, beginning with variable scope,
  name categories, application arity and closed instance heads.

## Siegework

Keep the local preview at port **4212**.

- [ ] Rewrite the colony model with nominal sum types and `match` in place of
  integer-coded kinds, jobs and stages.
