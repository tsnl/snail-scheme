# Building and testing Lofi

The compiler implementation runs in Chibi and emits Wasm from `.sld` inputs.
Ordinary Scheme build scripts import that compiler and the separate
[Wasm-to-native package](../wasm-native/README.md) to compose native builds.
Hygienic macros and the initial Scheme base forms expand to the same typed core.
Full Scheme support and self-hosting remain deferred.

`nix-shell` supplies Chibi, Chez, Node, Binaryen, LLVM and Rustup.
Install the Rust target used by the shared WASI runtime:

```sh
rustup target add wasm32-wasip1
./lofi run examples/fibonacci.sld
scripts/build-native examples/fibonacci.sld build/fibonacci
build/fibonacci
```

Binaryen is mandatory for both execution routes. The preflight checks `wasm-as`,
`wasm-opt`, `wasm-dis` and `wasm-merge`. Tool overrides are `CHIBI`, `NODE`,
`CARGO`, `WASM_AS`, `WASM_OPT`, `WASM_DIS` and `WASM_MERGE`; native builds also
use `LLVM_OPT`, `LLC` and `RUSTC`. An invalid override fails explicitly. Cargo
builds the single runtime crate at `wasm-native/Cargo.toml` offline, so dependencies must
already be available locally. Rust `cfg` selects the Wasm or native runtime
implementation; filesystem and other scalar services share the same sources.

Repository Scheme scripts use explicit search roots:
`chibi-scheme -I "$repo/bootstrap" -I "$repo/wasm-native/scheme" SCRIPT ...`.
The standalone package needs only `-I "$package/scheme"` and installed Chibi/SRFI
libraries; its tests additionally use `-I "$package/tests"`.
`(wasm-native runtime-wasm)` builds and links the runtime's Wasm form without
importing native lowering. The compiler likewise imports only the neutral Wasm,
optimization and host utilities it needs from the package.

Native execution currently validates x86-64 Linux. It lowers the optimized
Wasm mechanically and links the same Rust externs, the native host, and the
in-house Rust collector. Rust providers export concrete `extern "C"` functions;
unsupported ABI spellings fail before linking. Cargo invokes Rust's bundled
`rust-lld` directly: no C compiler driver is required. The native executable
still uses the system C runtime and startup objects; `SNAIL_NATIVE_LIBC` and
`SNAIL_NATIVE_GCC` select those library directories on Nix. Coreutils supplies
ordinary file copying and hashing for the Scheme tools.
See [command options](options.md).

Executable builds keep optimized guest LLVM bitcode until linker-plugin fat LTO
can optimize it with the Rust entry, runtime and providers. LLVM `opt` and Rust's
bundled linker must accept compatible bitcode versions. The public `llvm-object`
operation still emits a real ELF object for saved artifacts; these link without
guest optimization across the machine-code boundary.

