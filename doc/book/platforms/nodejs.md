# Wasm (Node.js)

`scripts/run-wasi.mjs` loads one linked Wasm artifact into Node.js. That artifact
contains Scheme's WasmGC code, the Rust runtime compiled for `wasm32-wasip1`, and
an entry module. Node.js supplies WASI preview 1 and the finalization hooks used
by the local [ABI](../abi.md).

| Capability | Behavior |
| --- | --- |
| Entry | `_start` initializes the Rust runtime, initializes the selected environment, then executes Scheme once. Explicit command entries call the selected `main`. |
| Arguments and environment | The module filename heads the argument list; remaining arguments and the environment pass through. |
| Files and ports | WASI exposes `/`; initialization sets the guest working directory to the host cwd. Standard input/output/error are inherited. |
| Scheme memory | The Wasm engine collects Scheme objects; owned roots keep values live across runtime calls. |
| Resources | `src/runtime/host.mjs` supplies finalization registration and calls `ports/drop-resource` with resource IDs. |
| Build tools | Node.js implements literal subprocess calls and atomic artifact publication through the build effect interface. |
| Node connections | Node `spawn`, `connect`, message codecs, and connection clients are not implemented. |

## Build and run

From the checkout, with the tools in `nix-shell` and Cargo's offline dependencies
and `wasm32-wasip1` target available:

```sh
chibi-scheme -I src tests/build-program.scm . \
  tests/programs/backend-bootstrap.scm build/bootstrap.wasm
node --no-warnings scripts/run-wasi.mjs build/bootstrap.wasm
```

The program prints:

```text
bootstrap checks passed
```

`tests/build-program.scm` is a small build script that wraps `build-wasm` in a
trace scope. It writes the linked artifact and `build/bootstrap.wasm.trace.json`.
A project's own `build.scm` can call the same library. `run-wasm` from
`(snail-scheme build)` invokes this runner and returns its process exit status.

Node.js must support the Wasm features selected by the compiler, including
WasmGC and tail calls. A module with unavailable imports or features fails before
its entry runs. This command platform has the host filesystem access of an ordinary local CLI.
Its root preopen and explicit guest cwd avoid overlapping `/` and `.` preopens.
Other platforms must state their own filesystem semantics.

## Startup and cleanup

The runner reads and compiles the module, creates the WASI and finalization
imports, instantiates the module, and calls `wasi.start`. It uses the returned
status as the process exit code. There is one invocation of the program entry;
this runner supplies no connection dispatch loop.

The finalizer's held data contains a resource kind and ID, without retaining the
Scheme wrapper it watches. Keep those imports alive with the instance. Use
explicit close when timely cleanup matters: finalizers need not run before
process shutdown. Invalid startup, runtime errors, and fatal Wasm traps fail the
command; they do not become recoverable connection errors.

The JavaScript finalization helper is reusable host code. It does not itself
supply the [browser GUI runtime](browser-gui.md).
