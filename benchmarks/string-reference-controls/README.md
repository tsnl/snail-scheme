# Matched String storage diagnostics

These four controls investigate storage width, allocation initialization and
buffer lifetimes in the canonical String workload. They are separate from the
57 reference implementations; the canonical source and frozen artifacts stay
unchanged. This directory contains correctness and retained-work controls,
not a performance campaign.

The original input is `100`, `500000`, `524278`: 100 invocations, each with ten
trials starting at `abcdef`. Each trial grows while its length is at most the
threshold. One growth constructs `123` + old + `456` + old + `789`, then copies
the back half and the front half including their shared middle element, then
constructs a fresh back + front result. The first growth returns
`56abcdef789123abcdef45`. Both overlapping substrings are owned copies.

`byte` uses `Vec<u8>` and `u32` uses `Vec<u32>`, with the same ASCII element
values, operation order and four fresh allocations per growth. Neither appends
into a substring buffer. The old buffer is released after first construction;
first, back and front remain alive until the final buffer is complete. A fresh
seed allocation begins each trial. `byte-zeroed` and `u32-zeroed` initialize
each allocation to zero, clear its logical length, and perform the same full
append operations. The allocation policy is selected by a compile-time
constant, so each mode has a specialized trial function.

Fresh owned buffers do not imply fresh physical pages. Rust's allocator may
reuse released storage in its linear memory. Scheme drops roots at assignment
and leaves reclamation to GC; it also retains the final global string until the
next reset. Rust releases each completed trial immediately after its length is
read. These are explicit allocation-policy and lifetime differences.

The frozen canonical Rust String implementation uses UTF-8 byte storage,
`format!`, two owned substrings and append into the back buffer, which can reuse
or reallocate its capacity. It also keeps the old string borrowed through the
whole growth. Comparing that implementation with these controls changes library
operations and lifetimes as well as allocation count. Comparing the byte/u32
controls holds their algorithm, copy order and release points constant, while
changing element width and the resulting allocator requests.

## Timing and result boundaries

Datum reading and count/threshold parsing precede the clock. The timed loop
contains all 100 invocations, all ten trials per invocation, all growth and
destruction work, and the final supplied length equality. Result and CSV
formatting follow clock capture. `black_box` covers the threshold at each
invocation, the returned length, and each complete final trial buffer before
reading its length. No complete-payload comparison is added to the timed loop.

The optional `--audit` performs a separate one-growth observation and one
additional complete trial after the timer. It prints first, back, front, final
and trial contents. This audit has different intermediate-buffer lifetimes and
is not the last timed output. The controls accept nonnegative Wasm32 `usize`
inputs and the fixed ASCII seed; they do not implement general Unicode strings
or Scheme's unbounded numeric domain. Zero and negative count behavior outside
the canonical positive-count input also differs from the original harness.

## Rebuild and verify

Use the Rust, Node and Chez tool identities in the archived build provenance.
The release profile is optimization level 3, LTO, one codegen unit and aborting
panics. Preparation and validation are separate from clean measurements.

```sh
cargo build --offline --release --target wasm32-wasip1 \
  --manifest-path benchmarks/string-reference-controls/Cargo.toml
cargo test --offline --manifest-path benchmarks/string-reference-controls/Cargo.toml
chibi-scheme -I src -I wasm-native/scheme -I benchmarks benchmarks/string-reference-controls/tests/check-controls.scm \
  --artifact benchmarks/string-reference-controls/target/wasm32-wasip1/release/string-reference-controls.wasm \
  --output build/string-controls-check
```

`checks.sld` copies the retained original Chez source and input from the Lofi
corpus, compiles that source with the selected Chez, and records their identities.
Historical binary bundles remain in [Git history](../history.md).
Actual Node/Wasm and original Chez pass
the full input, threshold boundaries and wrong-result rejection. Each Rust mode
also passes complete-payload checks. An independent untimed oracle checks every
element; negative checks corrupt interior elements without changing length and
truncate outputs. The original Chez grow/trial bodies provide a second complete
oracle, including threshold 500000; only their final driver invocation is
replaced by untimed observation calls.

## Retained allocation and initialization work

The frozen optimized Wasm retains one seed allocation and four distinct loop
allocations, six dynamic `memory.copy` operations per growth, literal stores,
all ten trials and the full outer count. Both zeroed modes call `calloc`; its
conditional `memory.fill` remains in the emitted module. Source-level zero
initialization alone would not establish this.

`tests/allocation-probe.scm` creates a separate diagnostic by redirecting only
the four specialized trial functions' allocation calls to counting wrappers.
An active marker attributes the original `calloc` zero fill to those selected
calls. Internal allocator calls and startup allocations are not double counted.
Removing the inserted instrumentation recovers the exact original optimized
WAT. The unmodified reassembly must pass the full input before the instrumented
module is checked. All 48 complete-payload replays on both transformed artifacts
pass: six thresholds, four modes, two artifacts.

Full-count instrumented runs reach 61,000 selected allocations: 1,000 seeds and
60,000 growth allocations. Requested bytes are 3,145,173,000 for byte storage and
12,580,692,000 for u32 storage. The zeroed modes reach 61,000 zero fills covering
those logical byte volumes; the other modes reach none. These are reached Wasm
operations and lengths, not physical memory traffic or newly faulted pages.

`tests/resource-wasi.mjs` compiles/instantiates before bracketing `WASI.start` with
Node resource counters. That bracket includes guest startup, reporting and any
requested audits. Process RSS high-water marks, final linear-memory capacity
and analytically live payload bytes describe different quantities. The largest
growth's live buffer payload is 1,572,833 byte elements, or 6,291,332 bytes for
u32; this excludes allocator headers, padding, released blocks and runtime data.
No diagnostic duration or resource counter here is a clean performance sample.

## Focused clarity review

Two fresh explainers received behavioral briefs without repository access:
one for the four-buffer workload and one for the probe/oracle orchestration.
Informed debate retained direct width-specific operations, compile-time
allocation policies and separate untimed audits. A record holding every buffer
in timed growth would obscure lifetime and change the return ABI, so timed
growth returns only its final buffer. Instrumentation remains separate from the
primary artifact. No additional runtime refactor was justified.

Longer functions are bounded exhaustive CLI dispatch, the complete timing and
predicate operation, atomic instrumentation with exact recovery, freezing and
checking an ordered artifact pair, and complete oracle/test cases. Keeping these
contracts together exposes ordering and provenance; short copy/ownership
operations remain named directly. Full-suite review work is separate and still
contains explicitly pending older cohorts.
