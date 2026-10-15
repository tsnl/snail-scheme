# Current optimized Wasm on archived LLVM and Immix

This preparation establishes a valid comparison; the instrumented validation
times in this directory are not performance results. Clean measurements belong
to the coordinated CPU 5 window described in `handoff.json`.

Both executors consume identical optimized Wasm bytes. The native path starts
at archive `5c277ab`, recovers the nonmoving Immix collector from `7f69868`,
and lowers Binaryen 132's disassembly through the archive's existing emitter.
It keeps exact explicit root frames, proper tail calls, bounds checks, ordinary
collection, zeroing, and the archived eight-byte array slots. The native host
is a separately compiled non-LTO object, preserving opaque runtime imports
while the guest and collector use Clang/LLD 21.1.8 with `-O3 -flto`.

| Workload | Original count | Native capacity | Full-input correctness |
| --- | ---: | ---: | --- |
| String | 100 | 300 MiB | Predicate 1; 2,001 workload collections |
| mbrotZ | 1,000 | 300 MiB | Result 5; 662 workload collections |
| quicksort | 2,500 | 300 MiB | Predicate 1; 23 workload collections |
| mperm | 20 | 300 MiB | Arena exhausted during setup; failure retained |
| mperm, capacity variant | 20 | 1 GiB | Predicate 1; 20 workload collections |
| deriv | 10,000,000 | — | Unsupported nonfinal struct subtyping |

The successful mperm capacity variant retains its original n=10, k=2, ell=1
inputs. Its diagnostic peak live payload was 614,393,720 bytes. It changes only
the arena size; the initial allocation budget remains 8 MiB and subsequent
budgets remain `max(8 MiB, 2 * live payload)`. All arenas are prefaulted before
module initialization and the workload timer. Native setup time is reported
separately. No never-collecting control is substituted for Immix.

`artifacts.tar.xz` retains frozen Wasm, disassembly, runtime specifications and
input files, emitted LLVM, native binaries, build commands, tool/source hashes,
the new harness, and collector/emitter source. It also retains the unsupported
deriv build, earlier host binaries used for full diagnostic validation, and
bounded stress results. `archive.json` identifies the archive. The full source
experiment lives on `experiment/current-wasm-llvm-20261014`, separate from the
current compiler stack; only evidence should be copied into that stack.

`final-harness-validation.json` records collection before every allocation in
bounded native probes and verifies that disabled counters report `null`.
`node-smoke-validation.json` runs the same byte-identical bounded Wasm on
Node 24.19. `checks.json` and the retained logs cover native callbacks, roots,
finalizers, tail transfers, traps, Scheme tests, formatting, strict C, and
ASan/UBSan allocation-hole checks. Full original inputs were checked before
the host-only readability refactor; the final clean runs must also check every
full-input result.

Later LLVM stack-map/bitmap-sweep experiments are separately retained at
`experiment/shared-binaryen-20261011` / `e3e66bc6a45263928cfd1e7a31659d00e6a47ca7`.
They are not the root protocol measured by this explicit-frame baseline.
