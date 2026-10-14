# Unicode String block-storage comparison

The original String workload runs **5.04× faster** with bounded WasmGC backing arrays.
The source program, Unicode element width, full input, repetition count and final
predicate are identical. Only strict-wasm.sld differs between the frozen compilers.

| Variant | Median seconds | Range |
| --- | ---: | ---: |
| Strict WasmGC, original flat i32 array | 4.952576 | 4.771381–5.028329 |
| Strict WasmGC, bounded i32 blocks | 0.982650 | 0.981163–0.990281 |
| Original Chez | 1.778489 | 0.948811–2.239374 |
| Original idiomatic Rust/Wasm | 0.057725 | 0.056752–0.058050 |
| Rust/Wasm u32, four fresh zeroed buffers | 0.465704 | 0.461972–0.495360 |

One discarded round precedes five retained fresh-process cyclic rotations:
30 checked executions, with each variant in each ordinal position once.
All 651 frozen source/artifact/tool identities remain unchanged. Node 24.19 uses
default V8 tiering; NODE_OPTIONS and native collector overrides are cleared.
Processes are pinned to CPU 5 in a coordinated window with all agent-controlled
builds, tests, profiles and compression held. Unrelated activity remains possible.

The candidate takes 2.11× the Rust u32/zeroed control time and 17.02× the
idiomatic Rust reference time. Its median is 0.553× original Chez time, but
Chez varies substantially: 0.949–2.239 seconds, including one result faster than
the candidate. Preserve that range rather than treating the median ratio as a
stable universal advantage. These Rust references retain their previously
[documented ownership/copying differences](../2026-10-14-string-storage/README.md).

## Representation and preserved work

The implementation is `d4116215645af699ae0e41008759d92db812de60`. An immutable
String owner contains permission, scalar length, its first character array, and
an optional directory of remaining arrays. Each i32 character array has at most
8,192 elements (32 KiB of payload); short and empty strings omit the directory.
Every mutable String owns its storage. Literal constants remain readonly.
No character narrowing, substring views, shared mutable backing, or native
ownership runtime is introduced.

Copying checks permission and both complete I64 ranges before writing. It then
uses bounded native array.copy spans, backwards for rightward self-copy and
forwards otherwise. Rooted locals keep incomplete constructors alive; directory
entries are filled before publishing the owner. This adds an owner allocation to
short strings and adds directory/object/span traversal for larger strings.
Only the full String growth workload is measured here; short-string performance
remains an explicit follow-up before judging the general tradeoff.

The canonical source retains 100 invocations, ten trials each, threshold 500,000
and final length 524,278. Separate static inspection of the exact optimized Wasm
retains both replacements, two append calls and two fresh substring calls per
growth step, owner/block construction and native copy loops. This inspection is
not a physical allocation count or an instrumented execution trace.

Fifteen focused contracts pass in raw and optimized actual Node execution,
including Unicode, readonly and empty copies, full pre-write range rejection,
both self-overlap directions, exact block ends, short final blocks, alias/copy
independence, first-class primitives and Top witnesses. The frozen full-source
preparation also passes original counts 1/2/100, complete-value and mutation
probes against original/adapted Chez, and wrong-result boundaries. make test and
make check pass. The [focused explanation and debate](../2026-10-14-wasmgc-string-blocks/simplify-review.md)
and the parent's source inspection are separate from these execution checks.

## Separate resource observations

After the clean comparison, four additional full-count runs use an unchanged
resource host in baseline/candidate/candidate/baseline order. It samples process
resource usage immediately around bench, before the final host assertion. The
Scheme predicate stays inside bench. No CPU profiler or Wasm counter is enabled;
these diagnostic observations are excluded from the clean timing table.

| Resource during bench | Flat storage | Bounded blocks |
| --- | ---: | ---: |
| Minor page faults | 2,896,003–2,896,080 | 31,412–31,416 |
| System CPU seconds | 3.800–3.875 | 0.032–0.037 |
| User CPU seconds | 0.857–0.872 | 0.940–0.946 |
| Major page faults | 0 | 0 |

The large reduction is in system CPU and minor faults; user CPU rises slightly.
That supports the earlier allocation/page-churn diagnosis and explains most of
the observed elapsed-time saving. The experiment changes allocation shape and
copy traversal together; it does not separately measure every V8 allocator/GC
phase or establish equal resident-memory policies across implementations.

## Artifacts and replay

`clean.json` preserves all samples, commands, environments, stdin and unchanged
identities. Workload timers include the complete repetitions and final predicate;
compilation, instantiation/input parsing and result formatting are excluded.
The GC host includes its final acceptance assertion. Rust uses the documented
Instant/report boundary. Process elapsed times remain separate in the raw file.

`artifacts.tar.xz` and `manifest.json` preserve the baseline/candidate preparations,
exact compiler sources, canonical and probe Wasm, complete checks, Rust sources
and references, resource host/records and measurement scripts with original path
mappings. External Nix binaries are identified by path/hash instead of copied.
Relocated count-one probes verify the archive's executables and results separately
from timing; all original non-count inputs and predicates are retained. A new
clean comparison requires remapping paths and freezing a new observation set.
