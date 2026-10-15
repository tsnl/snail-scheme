# Focused review of the Ray prerequisites

The pinned simplify skill at revision
`f09cc98ec9796e1616a8db2127b67ee1aaef6f81` guided this pass. A fresh Astra/max
explainer received no history and inspected no files, implementation, or diffs.
Its neutral brief described scalar FFI, text-file behavior, resource ownership,
numeric rounding, and the original renderer's timing boundaries. The implementing
agent owned all source inspection, edits and checks.

The independent explanation separated Scheme character iteration and number
formatting from Rust's owned buffered files. It proposed temporary pathname IDs
and output IDs, and identified the important failure boundary: Wasm traps do not
run Rust destructors. It also identified the inability of plain Scheme sequencing
to close after a callback trap. For round, its model was exactly the native
same-type nearest operation, with no conversion through an integer.

The informed debate introduced the provider's actual constraints. One instance
runs one invocation at a time, path traversal calls no user code, and Rust does
not call Scheme. Therefore a private `Option<String>` replaces path IDs. Taking
the String before a filesystem operation consumes it on success and failure.
The Result can be handled after all RefCell borrows end, so sentinel return codes
and a deferred diagnostic slot are unnecessary.

Standard idempotent Scheme close requires observable alias state. A private
shared `Ref<I32>` marks the wrapper closed before Rust removes and disposes of
the file. Rust retains only live entries and issues monotonic IDs; closed-ID
tombstones and generation counters are unnecessary. Callback self-close works,
and a returned alias is already closed. Raw absent/stale IDs remain errors.

Port.close leaves its payload resident after a flush error. The scalar adapter
explicitly drops a removed Port before reporting a fatal error. Whole-instance
cleanup clears pathname staging, detaches the registry before fallible work,
and attempts every close/drop while preserving the first returned error. A
terminal trap forbids further Scheme execution, while the cleanup export stays
available. No GC finalization, recoverable exceptions, or arbitrary host-trap
recovery is claimed.

The implementation follows that model in `src/strict_io.rs`, `src/snail/io.sld`
and the explicit pruning command. The existing buffered Port module and legacy
frontend/backend structure remain unchanged. The cleanup sweep is a deliberate
function-length exception: detachment, complete traversal, and first-error
retention are one atomic ownership operation. Long contract tests and the test
host's single WASI construction operation are also kept together.

The initial actual Node pruning proof uses the full existing Rust runtime and
a scalar caller. Both full optimization and reachability-only pruning eliminate
all legacy Root imports. The final output fixtures exercise real UTF-8 files,
the whole I64 formatting range, aliases, concrete generic callback results,
malformed raw callers, callback traps and injected flush errors through raw and
optimized linked modules. Checks assert that remaining imports are only WASI.

The numeric fixtures pass runtime arguments through direct primitives, overloaded
calls, and concrete function views at both widths. They inspect signed zero,
ties in both directions, NaN, infinities, subnormals and values outside I64.
Separate located rejection fixtures cover integers, bad arity and mismatched
function views.

The parent review additionally required cleanup to begin before Scheme main,
because top-level initialization can open a file and then trap. A separate real
file fixture now checks that boundary; the host encloses reactor initialization,
Scheme main, and worker invocation in its cleanup scope. The runtime module
header now distinguishes the legacy rooted ABI from scalar strict services.

The pass stops here because each remaining state has a concrete lifetime or
observable alias contract. Path-handle registries, deferred errors, a second Rust
crate, a general marshaling layer and a dynamic value fallback were rejected.
