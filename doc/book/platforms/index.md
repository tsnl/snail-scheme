# Platforms

A platform loads an artifact, supplies the ABI it needs, invokes its entry
points, and owns execution and external-resource cleanup. An engine is the
executable implementing that platform. The supported foreign functions come from
the Snail runtime; platform differences belong underneath that common API.

| Platform | Status | Reference boundary |
| --- | --- | --- |
| [Node / WASI](node.md) | Implemented command runner | Final linked Wasm module ↔ Node/V8 and WASIp1 |
| [Native](native.md) | Proposed native linkage | Compiled Scheme ↔ Rust runtime via the target C ABI |

These pages describe different link stages deliberately. Node loads an already
merged Scheme/Rust module, so only WASI and finalization imports remain. Native
linkage will resolve the Scheme/runtime boundary directly. The shared
[ABI rules](../abi.md) apply in both cases.

A browser platform is a later milestone for the chat tutorial. Reusing the
browser-compatible finalizer helper does not supply DOM operations, networking,
or the current Rust runtime's WASI dependencies. Give the browser its own page
when its first concrete module contract is specified; do the same for future
window/GPU services. There is no platform registry or file-extension lookup.

## One page per platform

Keep the complete reference for a platform on one page, in this order:

1. **Status and implementation.** Name the implementation and distinguish working
   behavior, proposed requirements, and unsupported operations.
2. **WAT module interface.** State whose perspective the module represents. Show
   import module/field names, exports, exact Wasm types, and required memories or
   tables. Interface stubs use `unreachable` and are not implementations.
3. **Symbols.** Give every displayed symbol a stable link and a rich-text bullet
   with its Wasm signature, parameter meaning, ownership, results, and effects.
   Document errors, callbacks, and any suspension where they occur.
4. **Lifecycle.** Specify initialization, dispatch, shutdown, resource cleanup,
   and failure. State what ordering and memory limits the platform actually
   provides, including whether calls block.
5. **Compatibility and evidence.** Record revision/feature requirements, commands
   that exercise the real platform, and gaps that still need implementation.

Store the WAT beside its page and include it into the code block. The same file
can then be assembled during review. Link to runtime code and standard ABI
definitions instead of copying their implementation into the book. Standard
interfaces such as WASI keep their own layout and error definitions.

The current interface files can be checked with the same Binaryen assembler
used by the compiler:

```sh
wasm-as --all-features doc/book/platforms/node.wat -o /tmp/snail-node-interface.wasm
wasm-as --all-features doc/book/platforms/native.wat -o /tmp/snail-native-interface.wasm
scripts/book build
```

Assembly verifies types and WAT syntax, not the described lifecycle. Compare
the Node imports with a freshly linked command and the native reference with
the Rust/Wasm runtime whenever either implementation changes.
