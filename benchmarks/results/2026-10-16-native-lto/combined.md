# Final runtime patch and CPU-tuning comparison

The combined runtime patch reduces ordinary native `array1` time by **9.6%**
and `gcbench` time by **9.2%**. It only skips redundant all-zero array filling
and individual object sweeping in wholly dead GC blocks. This comparison uses
the frozen machine-code guests and original Rust entry/provider/configuration,
with ordinary static runtime linkage. It does not enable shared guest/Rust LTO.

| Workload | Baseline median | Combined median | Baseline range | Combined range |
| --- | ---: | ---: | ---: | ---: |
| array1 | 3.284679 s | 2.969336 s | 3.251146–3.360422 s | 2.956792–2.974652 s |
| gcbench | 3.980095 s | 3.615305 s | 3.971716–3.982478 s | 3.612590–3.649306 s |

The baseline is `313cec8752b1fcd3b7a2577f3fc65b96ea1b9dd3`; the combined
runtime source is `08f98ad1db244753c48a1739702ca894e50416da`. Each guest ELF
object, Rust entry, provider and case configuration is byte-identical before
and after linking the candidate. Inputs, repetition counts and complete
predicates are unchanged. [runtime.patch](runtime.patch) retains the candidate
against that baseline; apply with `git apply --unidiff-zero`.

Review checked allocator zeroing on fresh and reused storage, negative-zero
and NaN bit patterns, exact-start membership before header reads, complete
large-allocation line coverage, and finalizer ordering. The focused regression
republishes a reclaimed exact address before reuse and verifies it cannot revive
the old object. Cargo's 58 tests, formatting, actual native execution including
forced collection and traps, and a copied standalone package's native and V8
execution checks pass. The native suite records 253 checked commands, including
expected traps and failures.

## CPU tuning is a separate experiment

The same schedule includes a matched shared-LTO Mandelbrot pair:

| Target CPU | Median | Range |
| --- | ---: | ---: |
| Generic x86-64 | 0.479142 s | 0.478520–0.481045 s |
| This host (`arrowlake-s`) | 0.311863 s | 0.310451–0.313178 s |

Host tuning reduces time by **34.9%**. Actual linked guest and Rust runtime
functions carry the intended CPU attributes in both binaries. Both disable
FMA, retain separate Wasm rounding, and have no fast-math or contraction flags.
Guest instructions before optimization differ only in CPU attributes. The
opaque benchmark boundary, inputs, counts and predicate are identical.

The host hot loop uses AVX three-operand instructions with VEX-encoded 128-bit
registers and unrolls two iterations. The generic loop uses SSE2 packed
operations with extra moves and unpacking. Neither hot loop uses FMA or AVX-512.
The optimized V8 code also uses three-operand AVX scalar operations. This is
evidence for the entire host-tuning change, not an isolated attribution to AVX:
instruction selection, unrolling and other target decisions change together.
The full recurrence and opaque outer work loop survive in both native binaries.

The preceding campaign measured V8 at 0.288790 seconds, placing the tuned
native result about 8% behind that earlier result. V8 was not rerun in this
short final schedule. This CPU experiment uses LTO and an explicit host target;
it does not change the portable native default or resolve the separate LTO
array regression. No CPU-tuning product change is included in the runtime patch.

## Protocol and retained failures

All **36 executions passed** in the successful campaign: six arms, each with
one warmup and five measured fresh processes, on CPU 2 with rotated cases and
arms. Samples use the unchanged canonical freeze, complete output predicates,
and the same timer boundaries as the [earlier report](README.md). Source and
executable hashes were verified before and after. No failed sample was replaced.

The first scheduled campaign failed all 36 attempts before any workload could
start: the parent launcher omitted `SNAIL_NATIVE_SUPERVISOR`. The target's
frozen environment did contain the setting, but the capture routine needs it
in its own parent environment. All failed records are retained under
`failed-launch/`; they have no timing values. Setting that parent variable to
the already-frozen supervisor and rerunning the whole unchanged schedule in a
fresh directory produced the successful campaign. No source or executable was
changed to resolve the launcher error.

All task-owned heavy workers remained held continuously through both attempts.
The LTO backend coordinator was stopped; its completed supervisor was a zombie
with no executing descendants. It resumed and reaped the supervisor after the
successful schedule and final integrity checks. Host snapshots retain process
states and executable names without unrelated command arguments. Ambient
desktop processes remain; this is not a machine-wide exclusivity claim.

[combined.json](combined.json) contains every successful attempt, sample, range
and median. [combined-evidence.tar.gz](combined-evidence.tar.gz) retains both
campaigns' plans and records, runtime link provenance, CPU build commands and
flags, full selected guest functions and assembly, diagnostic counters and
failed diagnostic attempts. `evidence-files.sha256` verifies the archive's
retained files; binaries, Cargo targets and full toolchains are excluded but
identified by hashes. The archived helper documents the selection.
[COMBINED-SHA256SUMS](COMBINED-SHA256SUMS) covers this report and evidence.
