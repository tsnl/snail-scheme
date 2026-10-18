# TODO

## Language documentation

Continue improving the existing [book](doc/book/SUMMARY.md) and
[formal summary](doc/book/lofi/reference.md) incrementally. Keep descriptions
of implemented behavior separate from proposed language changes.

- [x] Specify and implement rank-one `All` with an optional `requires` clause:
  rigid variables and assumptions while checking a definition, fresh inference
  holes or explicit type arguments at each use. Retain `=>` as input compatibility.
- [ ] Specify fixed-arity Lofi functions and explicit argument packing for
  Scheme variadic procedures before removing the documented rest forms.

## Deferred: Ott formalization and proofs

Formalization and proof tooling are deferred. They are not prerequisites for
landing documentation improvements.

- [ ] Revisit Ott for the grammar and named inference rules, starting with a
  small fragment of the existing reference.
- [ ] Generate the corresponding book sections from that source once the
  workflow is established, keeping explanations and examples alongside the rules.
- [ ] Choose a proof assistant and check its integration with Ott. Generating
  definitions does not itself prove properties of the language or compiler.
- [ ] Add machine-checked proofs incrementally, beginning with variable scope,
  name categories, application arity, and closed instance heads. State each
  fragment's assumptions and proved properties before expanding its coverage.

The [Agda experiment in draft PR #325](https://github.com/tsnl/snail-scheme/pull/325)
is parked for reference. It does not replace the book or commit the project to
Agda as its eventual proof assistant.
