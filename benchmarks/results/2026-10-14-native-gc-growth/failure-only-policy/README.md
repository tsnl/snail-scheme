# Preserved first growth policy

This source snapshot grows only after collection leaves no fitting hole. It
passes the complete original NBoyer and SBoyer inputs without heap overrides,
plus small, repeated, wrong-result and zero-repetition fixtures for each. The
separate statistics invocations expose excessive collection work near capacity:

| Default heap observation | NBoyer | SBoyer |
| --- | ---: | ---: |
| Initial managed capacity | 256 MiB | 256 MiB |
| Final managed capacity | 2 GiB | 1 GiB |
| Added regions | 3 | 2 |
| Collections | 134 | 91 |
| Traced reference fields | 3,198,949,356 | 815,738,759 |
| Object allocations | 359,440,532 | 59,001,388 |
| Allocated payload bytes | 8,692,156,392 | 1,481,616,992 |

The counts motivate testing a policy that leaves allocation headroom after a
capacity-triggered collection. They do not establish an optimal occupancy
threshold. Process durations and collection-phase times are retained as
diagnostics; builds and checks overlapped, so these are not clean comparative
timings.

`validation.json` retains commands, inputs, outputs, status, timeout state,
source/tool/module/executable identities and all GC controls. The relink reuses
the original mechanically lowered LLVM, Binaryen-optimized Wasm identity, scalar
provider, C entry and Rust library. Its changed collector is preserved here as
`precise-gc.c`; the executable files remain in `build/gc-growth/boyer/` in the
task worktree. The earlier immutable Boyer preparation artifacts are unchanged.

The native integration check, Scheme tests and formatting checks passed with
this version. The five focused growth modes also passed AddressSanitizer and
UndefinedBehaviorSanitizer. LeakSanitizer could not run under the sandbox's
ptrace environment, so those successful sanitizer runs explicitly disable its
leak scanner; they make no leak-detection claim.
