# Historical experiments

Current benchmark drivers are Scheme scripts; comparison programs and native
hosts are Rust crates built by Cargo. Start with [the current protocol](README.md).

Reports under `results/` and `sfir/evidence/` describe earlier compiler versions.
Their measurements, result predicates and raw data have not been rewritten for
the Rust migration. Old C and Python experiment drivers, and source archives
containing them, are retained in
[the last pre-migration tree](https://github.com/tsnl/snail-scheme/tree/16f4423c9f0f579d9cf154c171309755a3d7ae05).
[retired-sources.tsv](retired-sources.tsv) lists each removed path and its SHA-256.
Report links to those files point to that immutable revision.

To reproduce a historical experiment, create a separate checkout at that
revision and follow its report, including its recorded tool versions. A report's
old shell commands describe that checkout, not the current build interface.
Running the migrated harness creates a new experiment; it does not replace an
earlier sample or make an old timing claim about the new runtime.
