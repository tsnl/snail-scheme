# Arithmetic, array access and inlining

This campaign measures six unchanged canonical workloads: fib, fibfp, mbrot,
array1, bv2string and gcbench. It is a focused ablation, not a replacement for the
57-workload comparison. The retained inventory still contains all 57 sources.

Main now contains wrapping/IEEE arithmetic ([PR #268](https://github.com/tsnl/snail-scheme/pull/268))
and direct native array access ([PR #270](https://github.com/tsnl/snail-scheme/pull/270)),
the **C** combination. Against the checked baseline, V8 Mandelbrot takes 60% less
time and native bytevector/string conversion takes 33% less time. GCbench is a
remaining regression: 17% more time on V8 and 57% more natively.

**D remains an unlanded experiment.** Removing the forced inlining threshold
returns GCbench near the checked baseline, but slows bytevector/string conversion
by 42% on V8 and 70% natively versus C. A blanket threshold change trades one
problem for another. The next policy experiment should distinguish useful helper
inlining from recursive expansion, with the same measured controls.

## Changes and controls

| Arm | Arithmetic | Native array access | Guest Binaryen always-inline threshold |
| --- | --- | --- | --- |
| A | Checked integer/finite-float overflow | Rust helper calls | 40 |
| B | Wrapping integers, IEEE floats | Rust helper calls | 40 |
| C | Wrapping integers, IEEE floats | Direct checked LLVM operations | 40 |
| D | Wrapping integers, IEEE floats | Direct checked LLVM operations | Default 2 |

All arms run mandatory Binaryen with the existing optimization pipeline. D
removes only the guest `--always-inline-max-function-size=40` override. The
installed Binaryen 132 help reports a default of 2; other inlining decisions
remain enabled. Post-link
Rust-runtime optimization keeps its existing policy. B/C raw and optimized Wasm
are byte-identical for all six workloads; C/D raw Wasm is byte-identical. These
identities separate the native lowering and guest optimizer changes.

| Arm | Frozen compiler revision |
| --- | --- |
| A | `729cb5231f28de519e42e29d1ddce578870a5e8c` |
| B | `4b58cfb4dbb820a93cc116d34bf8eefc58b831a2` |
| C | `73faf9f36013c4ec4ee8ad401cab56353db9f8d9` |
| D | `e7ba61dfc4dbd9278a52e8387ede504dffe69dae` |

Default arithmetic now wraps I32/I64 addition, subtraction and multiplication
modulo the integer width, and uses IEEE F32/F64 arithmetic, including infinity
and NaN. Division, conversion and bounds traps retain their documented
contracts. The [language specification](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/doc/book/sfir/types.md)
defines these semantics; this campaign changes no benchmark source to obtain
them. Explicit checked arithmetic and the Scheme frontend remain future work.

Removing overflow guards also changes what Binaryen decides to inline. B/A is
therefore the effect of the full compiler pipeline, not a measurement of the
cost of overflow checks alone. The recursive fib and fibfp modules grow sharply
under the forced inlining policy; the code-size table records this effect.

GCbench exposes another consequence in the emitted native LLVM:

| Arm | LLVM bytes before LLVM optimization | Largest root-frame capacity |
| --- | ---: | ---: |
| A | 137,796 | 15 slots |
| B | 7,837,216 | 541 slots |
| C | 7,838,938 | 541 slots |
| D | 148,670 | 16 slots |

[The static layout record](gcbench-inline-layout.json) identifies each function,
source line and artifact hash. These are capacities supplied to root-frame
registration, not dynamically live-root counts, collection time or machine-code
size. C/D differ only in the guest inlining override, so the much larger frames
are a concrete consequence of that policy on this unchecked program.
At a collecting call, the native publisher includes every reference-local slot
plus current reference operands. Its active count excludes stale operand
temporary slots; this code does not analyze which reference locals have had
their last use. The record includes the publisher implementation. These facts
identify possible root-publication and scanning costs without assigning them a
dynamic cost or claiming additional object retention was measured.
Changing inlining also changes call counts and generated instructions. D/C
isolates the overall policy effect, not the separate contributions of code size,
root bookkeeping and collection.

## Measurements

All four campaigns completed: **792/792 processes passed**, including 132 warmups
and 660 measured samples. The tables show median seconds and time ratios; lower
ratios are faster. Each median has five samples in the retained records.

### SFIR on V8

| Workload | A seconds | B seconds | C seconds | D seconds | B/A | C/B | D/C | C/A |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 1.372788 | 1.465510 | 1.465594 | 1.471353 | 1.068 | 1.000 | 1.004 | 1.068 |
| fibfp | 0.363743 | 0.274724 | 0.274326 | 0.265727 | 0.755 | 0.999 | 0.969 | 0.754 |
| mbrot | 0.725377 | 0.288920 | 0.289173 | 0.289200 | 0.398 | 1.001 | 1.000 | 0.399 |
| array1 | 5.980189 | 5.416933 | 5.414127 | 5.368429 | 0.906 | 0.999 | 0.992 | 0.905 |
| bv2string | 0.880805 | 0.680417 | 0.680773 | 0.964210 | 0.772 | 1.001 | 1.416 | 0.773 |
| gcbench | 1.003009 | 1.174810 | 1.174944 | 1.010091 | 1.171 | 1.000 | 0.860 | 1.171 |

### SFIR native

| Workload | A seconds | B seconds | C seconds | D seconds | B/A | C/B | D/C | C/A |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fib | 3.187649 | 3.195086 | 3.194432 | 3.194831 | 1.002 | 1.000 | 1.000 | 1.002 |
| fibfp | 0.590098 | 0.580437 | 0.580212 | 0.580389 | 0.984 | 1.000 | 1.000 | 0.983 |
| mbrot | 0.876872 | 0.733218 | 0.729269 | 0.728679 | 0.836 | 0.995 | 0.999 | 0.832 |
| array1 | 3.254486 | 3.286974 | 3.272293 | 3.212531 | 1.010 | 0.996 | 0.982 | 1.005 |
| bv2string | 1.696002 | 1.415595 | 1.134169 | 1.932531 | 0.835 | 0.801 | 1.704 | 0.669 |
| gcbench | 1.937708 | 2.995597 | 3.046623 | 1.928089 | 1.546 | 1.017 | 0.633 | 1.572 |

### Current combination against Chez and Rust

These are **C** medians divided by the same campaign’s comparator medians, for
these six cases only. Original Chez controls are used in this table; the three
available adapted controls remain in the records. A value of 2 means SFIR takes
twice as long. The representation differences below limit what the comparison
says about compiler quality alone.

| Workload | V8 / Chez original | Native / Chez original | V8 / Rust Wasm | Native / Rust native |
| --- | ---: | ---: | ---: | ---: |
| fib | 1.095 | 2.386 | 2.198 | 4.370 |
| fibfp | 0.323 | 0.682 | 1.199 | 2.508 |
| mbrot | 0.130 | 0.328 | 0.797 | 3.319 |
| array1 | 0.808 | 0.488 | 17.115 | 1.362 |
| bv2string | 1.465 | 2.441 | 15.785 | 43.116 |
| gcbench | 3.045 | 7.895 | 1.686 | 5.431 |
| Geometric mean (6 cases) | 0.741 | 1.309 | 3.139 | 4.758 |

### Repeated controls

Each cell is the geometric mean time ratio followed by its per-case range.
Small changes overlap the observed variation; the large changes above do not
track equivalent movement in the controls.

| Control | Cases | B/A mean [range] | C/B mean [range] | D/C mean [range] |
| --- | ---: | ---: | ---: | ---: |
| chez-original | 6 | 0.991 [0.974, 1.001] | 1.004 [1.000, 1.014] | 1.000 [0.990, 1.014] |
| chez-adapted | 3 | 0.998 [0.995, 1.001] | 1.001 [0.999, 1.002] | 0.998 [0.994, 1.000] |
| rust-wasm | 6 | 0.998 [0.986, 1.003] | 1.005 [1.000, 1.016] | 1.001 [0.990, 1.018] |
| rust-native | 6 | 0.998 [0.994, 1.001] | 1.002 [0.999, 1.009] | 1.000 [0.995, 1.005] |

### Optimized guest Wasm size

Bytes include the retained debug/name information. B/C are byte-identical. D
shrinks recursive modules substantially without a broad timing improvement.
These are guest module sizes, not linked runtime sizes or native machine code.

| Workload | A bytes | B/C bytes | D bytes |
| --- | ---: | ---: | ---: |
| fib | 775 | 50310 | 689 |
| fibfp | 882 | 70301 | 733 |
| mbrot | 2390 | 1738 | 1738 |
| array1 | 1754 | 1670 | 1519 |
| bv2string | 7539 | 7691 | 5764 |
| gcbench | 3375 | 63578 | 3300 |

## Protocol

Each arm freezes source, tools, inputs and built artifacts before measurement.
The 33 available routes each receive one warmup and five measured fresh
processes, rotating route order, on CPU 2. All routes run the canonical workload
and final correctness predicate. Guest monotonic timers include the repeated
worker and final predicate; setup, module instantiation, formatting and cleanup
are outside that clock. V8 compilation/tiering during the worker is included.

The unavailable adapted Chez controls for fib, fibfp and array1 remain visible.
Independent Rust Wasm/native and original/adapted Chez controls are repeated in
every arm to expose machine drift. These are sequential campaigns on a shared
desktop machine with no competing agent build/test jobs during the quiet window;
they are not hardware-isolated laboratory measurements. Medians and all five
samples are retained. Ratios below one indicate less elapsed time.

The machine is an Intel Core Ultra 7 270K Plus running x86-64 Linux, using the
`intel_pstate` driver and `powersave` governor. CPU 2 has no listed sibling
thread. The recorded tools include Node 24.19.0, Chez 10.4.1 and Binaryen 132;
the preparation records retain exact executable hashes, including the Rust and
LLVM toolchains. Pinning and repeated controls expose some variation but do not
make small changes statistically conclusive.

## Representation findings

The workload sources and inputs were not changed to improve these numbers.
Several representation differences remain relevant to comparison with Rust:

- **array1:** SFIR uses eight-byte I64 elements on both targets. Rust uses
  `usize`, which is four bytes on Wasm32 and eight bytes natively. Both sources
  request zero initialization, forward filling and reverse copying; source
  inspection alone does not establish which initialization stores survive.
- **bv2string:** SFIR bytevectors use packed bytes with separate owners. SFIR
  strings store 32-bit Unicode scalars in blocks of at most 8,192 characters,
  while Rust uses UTF-8 `String`. For ASCII, the string payload differs by four
  bytes versus one. SFIR's mutable character indexing, validation and allocation
  contracts differ from Rust's. Decoding validates/counts, allocates, then
  validates/decodes again; encoding counts before allocating and filling.
- **gcbench:** Each SFIR source node contains two separate mutable `Ref` cells;
  Rust puts child pointers directly in one `Box<Node>`. Ref identity and aliasing
  prevent blindly flattening those cells. Rust releases dead trees
  deterministically; SFIR traces them. Equal logical node counts do not imply
  equal physical allocation counts.

The separate [checked-input native array diagnostic](../2026-10-15-native-array-access/README.md)
demonstrates removal of
opaque slot/length calls with unchanged static allocation/root/type-test call
counts. Its constructor-layout and disassembly observations describe those
retained checked-input artifacts, not the unchecked artifacts in B/C/D and not
dynamic allocation counts. Native collector headers and explicit root costs do
not describe WasmGC engine layout or collection cost.

The unchecked C artifact also retains zero-capacity root entry/exit and closure
type checks in Array1's recursive loops. The
[complete emitted LLVM for two such loops](array1-native-loops.json) records
their source revision and artifact hash. These functions still need local
storage for references even though they register no roots; removing empty
registration must preserve that storage. This is static evidence of remaining
operations, not a measurement of their individual cost.

The next focused experiments are omitting root entry/exit for statically empty
root frames, avoiding redundant zero fills where the allocator already clears
the payload, and carrying UTF-8 validation evidence into private filling loops.
Each requires its own correctness proof and ablation; none is included here.

## Failed host attempts

The first baseline invocation bypassed the public frozen-driver bootstrap. Its
missing supervisor exposed an after-fork launch-validation bug: child exceptions
could resume the benchmark driver and race its journals. No guest ran and there
are no valid timing samples. Its partial journal is explicitly non-authoritative.

A second preparation failed before canonical execution while a deliberately
broken launcher regression ran in another sandbox. Source behavior and nearly
coincident failure timestamps strongly implicate inherited cleanup deleting a
reused temporary-directory name; this cause is an inference, not a filesystem
trace. The third baseline uses the same source and a private temporary root.
Both failed histories are retained separately and excluded from every ratio.
PR #271 moves launch validation before fork and isolates the regression test.

## Correctness

The arithmetic change passes 2,074 arithmetic cases on raw Wasm, optimized Wasm
and native execution, including first-class calls, effects and discarded
results. An independent exact-arithmetic oracle checks the 379 changed outcomes
and 1,695 unchanged outcomes; 54 required integer division/remainder traps remain.
Narrowing and literal
range checks, exact Integer/Number suites, and all 320 compiler integration
cases pass. Native array tests cover null/immediate references, unsigned bounds,
operand effects before traps, packed fields and forced collection. The UTF-8
suite covers all 1,112,064 Unicode scalars. The alternative inlining policy also
passes the arithmetic and complete compiler integration suites.

## Evidence and reproduction

`A` through `D` preparation records contain the source/input/tool hashes,
canonical correctness records and built route identities. Their measurement
records retain every sample, warmup, unavailable route and process result.
The original plan, final measurement journal and machine record are also copied
byte for byte, so their recorded hashes can be checked without the temporary
campaign directory. Preparation exports select the relevant manifest fields;
they are not copies of the full manifest's build-dependency inventory.
Each JSONL entry stores the original process-record text in `record_json` and
its SHA-256, allowing that record's exact bytes and its stdout/stderr hashes to
be checked independently. Frozen `/tmp` paths identify the original artifacts;
they are provenance, not portable paths. Failed host histories are stored
separately and contribute no performance samples.

The report exporter independently checked plan order, process completion and
descendant cleanup, stdout/stderr hashes, reported durations, all medians, tool
and input identities, and the B/C and C/D Wasm identities. Tool paths inside
each frozen directory differ by construction; comparison normalizes only that
directory prefix and retains executable hashes and all other path components.

Use a fresh checkout of the desired revision and the public timing entry point.
The benchmark driver discovers its corpus from the current directory, so first
enter that checkout:

```sh
sfir_checkout=/absolute/path/to/checkout
sfir_evidence=/absolute/path/to/new-campaign
export TMPDIR=$(mktemp -d /tmp/sfir-campaign.XXXXXX)
cd "$sfir_checkout"
chibi-scheme -I "$sfir_checkout/src" -I "$sfir_checkout/wasm-native/scheme" \
  -I "$sfir_checkout/benchmarks" "$sfir_checkout/benchmarks/sfir/timing.scm" \
  prepare --output "$sfir_evidence" \
  --benchmarks fib fibfp mbrot array1 bv2string gcbench \
  --compile-timeout 1800 --run-timeout 1800 --cpu 2
chibi-scheme -I "$sfir_checkout/src" -I "$sfir_checkout/wasm-native/scheme" \
  -I "$sfir_checkout/benchmarks" "$sfir_checkout/benchmarks/sfir/timing.scm" \
  measure --output "$sfir_evidence" \
  --quiet-window 'Record the actual coordinated quiet interval here'
```

Do not invoke the copied frozen driver directly: the public entry establishes
its runtime environment. Preparation and measurement must use a fresh output
directory; the schedule cannot resume or retry. See the
[harness protocol](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/sfir/README.md#clean-timing-protocol) for prerequisites
and timer boundaries. The full 57-workload report remains the broad comparison;
these six selected workloads cannot establish a new whole-suite ranking.
