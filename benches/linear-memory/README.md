# Linear-memory benchmarks

## Last Mile ray intersections

Each timed call casts 50,000 rays against the same twelve footprints. The rays alternate between horizontal and sloping directions and include parallel misses. Both Snail builds call the shipping `trace-distance` from their selected version of `(snail shell game physics)`. The C version keeps twelve structs in an automatic array and its intersection interval in scalar locals. Every sample must return exactly `342894`.

| Implementation | Median for 50,000 rays |
| --- | ---: |
| WasmGC, original pair-returning slabs | 3.41 ms |
| WasmGC, one borrowed interval per ray | 2.07 ms |
| Linear memory, original pair-returning slabs | 36.53 ms |
| Linear memory, one borrowed interval per ray | 3.25 ms |
| C in Wasm32, automatic storage | 0.68 ms |

Measured on Node 26.8.1 on an Intel Core Ultra 7 270K Plus. The runner warms each module three times, rotates the order in one process and takes the median of eleven timed calls. Compilation, instantiation and host I/O are outside the timed interval. Binaryen 132 optimizes the Snail modules at `-O2`. Clang 23.1.3 optimizes C at `-O3`.

The scoped version removes the temporary pair allocations and the per-ray fold closure. On the same scoped source, WasmGC took about 64% of the linear backend's time. The C kernel took about one fifth of the scoped linear version's time. C also has contiguous wall data, different code generation and opportunities to specialize the twelve-wall traversal. This comparison measures their combined effect on this query. A whole game or the compiler can have a different allocation profile.

## Existing compiler and game workloads

The Siegework balance program exercises the economy and combat simulation through its existing expected-output checks, including a 3,000-tick defended position. Five alternating fresh-process runs follow one untimed pair. These timings include Node and Wasm startup.

| Workload | WasmGC | Linear memory |
| --- | ---: | ---: |
| Compile the balance program with the same compiler source | 0.320 s | 1.045 s |
| Execute the release balance program | 0.503 s | 2.647 s |

For the compiler comparison, the historical backend hosts today's compiler, and both compiler binaries must produce byte-identical linear-memory WAT. For the simulation, each backend builds the same application source and must print exactly `tests/siegework/balance.out`.

Separate diagnostic builds time the linear collector inside each program's entry and count its allocations. Each measurement snapshots the counters before formatting the report.

| Linear workload | Allocations | Allocated bytes | Collections | Total pause / elapsed | Longest pause |
| --- | ---: | ---: | ---: | ---: | ---: |
| Compiler | 11.46 million | 294 MB | 51 | 267 ms / 949 ms | 9.08 ms |
| Simulation | 78.92 million | 5.27 GB | 1,262 | 59 ms / 2,549 ms | 0.28 ms |

Removing the measured collection pauses while keeping everything else fixed would speed up these runs by at most 1.39× and 1.024× respectively. Explicit storage can also remove allocations, copies, pointer chasing and root handling. The ray comparison measures one such change.

For WasmGC, a separate Node trace recorded 52 ms of main-isolate pauses in a 314 ms compiler process and 39 ms in a 510 ms simulation process. The longest pauses were 6.55 ms and 3.57 ms. These traces include host startup and JS collections. They measure time stopped on the main thread and exclude concurrent GC work. Each maximum describes one run.

## Manager-owned working sets

The Last Mile rewrite packs four F64 coordinates per wall. The wall count, positions and key order come from runtime inputs. A dense scan visits the vector directly. An indexed scan visits every wall through a shuffled vector of nominal `WallId` records. The records are allocated during setup. A third Snail scan stores the same permutation as packed I64 slots. Clang stores its one-word `WallId` structs inline. Slots stay valid for the scene's lifetime in this experiment.

The Siegework rewrite gives an 80 × 80 map a reusable queue of cell indices and a distance buffer. Both Snail and C clear the distances and fill the queue on every search. The runner copies the actual game's walkability map to C before timing. It compares all 6,400 distances with the shipping breadth-first search from the hub, the farthest reachable cell and two corners, on each seed. The timed pair searches from the hub and the farthest cell.

| Work done per sample | Shipping Snail | Packed Snail | Checked C, Wasm | Unchecked C, Wasm |
| --- | ---: | ---: | ---: | ---: |
| 50,000 rays × 12 walls, dense | 3.45 ms | 3.41 ms | 0.473 ms | 0.470 ms |
| 50,000 rays × 12 walls, shuffled IDs | — | 3.69 ms | 0.591 ms | 0.528 ms |
| 12,500 rays × 96 walls, dense | 5.54 ms | 6.49 ms | 0.849 ms | 0.843 ms |
| 12,500 rays × 96 walls, shuffled IDs | — | 7.15 ms | 1.025 ms | 0.938 ms |
| Two Siegework fields, seed 1, 1,617 reachable cells | 1.63 ms | 0.083 ms | 0.0145 ms | 0.0145 ms |
| Two Siegework fields, seed 4, 4,903 reachable cells | 5.04 ms | 0.199 ms | 0.0431 ms | 0.0401 ms |

The shipping searches allocated 64,450 objects on seed 1 and 195,386 on seed 4 per pair. Every packed ray and queue kernel recorded zero managed allocations and collections after setup. The counters exposed a capturing named loop that made one closure per ray in the first rewrite. The measured version carries its state through direct recursive functions. Construction, resizing, slot reuse, teardown and full-game execution are outside these timings.

