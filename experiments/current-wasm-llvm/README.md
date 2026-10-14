# Current Wasm through archived LLVM and Immix

This isolated experiment starts from `archive/llvm-backend-20261012`
(`5c277ab`). It restores the retained Immix recovery patch, whose collector
matches `7f698687b9e7c6af4272a6a19c35ca9e1a9f9d11`, and adds scalar benchmark
imports. It does not compile today's Scheme with the old frontend. Binaryen
132 disassembles the exact frozen optimized Wasm that Node executes, and the
archive's existing reader, resolver, and LLVM emitter lower that disassembly.

The production archive defaults to BDWGC and has no separate shadow-root
stack. This experiment uses the custom collector's explicit reference frames,
declared object layouts, global slots, and tables. It does not use LLVM
stack maps. Tail calls unlink the caller immediately before transfer; the
callee publishes its parameters before any synchronous collection. There is
no moving collection and no evacuation. Rust callback and finalizer lifetime
regressions run through the recovered protocol.

Immix has 32 KiB blocks and 128-byte lines. The original policy starts with
an 8 MiB allocation budget, then uses `max(8 MiB, 2 * live payload)` after
collection. It prefaults the configured arena before module initialization.
The baseline retains eight-byte array slots, including i32 Unicode arrays.
No rooting, clearing, collection, or memory bounds are removed for timing.

`prepare.py INPUT.wasm SPEC.json DIRECTORY` preserves the Wasm and specification,
records the lowering and Clang commands, and builds `DIRECTORY/native`.
`DIRECTORY/inputs.txt` carries the specification's values at runtime. The host
accepts these selected benchmarks' finite scalar or vector numeric inputs,
with one i64 benchmark result. It is not a general host for arbitrary imports.
The host object is compiled with `-O3 -fno-lto`; the generated guest and collector use
Clang 21.1.8 `-O3 -flto` and LLD 21.1.8. Thus whole-program optimization cannot
replace opaque import calls with known input values or identity functions.

Run `native inputs.txt` for a clean sample. Initialization, heap prefault,
and exported `main` precede the timer, as in the Node host. The timer includes
`bench(count)` and its final result assertion. Each sample must use a fresh
process. `--validate` counts opacity calls and checks setup/workload counts;
`SNAIL_NATIVE_GC_INTERVAL=1` forces collection before every allocation.
`SNAIL_GC_STATS=1` enables separate collector diagnostics. None of those
diagnostic settings belongs in clean timing samples.

The original String (100), mbrotZ (1,000), and quicksort (2,500) inputs pass with
the archived 300 MiB arena. Original mperm (20, n=10, k=2, ell=1) exhausts that
arena during setup; the failure is retained. The named mperm 1 GiB capacity
variant sets `SNAIL_GC_HEAP_BYTES=1073741824` and passes, including actual
collection. Its prefault and initialization remain reported separately.
Deriv fails the archive's explicit rejection of nonfinal struct subtyping;
its original failed build is retained rather than changing the input module.

Validation includes actual Node execution of the same bounded artifacts,
every-allocation native collection checks, the archived native suite (proper
tail calls, traps, callback roots, and resource finalizers), `make test`,
`make check`, strict C, and ASan/UBSan Immix allocation-hole tests. Leak
detection is disabled for sanitizer checks because it cannot run under this
sandbox's ptrace mechanism; address and undefined-behavior checks remain on.

The later LLVM statepoint stack-map and bitmap-sweep experiment is retained on
`experiment/shared-binaryen-20261011` at
`e3e66bc6a45263928cfd1e7a31659d00e6a47ca7`, in
`benchmarks/results/2026-10-11-llvm-stackmaps`. It is a different root-transport
and allocation experiment. This baseline deliberately names the committed
`7f69868` explicit-frame collector that actually executes here; its results do
not characterize the later stack-map variant.

Timing results must come from the coordinated quiet CPU 5 window, with default
Node 24.19 tiering and `NODE_OPTIONS` unset. Full-input instrumented correctness
runs and bounded collection stress runs are not performance samples.
