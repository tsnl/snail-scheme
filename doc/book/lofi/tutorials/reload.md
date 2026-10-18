# Keep state across code changes and restarts

Use the app from [the board tutorial](board.md) to see which state survives
code changes, page refreshes and browser restarts. Start the board with that
tutorial's build and server commands.

## Give state a portable representation

The board's record opts into serialization:

```scheme
(define-immutable-record Cell cell
  (x I32 cell-x cell-x-set)
  (y I32 cell-y cell-y-set)
  (deriving derive-serialize derive-deserialize))
```

`(lofi serialization)` supplies the derives, and the import from `(lofi core)`
includes the `deriving` declaration. The generated instances describe the type,
constructor and fields. The shared adapter supplies the schema envelope and
binary snapshot format; you do not maintain word offsets for each field.

A decoded `I32` can still be outside the board. That is why `validate-cell`
checks the coordinates and traps on an invalid value. `serialized-program`
connects both typed applications, their validators, the view and status:

```scheme
(serialized-program board-app cursor-app
                    validate-cell validate-cell view status)
```

This is a useful division of work: derives construct correctly typed records;
the validator establishes their application meaning. A malformed or invalid
snapshot cannot replace committed state. These derives do not migrate old
schemas, and serializing a value alone does not save it to disk.

## Replace code while keeping both owners

1. Run the board on port 4174. Click cell `3,2`, then move the cursor to `5,4`
   without clicking. Expect `Marker 3,2 | Cursor 5,4`.
2. In `examples/applications/marker-board/src/tutorial/board.sld`, change
   `marker-color` from `16753920` (orange) to `65535` (cyan).
3. In a second terminal at the repository root, rebuild:

   ```sh
   chibi-scheme -I bootstrap \
     examples/applications/marker-board/build.scm "$PWD" "$PWD/build/marker-board"
   ```

4. Wait for the new color without refreshing the page. The saved marker stays
   at `3,2` and the local cursor at `5,4`.

The browser polls the completed manifest. A candidate module is validated
against current snapshots before installation, and the browser prepares its
GPU pipeline before switching. An existing owner keeps
its state; its initializer does not run again. No Wasm heap pointer needs to
survive the module replacement.

The marker color can change because it is a presentation constant. Keep the
library identity, application identities, state declaration, schema versions
and handler contracts unchanged for this exercise. Adding a handler is a
protocol change too, even if the state record stays the same.

## Reload the page

Move the pointer outside the canvas so a new pointer event will not immediately
update the cursor, then refresh the page. The marker stays at `3,2`; the new
local cursor starts at `0,0`.

Refresh creates a new local owner and restores the committed marker from
IndexedDB. Compatible code reload preserves both owners already in memory.
The host does not preserve the local cursor or pending requests through a full
page reload. HTML, CSS and host JavaScript changes use the page reload path.

## Reopen the saved board

Click a new cell, such as `6,1`. Wait until the status shows `Marker 6,1`
and the connection line reports a saved revision. Move the pointer outside the
canvas, close the tab, and reopen the same address in the same browser profile.
Expect the marker at `6,1` and a fresh cursor at `0,0`. You can also close and
reopen the browser to repeat this check.

The save belongs to this browser profile, origin and application ID. The static
file server holds no application state. You can stop it with Ctrl-C and start
it again on the same port before reopening the page:

```sh
python3 -m http.server 4174 --bind 127.0.0.1 --directory build/marker-board/solo
```

Changing the port changes the origin and therefore opens a different save.
Clearing site data removes the saved board. The Reset marker button resets its
position through an ordinary command, preserving the save itself.

Only one tab can write a save. Open the same address in a second tab while the
first is still open: the second reports that the save is already open. Close
the first tab and reload the second. It now acquires ownership and restores the
last committed marker.

`LocalState` manages a checkpoint containing a `revision` and the match owner's
serialized `state`. Its persistence callback checks the previous revision and
writes the next checkpoint in one IndexedDB transaction. The runtime publishes
the replacement state only after that transaction completes. A failed write
leaves the previous state and revision intact, so an explicit retry can commit
the requested change. The local cursor is not part of this checkpoint.

## Try an incompatible build

With the board running, change just the board application's declaration from
`(state Cell 1)` to `(state Cell 2)` and rebuild. The new build can pass its
initial-state check, but the running browser rejects it against the existing
schema. The page reports the rejected reload and the installed board remains
usable. Its saved state still uses schema `1`; refreshing with the incompatible
build reports that the save cannot be opened and keeps the save intact.

Restore `(state Cell 1)`, restore the original marker color `16753920`, and
rebuild before refreshing or closing the page. Automatic migration is not
implemented. A new schema requires an explicit migration or a deliberately
new application ID with a separate save.

## Check what you learned

| Action | Saved marker | Local cursor |
| --- | --- | --- |
| Change color and rebuild compatibly | Preserved | Preserved |
| Refresh the page | Restored from IndexedDB | Initialized again |
| Reopen the same origin in the same browser profile | Restored from IndexedDB | Initialized again |
| Build incompatible schema while the page runs | Old installed state retained | Old installed state retained |

Run `scripts/test-application-tutorials` after restoring the example. Its runtime
checks exercise retained snapshots, compatible replacement, schema rejection,
and `LocalState` checkpoint restoration, failed-write rollback and retry. The
Node runner supplies a temporary file-backed persistence callback. The steps
above additionally exercise the real browser, IndexedDB, writer lock and GPU
pipeline.

See the [reload reference](../applications.md#reload-boundary) for the full
compatibility requirements.
