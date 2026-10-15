# Native allocation: separate the bump path from hole searches

Keeping hole searches out of the common allocation path reduces the full
Matrix native median from **1.899358 s to 1.685207 s**, using **11.27% less
time**. The bytevector control changes from **0.901071 s to 0.904118 s**,
using **0.34% more time**, with overlapping retained ranges. This is a useful
Matrix improvement, not a demonstrated speedup across workloads.

The selected implementation is `478a8d7`: a small reservation helper checks
the current cursor and advances it; a `noinline` helper handles hole searches
and large objects. Each bump range remains within one block, so a request
larger than one block necessarily reaches the slow helper. Payload zeroing,
start membership, collection thresholds, retries, roots and allocation
accounting retain their existing behavior.

## Controlled attribute ablation

| Full workload | Native baseline | Split, with `cold` | Selected split, without `cold` | V8, identical Wasm |
| --- | ---: | ---: | ---: | ---: |
| Matrix, 2,500 searches | 1.899358 s | 1.679619 s | **1.685207 s** | 0.704987 s |
| `bv2string`, count 100 | 0.901071 s | 0.916014 s | **0.904118 s** | 0.647106 s |

Each entry is the median of eight retained fresh processes. Their ranges are:

| Full workload | Baseline range | `cold` range | Selected range | V8 range |
| --- | --- | --- | --- | --- |
| Matrix | 1.886447–1.904990 | 1.668363–1.687004 | 1.674507–1.691080 | 0.698812–0.708560 |
| `bv2string` | 0.899332–0.904797 | 0.910714–0.919405 | 0.902394–0.910104 | 0.644881–0.650239 |

The selected native variant still takes **2.390× V8 time on Matrix** and
**1.397× on `bv2string`**. Overlapping ranges do not establish equivalence;
the bytevector median is slightly worse. `cold` is deliberately omitted:
it gives no clear additional Matrix gain and makes the bytevector median
**1.658% worse than baseline** in this comparison.

This followed an initial three-system experiment, preserved without alteration:
Matrix baseline/split-with-`cold`/V8 medians were
1.895684/1.677183/0.703594 s; bytevector medians were
0.901326/0.915844/0.649311 s. That first bytevector regression motivated the
attribute ablation. The first experiment had one discarded plus six retained
processes per system, covering all six orders. The second had one discarded
plus eight retained, covering four rotations and their reversals. Every system
appears twice in each retained position. **All 114 processes passed**; 100
samples were retained under those predeclared rules. No failed sample,
replacement, additional warmup or retrospective outlier exclusion occurred.

## What changed in machine code

The baseline `allocate_header` symbol is 1,785 bytes and remains an actual call
from `native_gc_alloc`. Both split variants inline the cursor check and bump
into `native_gc_alloc`, removing that call from the common path. The public
allocator itself still remains a call at constructor sites, and `memset@plt`
still clears the payload. In Matrix:

| Native variant | `native_gc_alloc` bytes | Out-of-line reservation bytes |
| --- | ---: | ---: |
| Baseline | 244 | 1,785 (`allocate_header`) |
| Split, `cold` | 323 | 1,140 (`allocate_slow`) |
| Split, no `cold` | 310 | 1,737 (`allocate_slow`) |

The annotation changes code layout and optimization as well as symbol size.
This experiment establishes its effect as compiled; it does not attribute the
bytevector difference to a particular instruction or solely to hole-search
execution. The build's expanded Clang invocation includes
`-fzero-call-used-regs=used-gpr` and frame pointers. Those toolchain choices are
held constant. Their isolated cost remains unmeasured.

The preceding [Matrix attribution report](../2026-10-14-strict-matrix-native-diagnostics/README.md)
motivated the experiment: 99.88% of allocation requests used an existing bump
range, while allocator/header/memset paths occupied about 51–57% of native
samples. Those sampled percentages do not predict the speedup of this split.

## Artifact and timing boundaries

The compiler/runtime base is `869c505`. Both workloads use existing complete
source and canonical inputs. This experiment changes the C allocator only;
it does not regenerate either Scheme workload with a different frontend.
Matrix retains its previously frozen production module. The bytevector module
includes the already measured scalar-visibility/readiness improvements.
Mandatory Binaryen optimization remains in both production paths.

