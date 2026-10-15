# Cat: scalar foreign calls and concrete character storage

Replacing the generic Scheme/Rust character-I/O boundary reduces this frozen
`cat` workload from 21.01 to 8.12 seconds. A second diagnostic also keeps
characters in native registers and simplifies the loop, reaching 2.68 seconds.
These are measured prototypes, not performance results from the strict compiler.

| Variant | Retained samples (s) | Median (s) | Control / variant |
| --- | --- | ---: | ---: |
| Same-runtime control | 21.009146, 21.214968, 20.749528 | 21.009146 | 1.00× |
| Scalar imports, existing loop | 8.116424, 8.114741, 8.200894 | 8.116424 | 2.59× |
| Scalar imports and concrete loop | 2.681859, 2.680910, 2.761380 | 2.681859 | 7.83× |

Every variant copies the original 4,460,056-byte ASCII file fifty times, one
character at a time. All twelve full invocations, including one discarded run
per variant, passed independent output-size and SHA-256 checks. Compilation is
outside the workload timer. Fresh default-tier Node 24.19 processes ran on CPU 5
in a coordinated quiet window, rotating variant order over three retained rounds.
The variants share one runtime binary, source, input, host, and link recipe.

## What changes

The first variant retains the original generated loop and generic foreign calls.
The second changes the character wrappers to call Rust exports with native
signatures. It retains the caller's argument arrays, character boxes, and one
owner root per operation, while removing the Rust argument/result root traffic
and extraction machinery. Its gain supports substantial cost at that boundary.

The third variant replaces the frozen `catport` WAT function with the same
read/EOF-test/write sequence, retaining a Unicode scalar in an `i32` local and
rooting the two port owners around an entire copy. It also removes the old loop's
capture environments and value envelopes. Its result combines several changes;
it does not attribute the whole gain to imports or any single helper.
Opening, closing, buffering, the input count, and benchmark controls remain in
the original program. The diagnostic performs no bulk byte copy.

This hand-lowered loop ignores a deferred result-check parameter that is unused
in the frozen cat call context. General compiler lowering must preserve result
contracts. The Rust provider also still uses the old ABI to initialize and create
port wrappers; only the scalar operations avoid per-call Scheme roots. This
prototype is not yet a standalone strict-language I/O provider.

## Foreign declaration and ownership contract

The archived declaration parser emits imports directly from complete native
function types, for example:

```scheme
(define-extern read-code "snail.library" "snail:io/read-code" (-> I32 I32))
(define-extern write-code "snail.library" "snail:io/write-code" (-> I32 Char I32))
```

`read-code` returns a Unicode scalar, `-1` for EOF, or `-2` for an error.
`write-code` returns zero or `-2`. Scheme wrappers interpret these carriers.
The prototype also supplies peek, close, and fatal error reporting. Failed
operations retain one Rust diagnostic, which must be consumed before another
failing operation replaces it. Scalar calls neither allocate Scheme values nor
invoke Scheme callbacks.

The integer port ID is a provider resource identifier, not a WasmGC address.
The caller must retain the owning GC wrapper across allocation and callbacks.
IDs are never reused; delayed cleanup cannot close a newer resource. The
diagnostic keeps both owners rooted throughout the copy and releases them at
EOF. Error paths terminate the invocation. Public typed extern support must
retain these ownership and error contracts.

Linked Node checks cover Unicode including NUL and the maximum scalar,
malformed/truncated UTF-8, EOF and peek, interoperation with existing port calls,
closed/invalid/wrong-direction ports, mismatched native signatures, forced GC,
and delayed resource cleanup. Relevant Scheme tests, Rust tests, formatting,
and an independent simplify review passed at checkpoint `2c04755`.

## Preserved evidence

- [Clean runs](clean.json) and [linked checks](validation.json).
- [Frozen archive](https://github.com/tsnl/snail-scheme/blob/16f4423c9f0f579d9cf154c171309755a3d7ae05/benchmarks/results/2026-10-13-cat-scalar-extern/artifacts.tar.gz), hashed by [manifest](manifest.json).
- [Earlier cat profiling and EOF-array ablation](../2026-10-13-cat-abi/README.md).
- [Five Rust/Wasm references and Chez controls](../2026-10-13-wasm-five-reference/README.md).

The archive preserves all three WAT/Wasm variants, the exact runtime, source
snapshots, original input/output, host, native signatures, build commands,
tool identities, and original measurement driver. Production compiler/runtime
files are unchanged by this evidence report.

Restore and verify all ninety-one files and compile the three modules without
executing their workloads:

```sh
python3 benchmarks/results/2026-10-13-cat-scalar-extern/replay.py /tmp/cat-scalar-restored
```

After arranging a quiet host, add `--measure` for a new balanced batch. Replay
requires the original recorded Node executable and verifies its hash. It
relocates artifact paths while preserving the measured binaries and driver.
