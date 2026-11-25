# Last Mile ray intersections

Each timed call casts 50,000 rays against the same twelve footprints. The rays alternate between horizontal and sloping directions and include parallel misses. Both Snail builds call the shipping `trace-distance` from their selected version of `(snail shell game physics)`. The C version keeps twelve structs in an automatic array and its intersection interval in scalar locals. Every sample must return exactly `342894`.

| Implementation | Median for 50,000 rays |
| --- | ---: |
| WasmGC, original pair-returning slabs | 3.63 ms |
| WasmGC, one borrowed interval per ray | 2.12 ms |
| Linear memory, original pair-returning slabs | 37.63 ms |
| Linear memory, one borrowed interval per ray | 3.32 ms |
| C in Wasm32, automatic storage | 0.69 ms |

Measured on Node 26.8.1 on an Intel Core Ultra 7 270K Plus. The runner warms each module three times, rotates the order in one process and takes the median of eleven timed calls. Compilation, instantiation and host I/O are outside the timed interval. Binaryen optimizes the Snail modules at `-O2`. Clang 23.1.3 optimizes C at `-O3`.

The scoped version removes the temporary pair allocations and the per-ray fold closure. On the same scoped source, WasmGC took about 64% of the linear backend's time. The C kernel took about one fifth of the scoped linear version's time. C also has contiguous wall data, different code generation and opportunities to specialize the twelve-wall traversal. This comparison measures their combined effect on this query. A whole game or the compiler can have a different allocation profile.

## Existing compiler and game workloads

The Siegework balance program exercises the economy and combat simulation through its existing expected-output checks, including a 3,000-tick defended position. Five alternating fresh-process runs follow one untimed pair. These timings include Node and Wasm startup.

| Workload | WasmGC | Linear memory |
| --- | ---: | ---: |
| Compile the balance program with the same compiler source | 0.49 s | 1.39 s |
| Execute the release balance program | 0.53 s | 2.90 s |

For the compiler comparison, the historical backend hosts today's compiler, and both compiler binaries must produce byte-identical linear-memory WAT. For the simulation, each backend builds the same application source and must print exactly `tests/siegework/balance.out`.

Separate diagnostic builds time the linear collector inside each program's entry and count its allocations. Each measurement snapshots the counters before formatting the report.

| Linear workload | Allocations | Allocated bytes | Collections | Total pause / elapsed | Longest pause |
| --- | ---: | ---: | ---: | ---: | ---: |
| Compiler | 11.45 million | 294 MB | 50 | 428 ms / 1,260 ms | 16.63 ms |
| Simulation | 78.92 million | 5.27 GB | 1,262 | 74 ms / 3,036 ms | 0.51 ms |

Removing the measured collection pauses while keeping everything else fixed would speed up these runs by at most 1.52× and 1.03× respectively. Explicit storage can also remove allocations, copies, pointer chasing and root handling. The ray comparison measures one such change. A separate Node trace reports main-isolate pauses on the WasmGC builds, including process startup.

## Reproduce

From the migration checkout, use a second worktree at the last commit that supports both the earlier WasmGC backend and scoped references. The build script bootstraps each checkout, builds both versions of the physics library with each backend, compiles the C control, and runs the comparison. It needs the repository's development shell and a Clang with the Wasm32 target and `wasm-ld`. Set `WASM_CC` to an unwrapped Clang executable when using a host-only compiler wrapper.

```sh
git worktree add --detach /tmp/snail-ray-wasmgc c1ccf1f88
nix-shell --run 'sh benches/linear-memory/build /tmp/snail-ray-wasmgc /tmp/snail-rays'
```

To repeat only the timing, run `node benches/linear-memory/compare.mjs` with the resulting `.release.wasm` files and `c.wasm`. The modules stay in the supplied output directory.

Run the controlled compiler and game comparison with `nix-shell --run 'node benches/linear-memory/workloads.mjs /tmp/snail-ray-wasmgc /tmp/snail-rays'`.

The older compiler, Siegework and schema-check timings are recorded in the [linear-memory experiment](https://github.com/tsnl/snail-scheme/pull/752). The [reference-counting study](https://github.com/tsnl/snail-scheme/issues/773) records the separate list microbenchmark and allocation counts.
