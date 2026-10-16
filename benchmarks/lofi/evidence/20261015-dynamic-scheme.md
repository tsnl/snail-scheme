# Dynamic and Scheme canonical validation

The frozen runner at `7ab1af2a9ff313ebef8a9d7854c428fbe3384095`, using compiler
sources from `552545ae0d87a13a711cc4357f3d826795e10c12`, passes both complete
workloads. Their `main.sfir` bytes and literal widths are unchanged from the
landed base. The corpus now registers all 56 committed static sources; Compiler
remains pending in its separate worktree.

| Workload | Canonical count | SFIR Wasm | SFIR native | Original Chez | Adapted Chez | Rust Wasm | Rust native |
| --- | ---: | --- | --- | --- | --- | --- | --- |
| Dynamic | 500 | passed | passed | passed | passed | passed | passed |
| Scheme | 100,000 | passed | passed | passed | passed | passed | passed |

Each native build starts from the retained raw Wasm and proves its mandatory
optimization produces exactly the optimized guest bytes executed by V8.
Separate Rust scalar providers supply target services. Preparation and final
integrity verification pass. The [complete evidence](20261015-dynamic-scheme.json)
retains the frozen manifest, 48 command records, stdout/stderr, failures, input
and artifact hashes, native parity records and focused clarity review.

Dynamic checks its complete counter datum. Wasm observes one whole pinned file
per iteration: 500 opens, 41,936,000 bytes, 500 EOF reads, no worker closes and
500 cleanup closes. Native checks the full result, 500 barriers, and typed port
release counts of setup 1, worker 0 and cleanup 500. The source intentionally
leaves its worker ports open. Rust Dynamic buffers and closes each file during
parsing, which is a visible representation and lifecycle difference.

Scheme checks all 30 sorted strings on every route. Its 26 supported probes
also pass both SFIR targets and the original-Chez oracle. Wasm verifies the
configuration and probe file each open and close once, followed by no worker or
cleanup file activity. Native observes setup/probe/worker/cleanup port release
counts of 1/1/0/0. The interpreter is ordinary compiled benchmark code; the
product compiler accepts SFIR. External reader-label examples remain explicitly
unsupported in the existing case documentation.

The recorded checks also pass 17 runner tests, both JavaScript syntax checks,
strict C syntax checks and deliberate Dynamic input-digest rejection. The first
C preflight's ambient Nix linker-flag warning is retained separately. The shared
Rust CSV banner says `rust-wasm` on native too; recorded commands and artifact
digests identify the actual routes.

These concurrent, instrumented correctness runs establish no clean timing
results. Both workloads remain `not-measured`. The retained frozen directory is
`/tmp/snail-sfir-dynamic-scheme-validation-20261015`.
