# Platforms and effect interfaces

A **platform** is a collection of effect handlers with stated behavior. The
runtime runs a node using that platform. The common Scheme library deals with
values: numbers, text, symbols, pairs, vectors, hash tables, and datum syntax.
Platform handlers provide access to files, streams, clocks, command context,
diagnostics, and external build tools.

These are ordinary function effects, inspired by Koka's distinction between
function operations and control operations. A call invokes a named Wasm
function and returns normally, or terminates according to its contract. There
is no continuation capture, resumption object, control-effect interpreter, or
effect inference in this implementation.

## Define an interface and choose its handler

`(snail-scheme effects)` provides concrete interface, handler, and platform
records. An interface declares its name, revision, and complete operation list.
Each operation records its Scheme signature and behavior. Its default native
signature is `(param i32) (result i32)`: borrow an argument-vector root and
return one owned result root. An optional native signature describes operations
such as resource cleanup that take scalar IDs directly.

```scheme
(define-effect-interface clock 1
  (current-second (() -> Real) "Calendar seconds.")
  (current-jiffy (() -> Integer) "Monotonic ticks within one node.")
  (jiffies-per-second (() -> Integer) "Positive tick frequency."))
```

That example describes a new interface. To replace the implemented clock, use
its exported `clock-interface` descriptor, which contains the exact production
contract:

```scheme
(define clock-handler
  (make-effect-handler clock-interface "my.clock"
    '((current-second . "seconds")
      (current-jiffy . "ticks")
      (jiffies-per-second . "frequency"))))

(define platform
  (make-platform 'my-command
    (map (lambda (handler)
           (if (eq? (effect-name (handler-interface handler)) 'clock)
               clock-handler handler))
         (platform-handlers node-platform))
    '(("my.clock" . "clock.wat"))))

(parameterize ((current-platform platform))
  (build-wasm "." "app.scm" "dist/app.wasm"))
```

The script imports `(scheme base)`, `(snail-scheme effects)`,
`(snail-scheme build)`, and `(snail-scheme chromium-trace)`, and places build
calls inside `with-chromium-trace-to`. Module paths are explicit. Binaryen can
link WAT or Wasm providers. A provider importing the root API uses `snail.abi`;
it receives the same node's roots as the Scheme program.

A handler must supply every operation exactly once. Binding order is immaterial.
A platform selects one handler per interface. The linker checks the complete
standard interface contracts and any selected build interface, including revisions, and validates actual Wasm
function signatures. A matching descriptor is a declaration of semantics;
it cannot prove the provider's behavior. The integration check
`scripts/test-effects` links the same Scheme module with two clock providers and
also exercises rejected bindings, contracts, and Wasm signatures.

## Implemented interfaces

| Interface | Operations and default behavior |
| --- | --- |
| `filesystem` | Open, test, delete files, and locate packaged artifacts. WASI filesystem errors use named fatal diagnostics. |
| `ports` | Text/binary input, datum reading, output, current ports, explicit close, and resource cleanup. |
| `environment` | Initialize command context, obtain literal argv and environment values, terminate the command. |
| `clock` | Calendar time, monotonic nanosecond ticks, and tick frequency. |
| `diagnostics` | Scheme errors, internal failure codes, and UTF-8 diagnostic bytes from shared memory. |
| `build` | Literal subprocess argv, path identity, file copying, owned workspaces, and atomic publication. Node.js supplies these functions. |

Filesystem and port handlers must share the resource-kind and lifetime contract:
kind 1 denotes a port, IDs belong to this node, and only its selected port handler
may interpret those IDs. Replacing one requires a compatible implementation of
the other. Structural signature checks cannot establish that compatibility.

## Linking and calling

The generated platform module imports provider functions and re-exports them
as qualified names such as `clock/current-jiffy`. Scheme imports those names
from `snail.platform`. These are Wasm aliases; no dispatch loop or forwarding
function is needed. Qualified functions remain callable from the final module.
The linker removes private default-handler exports after resolving calls.

The current Rust link-time artifact contains both common operations and default
WASI implementations in one linear memory. `src/lib.rs` owns common operations;
`src/platform.rs`, `src/host.rs`, and `src/artifacts.rs` provide the default host
behavior. Selecting another clock replaces its public call paths. This is not
yet a freestanding browser library: remaining selected WASI handlers still need
a compatible host.

All handlers obey the [local ABI](abi.md). Roots and resource IDs cannot be sent
to another node. A JavaScript provider is supplied by the loader as an import;
its Wasm import declaration establishes the binary signature, while its behavior
and root ownership need execution tests. JavaScript subprocess execution in the
command platform is synchronous. Browser event delivery and asynchronous host
operations need their own interfaces and loader; a Promise is not a synchronous
Scheme result.
