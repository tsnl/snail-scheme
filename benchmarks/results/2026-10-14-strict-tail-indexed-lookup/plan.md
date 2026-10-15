# Bounded provider lookup experiment

This separate task starts from first-pass evidence commit
`0038492d894cf18dd833e7ba4a532555e58887e5`. It changes diagnostic source copies
only. Production `src/strict_io.rs`, Scheme libraries, compiler, workload and
historical artifacts remain unchanged. No clean timing is authorized yet.

Prepare both providers from the original Tail preparation's 76-file frozen
source closure and hash-verified Rust 1.95 toolchain/target libraries. Common
`cfg(test)` checks supplement existing ID/codec/cleanup tests. Compile each
source snapshot through the same concrete build path, with separate target
directories, the same offline locked release command, LTO/codegen settings,
and cleared build overrides. The only runtime source difference is
`src/strict_io.rs`'s resource container, publication/lookup/removal and iteration.

The baseline retains `BTreeMap<u32, Port>`. The diagnostic candidate uses
`Vec<Option<Port>>` at unchanged monotonically reserved IDs. Publication grows
with `None` slots while the opened Port is still locally owned; taking removes
the Port permanently, and cleanup flattens the taken Vec in ascending ID order.
RefCell boundaries, pathname transfer, error text/precedence, scalar ABI,
UTF-8 codec, buffering, explicit flush/drop and cleanup order remain unchanged.
Holes consume space proportional to historical successful/failed opens and
make this representation unsuitable as an unrestricted production replacement.
ID reservation/exhaustion arithmetic is tested separately from impractical
publication near `I32_MAX`.

Both fully linked artifacts use the **identical** pre-link Scheme program
`097a7eab1e03b7a8905d6487bb622d70aa2e55a7e5da89ae1fa5e827e89b6594`
and frozen linker script/adapter/Binaryen 132 pipeline. Mandatory final `-O3`
with closed-world/inlining/convergence remains in force. Provider differences
can change optimization of the complete linked module: the experiment measures
the full workload effect of this source change, rather than a universal isolated
lookup cost. Report whether the rebuilt baseline reproduces the historical
optimized artifact; never substitute the earlier 4.899608 s median for new
matched baseline samples.

Focused checks use both source configurations. Private Result-returning helpers
test successful IDs, failed input/output opens consuming IDs, a later successful
open through holes, stale rejection and unchanged exhaustion arithmetic. They
do not resume a fatal public invocation. Fresh actual optimized Rust/WASI
instances test Unicode/EOF/peek, successful IDs, stale/negative/unknown IDs,
ordered cleanup through a closed-ID hole, returned WASI EIO with later closes,
and a primary scalar error surviving an additional cleanup EIO. Diagnostics
must occur after every owned descriptor is dropped. Arbitrary host traps remain
outside the completion guarantee; instances are terminal after fatal errors.

Each actual linked Tail artifact runs the full count 50, unchanged 4,460,056-byte
bibliography and reversed-byte oracle. The workload repeatedly opens the same
unchanged input and writes the same reversed oracle; it does not reverse its
previous output. A common diagnostic-only observer checks all actual output
bytes after **each** successful output close, plus complete final files,
100 opens/closes, 49 deletions, all transfer bytes and original release order.
Those extra host reads/hashes are absent from future measurement hosts.

Raw started attempts, commands, stdout/stderr, sources, changes/erasure ledgers,
toolchain identities, probe events and actual full-count files are retained.
Every future command owns a new process group; timeout/failure cleanup kills
the group and records whether any executing descendants remain. The first
preparation attempt is preserved separately: its raw runtime retained unused
legacy ABI imports that the original probe harness rejected before instance
creation. Corrected probes provide explicit stubs that throw if ever called;
successful scalar checks therefore cannot silently use the legacy value ABI.
After preparation, send exact artifacts/commands to the parent for review and
coordinate quiet timing separately. Proposed bounded timing: one excluded pair
followed by four balanced retained AB/BA cycles on CPU 5, fresh process/cwd each,
original count/input, default Node tiering and cleared Node injections, exact
JSON result and full final file checks after every sample, raw failures retained
without replacements. No measurements start until the parent grants that window.
