# Ackermann passes the original input at the default V8 stack

Current raw and Binaryen-optimized Scheme Wasm pass the complete original input:
two repetitions of `ack(3, 12)`, returning `32765`. The native64 executable and
its exact final Scheme Wasm on V8 also pass. No engine stack or tiering flag is
used. **This is correctness preparation; clean timings remain pending.**

The generated Scheme source and input specification are byte-identical to the
earlier experiment. Running its archived artifacts with the same current Node
and host reproduces the old distinction: raw Wasm passes, optimized Wasm fails
with `RangeError: Maximum call stack size exceeded`. The newly compiled
optimized artifact passes under that same host. This establishes a change in
the generated artifact's behavior; it does not identify which intervening
compiler change or V8 compilation decision caused it.

| Artifact | SHA-256 |
| --- | --- |
| Unchanged generated Scheme | `5de295636b46db2530466696fd3c4fff4a5a95b03278ee9d4355e67d650dec47` |
| Archived optimized Wasm, fails | `b96438a8307505b3deb5448442a4f059673dc5e88772b3cc5cc6084968b95d07` |
| Current optimized Wasm, passes | `590a5d3acec095bb81aaa40ee1b4a941c5e79c09c2e0c90b6d959d8861b39704` |
| Exact native-final Scheme Wasm, passes on V8 | `efbf4ea6a3e27682b015e3087408c25730ea3628deb55a641e8a7f834aec3a4a` |

## Complete recurrence and native execution

Scheme preparation uses compiler/library basis `2e4c6ec`. Native preparation
uses `c0ba036`, whose backend includes the reviewed allocator annotations;
it consumes the already prepared optimized Wasm and runs Binaryen again before
mechanical lowering. Its C provider has checked positional scalar signatures
for input and opacity calls. Native setup and `main` run before the optional
clock, the full recurrence and numerical predicate run inside it, and formatting
and cleanup follow. Diagnostic mode disables that native clock and counts the
two scalar opacity calls per iteration.

The native executable passes `(m,n) = (0,0), (1,4), (2,3), (3,4), (3,12)`,
including both one and two repetitions of the full input. The original compiled
Chez program passes the full input too. Current Scheme preparation retains its
original raw/optimized one- and two-repetition checks.

The current optimized Wasm retains the recursive Ackermann body, both outer
tail calls and the inner non-tail recursive call. Its counted worker consumes
the scalar opacity functions' returned arguments. Native `f.5` retains the
inner recursive machine call and a loop for the outer tail call, with the
existing readiness/null checks. The native worker still reaches that body.
No closed-form Ackermann replacement or smaller canonical input is used.

## Rust controls and the remaining stack difference

The unchanged Rust reference passes on native. Its default recursive form fails
the full input on V8 in both raw and optimized Wasm, while its small `(3,4)`
control passes. These failures remain recorded. They are not silently replaced
by a larger engine stack.

The reference's existing `--heap-frames` option passes the full input on native,
raw Wasm and optimized Wasm. It keeps pending recursive calls in a `Vec` and
performs the same recurrence. This changes stack representation, allocation and
control flow; any later timing must label it separately from recursive Rust.
Native Rust retains its existing tail-call-to-loop source expression and
`black_box` boundaries. Scheme uses typed scalar imports; neither boundary
establishes identical optimization opportunities.

Every incidental clock in these validation records was observed while other
agents could work. None is a clean timing sample. V8's existing assertion
converts the result to text before stopping its clock; native compares I64s,
Chez uses the original numeric predicate, and Rust its original assertion.
Those small host differences remain explicit in a future comparison.

## Evidence

The archive preserves original/generated sources and inputs, compiler source
snapshots, raw/optimized Wasm, native LLVM and executable, C interfaces/entry,
Rust source and binaries, emitted Rust code, command records, archived failures,
complete successful outputs, and the original preparation drivers. Build caches
and external tool binaries are excluded. The native build manifest records its
exact input/tool identities; the earlier preparation records Node, Chez, Chibi
and Binaryen identities. Node is 24.19.0 and Binaryen is 132.

`archive.py` creates or verifies the fixed evidence bundle and checks every
unique regular member against its digest before any extraction. Commands in the
records retain their original absolute paths. Re-execution elsewhere requires
an explicitly verified path mapping and the pinned external tools. Preparation
does not increase the current 39 measured workloads.
