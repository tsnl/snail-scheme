# Instance initialization and ordinary-call contracts

Run `chibi-scheme -I src -I tests tests/lofi-instances/check.scm`. Each attempt retains its commands,
outcomes, raw and optimized Wasm, native lowering, and artifact hashes under
`build/lofi-instances`. Native execution consumes the retained raw Wasm and must
produce exactly the optimized guest bytes executed by V8. Native runs force GC
at allocation boundaries.

- `initialization.lofi` checks row order independent of class method order,
  general expressions, unused instance effects, initialized name aliases,
  concrete selection of a generic name, shared mutable captures and repeated
  calls without repeated initialization.
- `unused-forward-alias.lofi` checks a premature read at an unused instance site.
  The later initializer must not execute.
- `trapping-expression.lofi` checks that a later row's trap preserves earlier
  effects and prevents subsequent rows from running.
- `wrong-result.lofi` rejects a wrong method result even when its general
  expression and instance are unused.
- `ordinary-calls.lofi` checks argument effects before operator effects, unused
  eager arguments, immediate and rest calls, and sequential-let polymorphism.
- `immediate-parameter.lofi` and `named-parameter.lofi` reject the same attempt
  to use a function parameter at incompatible types. `aliased-parameter.lofi`
  checks that a sequential alias cannot generalize that parameter's type.

An explicit scalar provider records each effect as it occurs. V8 compares the
complete callback sequence; native execution compares the complete output
stream. A failed `main` intentionally prevents subsequent exported guest calls,
so the harness observes failure effects without calling back into that module.
After successful initialization, V8 also checks the stored history through an
ordinary export; the guest's complete predicate checks it on both targets.

The existing `typeclass-member-initializer` integration fixture deliberately
changes from success to a trap: its instance reads `member` before the later
initializer. Its source remains the regression for that former behavior.

The instance-initialization simplify pass used a local behavioral explanation
and the parent's contract critique. Both a fresh explainer and a reused reviewer were unavailable
because the collaboration tool reported `agent thread limit reached`; this is
not an independent-review claim.

The ordinary-call simplify pass used a fresh independent no-files explanation
and a focused debate. Calls instantiate existing schemes but never generalize
arguments; source bindings retain their value restriction. Deleting the old
direct-lambda-to-polymorphic-let path needs no replacement representation.
Static inference may inspect the operator first to discover argument domains;
runtime evaluation still performs all arguments before the operator.