| Workload | Common final Wasm SHA-256 |
| --- | --- |
| Matrix | `dfb9d40d9544334b3328aa041cbff50d30f40b28a65fc6bb690ea0e62f7e31cd` |
| `bv2string` | `03b6ed0da64be15486b095364da2dd9535a10f082277f0d92316b5e4f4cf22da` |

For each workload, all native variants use the same LLVM module, provider
object, entry program and Rust static archive. Matrix's baseline and first
candidate were built independently through `scripts/build-native`, with those
identities checked. The other bytevector variants reuse its recorded link
command with the allocator source and output changed. Original commands,
source variants, modules, native programs and disassembly are archived.

The timer covers the complete worker and its original result predicate.
Matrix checks all five ordered 6-by-5 matrices. The bytevector benchmark keeps
1,000 stress roundtrips, maximum size 1,000 and expected failure count zero.
Compilation, instantiation, input setup and `main` precede the workload clock;
JIT work during the worker remains included. Native and V8 result framing,
empty stderr, status zero, bounded completion and process-group cleanup are
checked for every clean sample. Native opacity providers are non-counting;
the V8 host omits `--validate`. Separate full-count validation enables the
host counters and checks all expected opacity calls.

Both windows pin every guest to CPU 5 on the Intel Core Ultra 7 270K Plus,
using Node 24.19.0 and LLVM/Clang 22.1.8. Other agents held builds, guests,
profiling and compression. Before/after policy snapshots record the active
Intel pstate driver, `powersave` governor, `performance` preference, turbo and
800–5500 MHz bounds. They do not establish fixed frequency. Each frozen plan
checks its binary, Wasm, input, host, supervisor, runner and tool identities
before every sample and at completion. The execution records preserve the
later coordinated release separately from each plan's preparation status.

## Correctness and preserved diagnostics

The initial split passed the full native suite: 252 recorded commands cover
actual native execution, linked Wasm controls, forced collection, roots,
callbacks, typed storage, traps, shared Rust services and artifact relocation.
After removing `cold`, 96 recorded commands repeat native scalar/control,
tail/root, array/storage/trap and collector checks. The selected variant also
passes both complete workloads, plus the standalone collector tests under
address and undefined-behavior sanitizers.

New cases cover exact bump exhaustion, aligned footprints below/equal/above
one block, a large allocation between small ones, and a failed two-block
request followed by successful small allocation. Existing tests retain hole
reuse, reference-only tracing, weak cleanup and payload zeroing after reuse.
They pass on the old allocator as well as both split variants. The initial
sanitizer attempt failed because LeakSanitizer cannot operate under this
environment's tracing; that failure is retained. Subsequent ASan/UBSan runs
disable leak detection only. `make check` passes.

Separate opt-in statistics runs confirm all integer collector counters match
baseline for each variant. Matrix has 224,085,259 allocations, 5,807,145,296
requested bytes and 950 collections; the bytevector control has 801,730
allocations, 512,661,128 requested bytes and 62 collections. These totals
include setup; their diagnostic clocks are not clean performance samples.

## Reproduction and remaining work

The four plans, execution records and complete campaigns retain every process
and predetermined exclusion. `manifest.json` describes the compressed source,
binary, build, test and measurement evidence. To verify it, or verify then
extract and execute all eight full-result controls in a new directory:

```sh
python3 benchmarks/results/2026-10-14-native-allocation-path/archive.py
python3 benchmarks/results/2026-10-14-native-allocation-path/archive.py --replay /tmp/allocation-replay
```

Replay requires the pinned external tools and shared libraries identified by
the artifacts. It is a correctness check, not another timing campaign. The
measured implementation is a draft; nothing has merged. Further candidates
include exposing the remaining allocator body to constructor optimization,
checking which root-publication operations survive LLVM, and separately
ablating toolchain flags. This report does not implement or claim gains from
those possibilities. It adds no new suite coverage or Chez/Rust timing.