The native control compiles the same C source with Clang 23.1.3 at `-O3 -march=native` for x86-64 Arrow Lake. It checks the same ray sums and compares every distance with the shipping Snail search. The native driver uses the same core, rotation, warmup, sample counts and number of calls across the host boundary. It measures those calls through Python ctypes. The unchecked builds use ordinary C subscripts. Both Wasm builds also run inside the engine's linear-memory sandbox.

| Work done per sample | Checked C, native | Unchecked C, native |
| --- | ---: | ---: |
| 50,000 rays × 12 walls, dense | 0.518 ms | 0.514 ms |
| 50,000 rays × 12 walls, shuffled IDs | 1.162 ms | 0.567 ms |
| 12,500 rays × 96 walls, dense | 2.206 ms | 2.213 ms |
| 12,500 rays × 96 walls, shuffled IDs | 3.795 ms | 2.178 ms |
| Two Siegework fields, seed 1 | 0.0065 ms | 0.0062 ms |
| Two Siegework fields, seed 4 | 0.0263 ms | 0.0195 ms |

Clang proves the dense C scan stays inside the vector on both targets. The checked shuffled scan tests each fetched slot against the wall count. On x86-64 this also changes the generated arithmetic. The checked sloping loop contains a packed floating-point division. The unchecked build specializes the constant slope to multiplication. The keyed timing difference includes both effects.

## Where the CPU time goes

In release Wasm, `trace-dense` advances one wall with `return_call`. Each coordinate read calls a helper that checks the I64 subscript against the array length, narrows it, then checks it again in the physical indexing helper. Clang lowers the dense loop to direct loads at fixed offsets, advances a pointer and selects the ray direction outside the wall traversal. Its checked keyed loop retains a range test on the loaded wall ID.

The controls below change the emitted Snail program and run the same inputs. The index control compares the full unsigned I64 against the length once per access. The loop control branches back in the same Wasm function with the next iteration's evaluated arguments. The wall control checks the extent of four consecutive coordinates before loading them. The direction control splits the wall loop for the two ray directions used here. Each indexing implementation traps on invalid subscripts, including I64 values that would wrap on narrowing. All variants must reproduce both ray checksums, every tested distance field and the allocation counts for the packed paths.

| Code generation | 50,000 rays × 12 walls, dense | Two fields, seed 4 |
| --- | ---: | ---: |
| Released Snail | 3.41 ms | 0.199 ms |
| More aggressive Binaryen inlining and optimization alone | 1.34 ms | 0.105 ms |
| One checked index per scalar access alone | 1.57 ms | 0.106 ms |
| Wasm loops for direct self-tail calls alone | 1.12 ms | 0.165 ms |
| One checked index and Wasm loops | 0.93 ms | 0.094 ms |
| Also check four coordinates as one wall | 0.81 ms | — |
| Also specialize the loop by ray direction | 0.64 ms | — |
| Bounds-checked C | 0.47 ms | 0.043 ms |

These are benchmark controls. The release compiler still emits the first row. The effects overlap. For example, aggressive inlining on top of the checked index and Wasm loops took 1.50 ms for the dense scan. The final Snail module still contains a per-wall range test and a call to the slab helper. The remaining 0.17 ms has no individual attribution.

Measurements use Node 26.8.1 on one performance core of an Intel Core Ultra 7 270K Plus. The runner rotates implementations in one process, warms them for seven rounds, then reports the median of fifteen. Queue samples average eight pairs of searches. Results include the public Wasm call and exclude module loading, scene setup and heap profiling. Both languages target Wasm32. Clang 23.1.3 uses `-O3`, and Binaryen 132 applies `-O2` to both linked modules. [Medians, ranges and heap counters](manager-results.jsonl)

## Reproduce

From the migration checkout, use a second worktree at the last commit that supports both the earlier WasmGC backend and scoped references. The build script bootstraps each checkout, builds both versions of the physics library with each backend, compiles the C control, and runs the comparison. It needs the repository's development shell and a Clang with the Wasm32 target and `wasm-ld`. Set `WASM_CC` to an unwrapped Clang executable when using a host-only compiler wrapper.

```sh
git worktree add --detach /tmp/snail-ray-wasmgc c1ccf1f88
nix-shell --run 'sh benches/linear-memory/build /tmp/snail-ray-wasmgc /tmp/snail-rays'
```

To repeat only the timing, run `node benches/linear-memory/compare.mjs` with the resulting `.release.wasm` files and `c.wasm`. The modules stay in the supplied output directory.

Run the controlled compiler and game comparison with `nix-shell --run 'node benches/linear-memory/workloads.mjs /tmp/snail-ray-wasmgc /tmp/snail-rays'`.

The manager experiment uses the current checkout and a Wasm32-capable Clang. The first two commands build and run the source rewrites. The last two build the code-generation controls and compare them in one process. On Linux, `taskset -c 2` before `node` reproduces the CPU affinity used here on this machine.

```sh
nix-shell --run 'sh benches/linear-memory/build-managers /tmp/snail-managers'
node benches/linear-memory/managers.mjs /tmp/snail-managers
nix-shell --run 'node benches/linear-memory/ablate.mjs /tmp/snail-managers'
node benches/linear-memory/managers.mjs /tmp/snail-managers --controls
nix-shell --run 'python3 benches/linear-memory/native.py /tmp/snail-managers'
```

The older compiler, Siegework and schema-check timings are recorded in the [linear-memory experiment](https://github.com/tsnl/snail-scheme/pull/752). The [reference-counting study](https://github.com/tsnl/snail-scheme/issues/773) records the separate list microbenchmark and allocation counts.
