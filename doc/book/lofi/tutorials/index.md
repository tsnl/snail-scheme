# Tutorials

Build a counter, an inventory and a shared browser board. Follow the tutorials
in order; each includes working code and an exercise.

The first three run in a terminal. The last two use the same 8 by 6 browser board
to teach shared state, saving and reloading.

| Tutorial | What you learn |
| --- | --- |
| [1. Counter](counter.md) | Change state with typed commands |
| [2. Inventory](inventory.md) | Update immutable records and reject invalid purchases |
| [3. Local controls](commands.md) | Send a command to a separate state owner |
| [4. Shared marker board](board.md) | Handle browser input and draw shared state |
| [5. Saving and reloading](reload.md) | Keep state across code changes and server restarts |

## Set up once

Run commands from the repository root. Use `nix-shell` for Chibi, Binaryen and
Node 24, or install the [build requirements](https://github.com/tsnl/snail-scheme/blob/main/doc/backend.md)
yourself.

```sh
nix-shell
chibi-scheme -V
wasm-opt --version
node --version
mkdir -p build/examples
```

The last two tutorials need a browser with WebGPU and WasmGC. The first three
run without a browser. No Rust runtime build is needed.

Finished sources live in
[`examples/applications`](https://github.com/tsnl/snail-scheme/blob/main/examples/applications/README.md).
Edit those files as you follow each tutorial. Restore your exercise edits
before checking the finished examples:

```sh
scripts/test-application-tutorials
```

This runs the terminal examples and checks the board's input, snapshots, reload
and database restore in Node. Follow the browser steps in tutorials 4 and 5 to
check drawing and interaction.

Start with [the counter](counter.md). Consult the
[application reference](../applications.md) for the full API contracts.
