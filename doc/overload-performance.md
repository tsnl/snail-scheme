# Overload trial compilation cost

Granular compiler tracing is added by [PR #306](https://github.com/tsnl/snail-scheme/pull/306).
It separates source-labelled binding/function spans from optional hot-helper
counts and inclusive/self timing. This fix only changes overload compatibility
filtering; its ordinary copied unification trial remains authoritative.

The later [3D compilation work](compilation-performance.md) also replaces the
copied trial's exception handler and addresses repeated whole-environment and
whole-program scans. The measurements below describe the earlier prototype.

## Cause

The profile counted 136,363 compatibility trials in checking and 185,706 each
in specialization and emission for the current Siegework prototype. Each trial
entered `guard` before copying types and attempting unification. Chibi 0.12's
`scheme/misc-macros.scm` implements `guard` using `call-with-current-continuation`
on entry, with another capture on the handler path. Entering a trial therefore
has stack-dependent cost even if a successful unification never raises.

The compiler often tries an I32 signature against an I64, Bool, or differently
shaped signature. Those fixed contradictions do not need a copied solver or an
exception handler. They became particularly expensive while the emission visitor
held a deep continuation. The phase called emission includes concrete typing and
overload selection; this cost was not WAT writing or Binaryen optimization.

The new preliminary check resolves existing links, treats every variable as
unknown, and compares only fixed pair structure and atom identities. A definite
contradiction returns false immediately. All other cases still run the existing
copy-and-unify trial. That trial retains responsibility for rigidity,
repeated-variable consistency and occurs checks. Nominal definitions compare by
identity. The filter introduces no solver constraints; resolving existing links
may perform the same path compression as ordinary unification.

## Observed build costs

| Ordinary build sample | Seconds |
| --- | ---: |
| Before, `62f4e0d6` | 152.968 |
| Before, `a1c8ec37` (measurement script only) | 149.226 |
| After, `c84d62ad`, first sample | 34.368 |
| After, `c84d62ad`, second sample | 35.202 |

Both optimized builds produced byte-for-byte identical shader and simulation
Wasm to both original builds. The observed wall time fell from 149–153 seconds
to 34–35 seconds. See the [recorded samples](measurements/overload-prefilter-2026-10-17.json)
for commands, revisions, loads and hashes. `$REPO` denotes the checkout path.

This is a small, single-machine observation. The source is the Siegework prototype
and derived-serialization revision on `cleanup/miscellaneous`, not the larger
colony application in PR #302. The builds include shader/simulation compilation
and browser packaging. They use Chibi 0.12.0, Binaryen 132, Node 24.19.0 and
`BINARYEN_CORES=1` on an Intel Core Ultra 7 270K Plus, Linux x86-64. No competing
compilation was deliberately started during samples; cache state and other host
load were not controlled. These are compiler build timings, separate from the
unchanged 57-workload runtime evidence.

Reproduce the ordinary build from the repository root:

```sh
chibi-scheme -I bootstrap \
  apps/siegework/build.scm "$PWD" "$PWD/build/siegework-overload-check"
```

For phase traces, use the measurement command from #306 on a checkout containing
both changes. Run timing samples sequentially; run `hotspots` separately from
clean timing. Instrumentation changes the stack and allocation behavior being
measured. Do not compare its totals as if they were clean samples.

## Correctness evidence

Host tests compare the filtered trial against the previous copied-unification
algorithm for 722 type-pair/rigidity-mode combinations. The family includes scalar
and structured types, shared holes, rigid binders, function/rest shapes and two
opaque nominal identities with the same name. Focused cases cover linked holes,
repeated-variable contradictions and occurs-check failure. The filter leaves
unresolved input holes unbound.

Additional local checks passed:

- `make test` and `make check`.
- 105 selected overload, class and Scheme integration fixtures on raw/optimized Wasm.
- All 20 focused contract fixtures on raw/optimized Wasm.
- Actual native execution of generic overload rows, returned closures and
  qualified overloads, returning the expected 42 with collection forced at every
  allocation. These are correctness checks, not native timing measurements.

The measurement record includes the exact selected case inventory and completion
records. CI runs the repository's broader correctness inventory separately.
