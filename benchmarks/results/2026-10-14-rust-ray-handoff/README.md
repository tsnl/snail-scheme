# Corrected canonical Rust Ray handoff

This handoff retains the original 50 complete renders, resolution 1, pathname
`outputs/ray.output` and expected symbol `ok`. Each invocation reconstructs all
33 spheres, visits all 10,000 pixels and formats the complete ASCII PGM. The
rendering source region remains byte-identical to the historical reference;
the [source audit](source-review.md) explains traversal, arithmetic, ownership
and file lifetime differences. No clean timing campaign is included.

Source correction `296f7ef79829f47d3c0a4c92053d49f2f03a26e2` fixes two driver
defects: expected string `"ok"` no longer equals symbol `ok`, and zero/negative
counts retain the original harness's initial false without touching the file.
Signed i64 count labels remain exact. Shared reporting now accepts a Display
count; existing usize callers retain their behavior. The predicate still runs
before stopped-clock capture. Failed predicates do not capture that clock or
print normal CSV; Rust panics while original Chez prints `INCORRECT`.

The corrected artifact is
`e66e1b8a221250c113073e9336b5247722de7484464c77963ce9d6d3b61bb081`
(131,282 bytes), built from the exact corrected source snapshot with Rust 1.95,
LLVM 22.1.2, offline release opt-level 3, LTO, one codegen unit and panic-abort.
[Build provenance](build-provenance.json) retains actual verbose rustc commands,
selected build environment, tool identities and the build log. The current
expanded reader/library snapshot is explicit. Full inherited environment and
external sysroot/dependency binaries are not vendored.

Historical artifact
`cc4855cd2bb13b58a38bbcf9eea542b632304d43fc411632b875a430c067950c`
(130,490 bytes), its 44-file source snapshot, input, original validation and
disassembly remain unchanged under `historical/`. The historical full-count
success remains correctness evidence for that old artifact. This correction
does not overwrite it or reinterpret its CSV durations as clean samples.

[handoff.json](handoff.json) gives the immutable artifact/host/source/input hashes,
exact command/cwd/stdin and complete validation contract. Use a fresh case
directory containing `outputs/`, with the destination initially absent. The
original input file remains byte-exact at count 50. Startup, compilation,
initialization and input decoding are untimed. All scene reconstruction,
geometry, raster/decimal formatting, per-invocation delete/create/write/flush/
close, owned scene cleanup and final supplied-result equality are timed.
Result/CSV printing and complete-image validation follow clock capture.

Complete canonical PGM is 29,517 bytes with SHA256
`38babccc4583f44c18d17488314bffe9723a0fd2bdeff7227ec0d7ed1ea1463d`.
All 10,000 pixel values produce byte checksum
`2504547e212cb609b776f06ac18c74915dac54a988e42f9584d0509c03f044eb`.
These untimed complete checks supplement the original timed symbol predicate.
No image audit or extra opacity boundary was inserted in its timed loop.

Rust uses contiguous owned spheres and inline F64 points/options instead of
Scheme vectors/world cons cells or strict products/option/Hit wrappers/Ref world.
It frees the scene inside each invocation; original Scheme retains the world
until the next reset, including the final world after timing. The 8192-byte
BufWriter and native Scheme/strict file adapters have different buffering and
allocation policies. Explicit flush and implicit drop close the Rust file;
drop does not propagate close errors. Physical allocation/lifetime parity and
general exceptional IO equivalence are not claimed.

The [retained-work audit](retained-work.json) identifies the exact release Wasm
scene/grid/reverse, raster/sphere, square-root, formatting, lifecycle and predicate
sites. LLVM hoists ray-invariant a/4a/2a terms within a pixel; no artificial
barriers counteract it. The original two input black_box boundaries remain.
This evidence does not count V8 physical allocations or machine instructions.

[Supplemental checks](supplemental-correctness.json) preserve 32 actual corrected
Wasm/original-Chez executions, including full 50, complete resolutions 0/1/2,
existing/Unicode paths, symbol/string/list negatives, nonpositive false results
and exact signed labels. All output bytes agree. The existing suite runner
also passes 16 executions of the four committed regression fixtures, recorded
in [fixture-correctness.json](fixture-correctness.json).

[Filesystem evidence](filesystem-correctness.json) reconstructs every successful
write payload between file open and close. Full 50 with initially absent output
has 50 opens, 49 unlinks, 50 closes, 200 writes and 1,475,850 bytes. Count 2 with a preexisting
sentinel has 2 opens, 2 unlinks, 2 closes and 59,034 bytes. Every one of these 52 separately
closed files matches the full canonical PGM. Raw strace records, including joined
unfinished/resumed calls, are archived; the initial unavailable sandbox ptrace
attempt remains separately recorded. Diagnostic durations are not performance
observations. [Parent check](parent-canonical-check.json) independently repeats
the corrected full 50 and validates the complete image.

Eight native tests, fmt, Wasm Clippy and `make check` pass. A fresh no-history/
no-files Sol 6.1 max explanation and one informed critique accept the direct
result state and visible timer driver; [independent-review.json](independent-review.json)
records that bounded review. No renderer refactor was warranted. The shared
reader remains bounded: canonical false spelling `#f` is supported, while alternate
boolean/numeric spellings and escaped boolean-like symbols are outside its
equivalence. Counts fit i64; nonnegative extents/storage fit Wasm32; the checked
scene is finite. Other full-suite structural/SLaTeX reviews remain pending.

`artifacts.tar.xz` and [manifest.json](manifest.json) preserve corrected and
historical source, programs, host/input, complete images, raw observations,
per-file syscall payloads, source patch and tool/build/review provenance.
Restore each `files[path]` from `blobs/SHA` beneath a scratch directory and verify
all SHA256s. [archive-verification.json](archive-verification.json) records complete
restoration; [replay-check.json](replay-check.json) records separate relocated
count-one Rust/original-Chez executions, complete images and unchanged hashes.
Those probes are not retained clean samples. Parent controls any later clean
comparison, using the unshortened original input and frozen handoff.

The live checkpoint selects this corrected Ray artifact while retaining its
historical record. All 57 source implementations, 56 default canonical passes,
default Ackermann stack failure and separate heap-frame variant remain distinct.
The existing historical full-suite archive is unchanged.