Set `SNAIL_NATIVE_CPU=x86-64-v3` to opt into that CPU for fresh guest code and
the Rust entry, runtime and providers. Leaving it unset preserves the portable
default. CPU selection does not enable relaxed floating-point operations or
change traps. Empty values fail at native compilation; LLVM and Rust diagnose
unsupported names. Ordinary builds may use `native`, whose meaning depends on
the build host. Host build scripts and the supervisor retain their existing
flags. A saved ELF object retains its original instructions when linked later;
its guest CPU stays unknown in build evidence, separately from the new Rust CPU
selection. See the [package build API](../wasm-native/README.md#scheme-build-api).

Native array length and element accesses emit checked LLVM header loads and
address calculations with the validated storage width. Allocation and bulk copy
stay in Rust; the [package representation contract](../wasm-native/README.md#native-array-representation)
describes the layout, traps and compatibility exports.

The Nix shell sets `RUSTC_WRAPPER` to `wasm-native/scripts/rustc-native`. This
small Scheme wrapper also supplies the native linker for Cargo's host build scripts during
Wasm builds. It preserves Cargo's selected compiler, explicit target and linker.
On x86-64 Linux outside the Nix shell, enable it from the checkout with
`export RUSTC_WRAPPER="$PWD/wasm-native/scripts/rustc-native"` before running Cargo directly.
Native executable builds configure their linker and default to this wrapper,
preserving an explicit override. They pass a native Cargo target so shared-LTO
flags reach only target crates, leaving host build scripts to the wrapper.

[`build.scm`](../build.scm) is a small library-composition recipe. From any
working directory, with `repo` set to the checkout's absolute path:

```sh
chibi-scheme -I "$repo/bootstrap" -I "$repo/wasm-native/scheme" "$repo/build.scm" \
  "$repo" "$repo/examples/native/answer.sld" answer \
  "$repo/examples/native/entry.rs" /tmp/lofi-answer
/tmp/lofi-answer
```

The executable prints `42`. The recipe's arguments are
`REPOSITORY SOURCE EXPORT RUST-ENTRY OUTPUT`; it compiles the selected public
export to Wasm, lowers those bytes to an object, and links the supplied Rust
entry point through Cargo.

## Checks

The reader checks use canonical data from the pinned benchmark submodule.
Initialize it before running the aggregate checks:

```sh
git submodule update --init benchmarks/r7rs-benchmarks
make test
make check
cargo test --manifest-path wasm-native/Cargo.toml --offline
cargo fmt --manifest-path wasm-native/Cargo.toml --all -- --check
scripts/test-build
scripts/test-backend
scripts/test-native
```

Host unit tests do not establish target behavior. Backend checks execute linked
Wasm, and native checks execute native code, including forced collection and
traps. The Lofi integration migration preserves the prior typed contracts while
removing Scheme syntax expansion from their runners.

GitHub Actions runs these checks on x86-64 `ubuntu-24.04`, using the Nixpkgs
revision and Rust version pinned in [the workflow](../.github/workflows/ci.yml).
It initializes the benchmark input submodule and fetches locked Cargo dependencies
before the offline test commands. Nix dependencies, Rust and downloaded crates
are cached; generated guest artifacts are rebuilt. A new push cancels an obsolete
run of the same pull request.

[`tests/backend-suites.json`](../tests/backend-suites.json) is the ordered backend
inventory. With no arguments, `scripts/test-backend` still runs the whole inventory
serially. Named arguments select suites while preserving inventory order:

```sh
scripts/test-backend binaryen lofi-execution
node tests/ci.mjs matrix
node tests/ci.mjs run integration-1
```

CI distributes the ordinary backend suites across nine jobs and integration cases
across eight jobs. Round-robin assignment spreads the manifest's clusters of
compile rejections across those jobs. The plan checks that every suite and case
appears exactly once, and each job verifies its actual completion records against
its assignment. Host checks, native execution, and public-build/application checks
have their own jobs. A successful `Complete correctness checks` status requires
every planned job to pass. The 20 matrix jobs fit GitHub's documented
[standard-runner concurrency limit](https://docs.github.com/en/actions/reference/limits#job-concurrency-limits-for-github-hosted-runners)
for the Free plan; the planning and completion jobs run outside that phase.
A failing backend partition retains the existing
stop-on-first-failed-suite behavior; other partitions continue.

Each job uploads command records, stdout/stderr, selection/completion records and
generated Wasm/LLVM diagnostics for seven days, including on failure. These are
correctness diagnostics. Parallel CI durations are not workload benchmarks or
evidence of runtime performance parity; see the [test-runner notes](../tests/README.md).

Build helpers retain WAT, raw Wasm, optimized Wasm and trace files. Native build
directories also retain LLVM, commands and source hashes. Public compile commands
publish only a complete artifact; failed builds leave the previous output intact
and print the retained directory. Successful public runs remove their private
build files.

Benchmarks have their own [frozen protocol](../benchmarks/README.md). Record
compilation and execution separately; preserve failures and compare complete
matched workloads. Run clean timing samples without concurrent compilation,
profiling or forced-GC jobs.

For compiler depth diagnostics, run
[`compile-cost.scm`](../tests/lofi-generation/compile-cost.scm) against the selected
checkout's module roots:

```sh
chibi-scheme -I "$repo/bootstrap" -I "$repo/wasm-native/scheme" \
  tests/lofi-generation/compile-cost.scm 64 128 256 512
```

The same script works with another revision's roots. It reports checking,
concrete preparation and Wasm emission separately for nested addition, discarded
conditionals and generic calls with a fixed result type. These are synthetic
compiler diagnostics; the script does not execute the generated Wasm or assert
timing thresholds. Instrumented call counts help explain costs, while clean
comparisons require uninstrumented runs without concurrent jobs. Keep these
diagnostics separate from the complete 57-workload benchmark comparison.
