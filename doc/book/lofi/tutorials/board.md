# Draw a saved marker board

Build a browser app with an orange saved marker and a translucent white local
cursor. Moving the pointer changes only your cursor. Clicking sends a typed
request to the board and saves its new position in this browser. The view draws
just three rectangles.

The finished app is
[`marker-board`](https://github.com/tsnl/snail-scheme/blob/main/examples/applications/marker-board/README.md).
Use the [shared setup](index.md#set-up-once) first.

## Run the finished board

```sh
chibi-scheme -I bootstrap \
  examples/applications/marker-board/build.scm "$PWD" "$PWD/build/marker-board"
python3 -m http.server 4174 --bind 127.0.0.1 --directory build/marker-board/solo
```

Open `http://127.0.0.1:4174` in a browser with WebGPU and WasmGC. Without an
existing browser save, the status starts at `Marker 0,0 | Cursor 0,0`. Both rectangles
occupy the top-left cell, so the white overlay lightens the orange marker.
If you have run it before at this origin, the marker is restored from IndexedDB.
The Reset marker button puts it back at `0,0`.

Move within the board, then click a different cell. The text shows coordinates
starting at zero. Open a second tab at the same URL: it explains that the save
is already open. Close the first tab and reload the second. The marker returns
to its saved position and the cursor starts at `0,0`. A browser Web Lock gives
one tab ownership of this save.

Keep the static file server running in this terminal. It serves the packaged
assets; the browser runs and saves the application. Use another terminal, also
at the repository root, for edits and builds.

## Follow the state through one click

Open [`board.sld`](https://github.com/tsnl/snail-scheme/blob/main/examples/applications/marker-board/src/tutorial/board.sld).
Both owners store a `Cell` with `I32` fields `x` and `y`. Valid cells have
`0 <= x < 8` and `0 <= y < 6`. `move-cell` returns a new cell for valid input
and retains the previous one for invalid input.

`board-app` handles saved placement and reset. `cursor-app` handles local
pointer motion and confirmation. They use the same state type but have distinct
typed command owners. Confirmation is the key operation:

```scheme
(confirm (state)
         (transition state
                     (list (enqueue board-target
                                    (place (cell-x state) (cell-y state))))))
```

The client keeps its cursor and returns a send description containing its
coordinates. The browser delivers that effect to the board's `place` handler.
The same Scheme reducer checks the bounds and constructs a replacement. The
host's `LocalState` writes the checkpoint to IndexedDB before publishing the new
board state. The white cursor can therefore move independently of the saved
orange marker.

The host converts pointer coordinates to cell coordinates before calling
`move`; do not divide by the cell size again in Scheme. Leaving the board retains
the last valid cursor. Enter or Place marker confirms that last selection.
Reset marker resets the saved marker and leaves the current cursor alone.

The `idle` handler returns the state unchanged. The current host requires a
clock endpoint even for this static board. Its clock can commit revisions,
but it does not move the marker.

## Turn values into rectangles

The entire view is:

```scheme
(define (view board cursor)
  (list (quad 0 0 320 240 1055781 255)
        (tile board marker-color 255)
        (tile cursor 16777215 90)))
```

`quad` takes `x`, `y`, width, height, packed RGB color and opacity from 0 to
255. These are logical pixels. `tile` multiplies cell coordinates by forty
and adds a two-pixel inset, producing a 36 by 36 square. List order is draw
order: background, marker, then translucent cursor. `status` independently
calculates the text from the same two values.

The renderer converts these rectangles into triangles and their positions into
clip coordinates. [`shaders.sld`](https://github.com/tsnl/snail-scheme/blob/main/examples/applications/marker-board/src/tutorial/shaders.sld)
contains the remaining GPU work:

```scheme
(define shader
  (compile-shader (gpu (vec4 position zero one)) (gpu color)))
```

The vertex expression extends the renderer's position to four components;
the fragment expression uses the supplied color. This needs no custom macro
or embedded WGSL string. `shader-entry` exposes the generated text to the build:
a negative input asks for its length, and other inputs select Unicode scalars.
A negative length reports a shader diagnostic and stops packaging.

## Connect the pieces

The remaining files each have one job:

| File | What to change there |
| --- | --- |
| `src/tutorial/board.sld` | State, handlers, bounds, view and status |
| `src/tutorial/shaders.sld` | GPU expressions |
| `settings.json` | Owner assignments, dimensions and input mappings |
| `index.html` | Canvas, status elements and buttons |
| `style.css` | Page layout and styles |
| `build.scm` | Source roots, exported entries and output artifacts |

Settings gives the app the stable ID `marker-board`, maps `board-app` to `match`,
and maps `cursor-app` to `client`. That order
agrees with `(serialized-program board-app cursor-app ...)`. The browser owns
both applications; only the `match` snapshot is saved. Their typed destinations
keep commands distinct even though both owners use `Cell`.
`pointer.move` names the two-argument local handler, and `pointer.confirm`
names the zero-argument local handler. The HTML buttons use those same lexical
handler names through `data-handler`.

The build recipe supplies the app's `src/` and shared repository `src/` as
library roots. It compiles simulation and shader entries, retains application
declarations for the manifest, and calls the shared packager. The packager checks
the settings and executes the initial state/view before publishing each package's
`manifest.json`. It writes the static `solo/` package with the shared browser host
and its IndexedDB adapter. The HTML's `data-application-entry` script is replaced
with `lib/browser/solo.mjs`. You do not need app-specific JavaScript.

## Change the presentation

In `board.sld`, change the cursor opacity in `(tile cursor 16777215 90)` from
`90` to `160`. Rebuild with the first command. Without refreshing the page,
the white cursor becomes more opaque and the positions stay the same. Restore
`90` and rebuild when finished.

If startup fails, read the connection text on the page and the build output.
“WebGPU is unavailable” concerns browser support; an unknown handler concerns
the settings names. A port conflict can be resolved by choosing another port in
the Python command and opening that URL. A different port is a different browser
origin, so it has a separate save. Stop the file server with Ctrl-C when done.

Next: [save and reload the board](reload.md) to keep state across code changes
and browser restarts.
