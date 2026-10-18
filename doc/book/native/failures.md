# Failures and testing

Expected Wasm failures check divisors, signed division overflow, conversion
ranges, nulls, bounds and casts before LLVM operations can produce undefined
behavior. Unsupported optimized instructions or module shapes fail with a
Wasm-specific diagnostic.
Linear memory, SIMD, atomics, exceptions and multivalue results remain outside
the native lowering subset. Function and global exports have C adapters;
exporting a table to a C host is rejected. Active element segments validate the
whole range, including empty segments beyond the table end.

Lofi I/O wrappers own scalar Rust resource handles. Alias-visible close detaches
the handle before flushing, and callbacks do not keep a Rust resource borrow
across a guest call. Normal return, traps, I/O failures and arena exhaustion
finish through terminal cleanup. Cleanup does not reenter generated code or
unwind through Rust. Resumable exceptions are not implemented. A failed worker invocation closes
that instance; another instance may run the same linked artifact.

## Validation

`scripts/test-native` executes common Wasm/native scalar semantics, conversions,
traps, subtype identity, cyclic graphs, exact tracing and tail calls. Lofi cases
also exercise mixed Rust scalar signatures at the C ABI, concrete variants/strings/bytevectors and
Unicode/I64 I/O, including `/dev/full`, stale aliases and allocation failure.
Commands and terminal outcomes remain under `build/native-tests`.

The shared checks are `make test`, `make check`,
`cargo test --manifest-path src/native/Cargo.toml --offline`,
`cargo fmt --manifest-path src/native/Cargo.toml --all -- --check`,
`scripts/test-backend` and `scripts/test-build`.
The public command and linked Wasm must actually execute; compilation alone is
not target validation. See [build requirements](https://github.com/tsnl/snail-scheme/blob/main/doc/backend.md).

## Stress execution

`scripts/test-native` builds both normal and stress variants of the semantic
fixtures, executes them, and checks the compiled mode. Other native integration
fixtures use `src/native/tests/cargo-gc-stress`, a test-only Cargo wrapper that
adds `native-runtime/gc-stress` when building native entry crates. Runtime
collection and movement counters provide explicit assertions; stderr is reserved
for actual diagnostics. Tests that need exhaustion freeze the stress heap at its
current capacity before executing the guest.

The standalone authored-Wasm test bypasses the source compiler and exercises both
LLVM bitcode and saved ELF links in normal and stress modes:

```sh
cd src/native
chibi-scheme -D snail-tests -I ../../bootstrap -I tests tests/standalone.scm
```

`scripts/test-package-isolation` also executes linked Wasm with the native
lowering libraries and native toolchain inaccessible, then runs a composed native
build from outside the repository. Historical measurement captures keep their
original settings; they are not descriptions of the current production policy.
