# Draft WasmGC String blocks

This candidate changes only the strict compiler's physical String storage. Each
String has an immutable owner containing writability, unsigned scalar length,
one direct i32 scalar array and an optional directory of remaining scalar
arrays. Every scalar array holds at most 8,192 Unicode scalars (32 KiB of
payload). Short and empty strings omit the directory. The Wasm engine owns all
storage and collection; no native runtime or linear-memory ownership is added.

The size is an experimental general storage parameter, not a claimed engine
allocation threshold. Bounding individual scalar arrays may reduce repeated
large-object page churn. The parent performs clean comparative measurements;
preparation and linked contract execution establish correctness only.

The owner publishes after all blocks are initialized. Its references and the
constructor's backing locals are engine-traced roots during later allocations.
Each mutable result owns independent blocks, including empty strings. Equal
readonly literals may share an owner. Public String/Char signatures, scalar
conversions, literal writability and explicit Top witnesses remain intact.

Copy checks permission and both complete I64 ranges before its first write.
Forward spans stop at both physical block edges. Same-owner copies to a later
destination run backward from exclusive range ends. Native array.copy handles
overlap within each span; the traversal direction protects the remaining source
across spans. Validated logical ranges also bound a short final block.

The candidate preserves the canonical String source, original full inputs
(`100`, `500000`, `524278`), ten trials per iteration, four fresh logical buffers
per growth step, both growth stores, and all append/substring copies. Additional
Unicode, alias and trap observers exist only in separate contract/probe modules.
The frontend, typeclass model, vector representation and benchmark adapter are
unchanged. Source and artifact comparison belongs in the frozen preparation.

Small strings now require two GC objects instead of one. Long strings add a
directory and more individual objects, span-copy calls and directory lookups.
The directory itself is not bounded to 32 KiB; its size grows with the number of
blocks. Engine resource limits can still reject otherwise valid large lengths.
Neither lower page-fault counts nor faster execution follows from the layout
alone.

The [focused explanation and debate](simplify-review.md) records the required
independent review and the implementation comparison. Checks include `make
test`, `make check`, and fifteen focused strict contracts, executed in raw and
optimized Wasm on actual Node. Three new fixtures cover full Unicode scalar
contents, independent copies and aliases, both overlap directions across block
boundaries, exact block sizes, partial final blocks, empty operations, readonly
literal blocks, and range failures that must precede every destination write.

Frozen baseline and candidate artifacts are prepared separately under
`/tmp/snail-gc-string-block-preparation-20261014`. That local handoff is not a
published benchmark result. Full-source adaptation and complete-value probes
come from the established strict String preparation.
