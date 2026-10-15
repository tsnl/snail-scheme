# Paired Cat/WC input packets, 15 October 2026

Owned-file input packets reduced median workload time for canonical Cat and WC
on both V8 and native execution in this paired campaign. All eight routes passed
one warmup and five samples: 48 fresh processes, with no retries or failed attempts.
The original source, count 50, input and complete predicates were preserved.

Median guest workload seconds; ratio is scalar median divided by packet median:

| Workload | Target | Scalar input | Packet input | Ratio |
| --- | --- | ---: | ---: | ---: |
| Cat | V8 | 4.238893988 | 2.845080934 | 1.490× |
| Cat | Native | 3.473143160 | 2.304108797 | 1.507× |
| WC | V8 | 3.320282968 | 1.435619571 | 2.313× |
| WC | Native | 3.004847566 | 1.671740652 | 1.797× |

The [JSON summary](20261015-input-packets.json) retains every sample, exact ratios,
source/tool identities and verification scope. The
[indexed archive](20261015-input-packets-records.tar.gz) retains all 48 original
process records, raw stdout/stderr and per-attempt result records, plus the sealed
driver, plan, preparation manifest, machine context and native build metadata.
These results cover SFIR Cat/WC input buffering. They establish no Chez/Rust
comparison or full57 result, and are separate from historical buffer experiments.

## Frozen protocol and complete work

The scalar baseline is `6f32b9cf303569f2578f6c16b9394bba14b8c3cb`; the measured
packet candidate is `c0b6f16299c5568e4f906f18af330df43aa7df25`. Both use the same
Cat/WC source hashes, canonical count 50 and 4,460,056-byte `bib` input. WC keeps
its complete `(31102 851820 4460056)` datum predicate inside the workload. After
every Cat warmup and sample, all output bytes were checked against the input's
SHA-256 `2994b446dfb07d7cf324fb6aa32d519b3f0bd53a582268714adf08df5f45b8d3`.

Each attempt uses a fresh process and working directory on CPU 2. Each round
rotates the four case/target pairs, and each pair alternates which variant runs
first. Round zero is warmup; rounds one through five supply samples. The order
was fixed before measurement and never adapted to observed times. The original
version-one plan was superseded before execution because it did not alternate
each pair's first variant; these samples use only the sealed version-two plan.

The unchanged guest clock encloses the 50 repeated workers and complete final
predicate, including workload file reads and writes. Process startup, parameter
loading/setup, result formatting, final resource cleanup and Cat's additional
output hash are outside it. A fresh-process warmup warms shared machine state;
it preserves no V8 JIT state for later processes. Validation and process wall
clocks remain diagnostic records and supply no samples in this report.

Measurement ran from 18:50:00 to 18:52:18 UTC. The retained attestation confirms
that coordinated builds, tests and archiving had stopped. Ordinary desktop
applications remained active. The machine was an Intel Core Ultra 7 270K Plus,
using `intel_pstate` with the recorded `powersave` governor. The archive retains
full machine context before and after the run. This is one controlled paired
campaign on that desktop, without a broader uncertainty estimate.

Node 24.19.0 uses V8 13.6.233.17-node.51; mandatory optimization used Binaryen 132.
Within each variant/case pair, native lowering consumed optimized guest bytes
identical to V8's module. Target runtime providers remain separate. The four
optimized guest hashes are recorded independently; scalar and packet variants
are intentionally different implementations.

## Integrity and the current rebased candidate

Before and after measurement, the frozen driver verified 7,577 source, input,
toolchain, shared-library, execution-helper and artifact identities. Both checks
passed. The sealed plan, driver and preparation manifest SHA-256 values are:

```text
plan:     7be6bf3b3b4217d20ebba617299d4b507c93193add8cecd87fa30e155030c9c6
driver:   8209b62baa891b5cd4918e840cc64984e66877cc00229811370051c3de5ddb52
manifest: dc53cf4ff7eb1163653592cdf13e72b199078d39eed28b80e1b495e372542dbc
```

Report preparation independently checked raw stream hashes, terminal exit and
descendant status, the complete schedule, positive finite guest results, all 24
Cat output hashes and 96 copied inputs. It rehashed 1,091 frozen source files and
the four native/V8 optimized guest pairs, then recomputed all medians and ratios
from raw stdout. These agree exactly with the terminal measurement JSON, whose
SHA-256 is `f63c20f9ae6bdefaba047abccc4f08f5ffec78dff5d42104d6ed909c620bc13a`.
No workloads or builds were repeated, and the full toolchain verification was
retained from the completed campaign rather than repeated for this report.

A separate retained rebuild at `f432b0a836a230c73d9a39a5ffe52a47099951fd`
reproduced the candidate's raw and optimized Cat/WC guests exactly after rebasing
onto `e90e8fe9`. Its report SHA-256 is
`f7d98991f318ca16603cc95c46a67958609f30d522f998df086dfd5b85b0cb3e`.
The subsequent `f432b0a8` → `6bfbb6eb` step changed three README files; the
`6bfbb6eb` → current `d153adf6` step changed only Mperm timer metadata and its
Python regression. Exact commits and changed paths are archived. Equality for
the current candidate follows that rebuild proof and those source-preserving
steps; this report does not claim a fresh rebuild or measurement of `d153adf6`.

The archive's `index.json` records byte lengths and SHA-256 for every other
member. The summary records its outer archive and index hashes. Binaries, LLVM
IR, sysroot/vendor copies and repeated output trees are omitted; their recorded
identities remain in the original manifest, plan, parity and build records.
Preparation-time status words in those original files remain unchanged; terminal
`measurement-v2/measurement.json` supplies the measurement outcome. The frozen
campaign remains at `/tmp/sfir-input-buffer-comparison-20261015-v1`.
