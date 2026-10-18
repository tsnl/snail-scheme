# Historical experiments

Current benchmark drivers are Scheme scripts. Independent Rust controls, Wasm
scalar providers and host tools are Rust crates built by Cargo. Start with
[the current protocol](README.md).

Reports under `results/` and `lofi/evidence/` describe earlier compiler versions.
Their measurements, result predicates and raw data have not been rewritten for
the Rust migration. Old C and Python experiment drivers, and source archives
containing them, are retained in
[the last pre-migration tree](https://github.com/tsnl/snail-scheme/tree/16f4423c9f0f579d9cf154c171309755a3d7ae05).
[retired-sources.tsv](retired-sources.tsv) lists each removed path and its SHA-256.
Report links to those files point to that immutable revision.

The LLVM backend, custom collector and Lofi/native route were retired in
[PR #341](https://github.com/tsnl/snail-scheme/pull/341). The
[last tree before that removal](https://github.com/tsnl/snail-scheme/tree/e528eb28f07650b8f61046572feb233fec9a9fe5)
contains the Rust native executor and its build scripts. Native parity fields,
collector observations, six-route schedules and source paths in frozen JSON,
logs, patches and source captures refer to their recorded compiler revisions.
They remain evidence; they are not supported current commands or APIs.

To reproduce a historical experiment, create a separate checkout at the revision
recorded in that report and follow its tool versions and resource requirements.
A report's old shell commands describe that checkout, not the current build
interface.
Running the migrated harness creates a new experiment; it does not replace an
earlier sample or make an old timing claim about the new runtime.
