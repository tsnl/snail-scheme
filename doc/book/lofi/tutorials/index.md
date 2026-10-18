# Build Small Applications

These five tutorials take apart the ideas used by Siegework. Start with a
counter you can run in a terminal, then build a tiny shared marker board. Each
lesson introduces one responsibility and gives you a working checkpoint, a
change to try, and a place to find the same idea in Siegework.

The first three examples run without a browser or server. The last two use the
same 8 by 6 board, so learning persistence does not require learning another
application first.

| Tutorial | What you build | What it isolates |
| --- | --- | --- |
| [1. A counter](counter.md) | An integer changed by typed commands | State transitions and direct tests |
| [2. An inventory](inventory.md) | A purchase that can be refused | Immutable records and application rules |
| [3. Local controls](commands.md) | A control that requests a deposit | Separate owners and returned effects |
| [4. A shared marker board](board.md) | A browser app with three rectangles | Input, presentation, shaders and packaging |
| [5. Saving and reloading](reload.md) | The board keeping its shared position | Snapshots, compatible reload and restart |

## Set up once

Run commands from the repository root. The repository's `nix-shell` supplies
Chibi, Binaryen and Node; otherwise use the [build requirements](https://github.com/tsnl/snail-scheme/blob/main/doc/backend.md)
to provide them. These tutorials use the Chibi-hosted compiler and Node 24.

```sh
nix-shell
chibi-scheme -V
wasm-opt --version
node --version
mkdir -p build/examples
```

The browser lessons also need a browser with WebGPU and WasmGC. Their server
listens on localhost. They do not need a Rust runtime build or a native executable.
If WebGPU is unavailable, the first three lessons and the automated runtime
checks still work.

Finished sources live in
[`examples/applications`](https://github.com/tsnl/snail-scheme/blob/main/examples/applications/README.md).
Edit them in your own working checkout, or type the small complete examples
into the stated files. Each lesson's commands build those files directly.
Restore your exercise edits before running the checkpoint checks:

```sh
scripts/test-application-tutorials
```

This compiles and executes the three terminal examples, packages the board,
and checks its input, effects, snapshots, reload and SQLite restore in Node.
The browser observations in lessons 4 and 5 exercise the graphical host too.

## Five rules to keep beside your editor

1. **Put stored data in the state value.** A handler receives the old state and
   returns a `Transition` containing its replacement and any effects. Keep
   hidden mutable state out of handlers, views and snapshot code.
2. **Replace immutable values.** A setter such as `stock-ore-set` returns a
   new record. A previous reader still sees the previous value.
3. **Send commands to other owners.** Local selection belongs to the client;
   shared decisions belong to the authority. An effect describes a request,
   and the host delivers it after committing the local transition.
4. **Derive representation and check meaning.** Serialization derives check
   types and record shape. Your validator checks rules such as nonnegative
   stock or a position being inside the board.
5. **Keep the view a calculation.** State goes in; quads and text come out.
   Browser input, GPU resources, networking and durable storage belong to the
   existing host adapters.

The [application reference](../applications.md) has the full contracts. Read it
when a lesson reaches that boundary; you do not need the whole reference before
writing the counter.

## What can be simpler

For a small application, keep the record, handlers, validator and view in one
library. Extract a model library when the rules become a substantial subject,
as they do in Siegework. Use generated command constructors and derived
serialization instead of maintaining a message enum or field offsets yourself.
Write shader expressions directly; a macro is useful once you have shader
composition to reuse.

Some ceremony comes from the current browser adapter: it always has `match`
and `client` owners, and settings must name clock, reset and pointer handlers.
The board shows this explicitly, including a no-op clock. A future host with
optional inputs could shorten that setup, but those options are not implemented.
The examples use the existing host contract throughout.

The older [`state.sld`](https://github.com/tsnl/snail-scheme/blob/main/examples/applications/state.sld) demonstrates
an explicit word codec. It is useful when studying the lower-level bridge;
it is not required preparation for making an app. The board uses derived
snapshots, just like Siegework.
