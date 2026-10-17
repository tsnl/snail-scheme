# Recursive group contracts

Run `chibi-scheme -I bootstrap -I tests tests/lofi-recursion/check.scm`. Each attempt retains exact commands,
outcomes, inference traces, raw/optimized Wasm, native lowering and guest hashes
under `build/lofi-recursion`. Native builds consume retained raw Wasm; the runner
requires their optimized guest bytes to equal the module executed by V8. Native
runs force GC at allocation boundaries. The scalar effect provider and bounded
process supervisor are shared with the instance-initialization fixtures.

`generic-groups.sld` exercises independently annotated mutual functions,
permuted quantifiers, an inferred peer shared by two annotated functions,
same-tuple explicit recursion with a phantom binder, nested generic captures,
and preserved external nominal/class identities. Each group executes at its
concrete calls; the I64/Bool mixed group checks distinct specializations.

`safe-values.sld` executes self and mutual value cycles whose chosen branches
avoid premature reads, plus a computed local closure capturing its recursive
peer. `early-value.sld` and `early-capture.sld` must trap on actual premature
reads after exactly the recorded preceding effects, on both execution targets.

The negative sources stop at `source-file->core`: no specialization or Wasm
emission runs. They reject inferred and annotated type-changing self/mutual
recursion, narrowing or merging quantified binders, changing a phantom `inst`
argument, capturing an unrelated nested rigid binder, generalizing a phantom
outer binder, shared expansive storage, and an invalid generic body.

The focused simplify pass used a fresh independent no-files SCC explanation
and behavioral debate. The chosen implementation keeps the ordinary unifier
and the existing single-pass inferred-group path. Annotated recursive groups
need two judgments: one private monomorphic solution and independent rigid body
checks. A single pass with scope proxies and deferred substitution would add
another solver-like mechanism. Runtime initialization and readiness remain in
their existing passes.
