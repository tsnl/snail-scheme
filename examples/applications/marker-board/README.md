# Marker board

An 8 by 6 shared board with one orange marker and one white cursor per browser.
It isolates the input, ownership and rendering boundaries used by Siegework.
Follow [the board tutorial](../../../doc/book/lofi/tutorials/board.md) and
[the reload tutorial](../../../doc/book/lofi/tutorials/reload.md) to build and
modify it step by step.

From the repository root with Chibi, Binaryen and Node 24:

```sh
chibi-scheme -I bootstrap -I wasm-native/scheme \
  examples/applications/marker-board/build.scm "$PWD" "$PWD/build/marker-board"
PORT=4174 node build/marker-board/lib/browser/server.mjs "$PWD/build/marker-board"
```

Open `http://127.0.0.1:4174` with WebGPU and WasmGC support. Move to choose a
cell, click or press Enter to place the marker, and use Reset marker or `r`
to return the shared marker to `0,0`. Pointer motion is local; placement is
shared across tabs. The cursor retains its last valid cell outside the board.

`src/tutorial/board.sld` owns both state declarations, handlers, snapshots and
presentation. `src/tutorial/shaders.sld` owns the GPU expressions. The build
recipe compiles these against the existing shared libraries; no app-specific
JavaScript or changes to the runtime are needed.

Compatible rebuilds preserve both positions. Page refresh initializes a new
cursor. The authority saves committed shared state in the output directory's
`match.sqlite` and restores it on restart; refresh tabs after a server restart.
The host requires a clock endpoint, so `idle` leaves the board unchanged.

Run `scripts/test-application-tutorials` for compiled runtime and persistence
checks. The tutorials give the two-tab graphical checks.
