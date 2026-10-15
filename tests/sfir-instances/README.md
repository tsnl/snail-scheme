# Instance initialization contracts

Run `python3 tests/sfir-instances/check.py`. Each attempt retains its commands,
outcomes, raw and optimized Wasm, native lowering, and artifact hashes under
`build/sfir-instances`. Native execution consumes the retained raw Wasm and must
produce exactly the optimized guest bytes executed by V8. Native runs force GC
at allocation boundaries.

- `initialization.sfir` checks row order independent of class method order,
  general expressions, unused instance effects, initialized name aliases,
  concrete selection of a generic name, shared mutable captures and repeated
  calls without repeated initialization.
- `unused-forward-alias.sfir` checks a premature read at an unused instance site.
  The later initializer must not execute.
- `trapping-expression.sfir` checks that a later row's trap preserves earlier
  effects and prevents subsequent rows from running.
- `wrong-result.sfir` rejects a wrong method result even when its general
  expression and instance are unused.

An explicit scalar provider records each effect as it occurs. V8 compares the
complete callback sequence; native execution compares the complete output
stream. A failed `main` intentionally prevents subsequent exported guest calls,
so the harness observes failure effects without calling back into that module.
After successful initialization, V8 also checks the stored history through an
ordinary export; the guest's complete predicate checks it on both targets.

The existing `typeclass-member-initializer` integration fixture deliberately
changes from success to a trap: its instance reads `member` before the later
initializer. Its source remains the regression for that former behavior.

The focused simplify pass used a local behavioral explanation and the parent's
contract critique. Both a fresh explainer and a reused reviewer were unavailable
because the collaboration tool reported `agent thread limit reached`; this is
not an independent-review claim.
