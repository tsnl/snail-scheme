# Marker board

An 8 by 6 board with one saved orange marker and one local white cursor.
Follow [the board tutorial](../../../doc/book/lofi/tutorials/board.md) and
[the reload tutorial](../../../doc/book/lofi/tutorials/reload.md) to build and
modify it step by step.

From the repository root with Chibi, Binaryen, Node 24 and Python 3:

```sh
chibi-scheme -I bootstrap \
  examples/applications/marker-board/build.scm "$PWD" "$PWD/build/marker-board"
python3 -m http.server 4174 --bind 127.0.0.1 --directory build/marker-board/solo
```

Open `http://127.0.0.1:4174` with WebGPU and WasmGC support. Move to choose a
cell, click or press Enter to place the marker, and use Reset marker or `r`
to return the saved marker to `0,0`. Pointer motion changes only the cursor;
placement updates the board and saves it in IndexedDB. The cursor retains its
last valid cell outside the board.

`src/tutorial/board.sld` owns both state declarations, handlers, snapshots and
presentation. `src/tutorial/shaders.sld` owns the GPU expressions. The build
recipe writes the static `solo/` package. The browser runs both state owners and
commits the board through `LocalState`; the file server serves only assets. No
app-specific JavaScript or changes to the runtime are needed.

Compatible rebuilds preserve both positions. Page refresh and browser restart
restore the saved board while initializing a new cursor. Use the same browser
profile, origin and application ID to reopen the save. A second tab cannot write
the same save: close the first tab, then reload the second to take ownership.
The host requires a clock endpoint, so `idle` leaves the board unchanged.

Run `scripts/test-application-tutorials` for compiled runtime and persistence
checks. Node uses a temporary file-backed checkpoint fixture; the tutorials give
the real browser, writer-lock and IndexedDB exercises.
