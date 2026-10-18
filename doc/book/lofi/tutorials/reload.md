# Keep state across code changes and restarts

Use the app from [the board tutorial](board.md) to see which state survives
code changes, browser refreshes and server restarts. Start the board with that
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

4. Wait for the new color without refreshing the page. The shared marker stays
   at `3,2` and the local cursor at `5,4`.

The authority polls the completed manifest and notifies browsers. A candidate
module is validated against current snapshots before installation, and the
browser prepares its GPU pipeline before switching. An existing owner keeps
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

This is different from compatible code reload. Refresh creates a new local
owner and reconnects to the authority's shared state. The current host does
not promise to preserve the local cursor or pending requests through a full
page reload. HTML, CSS and host JavaScript changes use this restart path.

## Restart the authority

Click a new cell, such as `6,1`, and wait until a second tab also shows
`Marker 6,1`. That confirms you are observing an authoritative update rather
than merely moving the local cursor.

Stop the server with Ctrl-C, then run the same command against the same output
directory:

```sh
PORT=4174 node build/marker-board/cloud/lib/browser/server.mjs "$PWD/build/marker-board/cloud"
```

Refresh the tabs to establish new sessions with the restarted authority. Expect
the shared marker at `6,1`, with fresh local cursors at `0,0`. The host restored
the committed match from `build/marker-board/cloud/match.sqlite`. Leave that file in
place while testing restart. The Reset marker button resets the shared position
through an ordinary command; no database deletion is needed.

The host commits the shared snapshot, revision, epoch and latest client receipts
together. Repeating a matching latest request can return its receipt without
running the command again. This protects those state transitions; it is not a
general guarantee for arbitrary external effects such as sending mail.

## Try an incompatible build

With the board running, change just the shared application's declaration from
`(state Cell 1)` to `(state Cell 2)` and rebuild. The new build can pass its
initial-state check, but the running authority rejects it against the existing
schema. The page reports the rejected reload and the installed board remains
usable. Do not restart the authority with this incompatible build; its saved
state still uses schema `1`.

Restore `(state Cell 1)`, restore the original marker color `16753920`, and
rebuild before stopping. Automatic migration is not implemented. A new schema
requires an explicit migration or a deliberately fresh application state.

## Check what you learned

| Action | Shared marker | Local cursor |
| --- | --- | --- |
| Change color and rebuild compatibly | Preserved | Preserved |
| Refresh a browser tab | Read from authority | Initialized again |
| Restart authority with the same database, then refresh tabs | Restored from committed snapshot | Initialized again |
| Build incompatible schema while authority runs | Old installed state retained | Old installed state retained |

Run `scripts/test-application-tutorials` after restoring the example. Its runtime
checks exercise retained snapshots, compatible replacement, schema rejection and
SQLite close/reopen restoration. The steps above additionally show the real
server, browser and pipeline behavior.

See the [reload reference](../applications.md#reload-boundary) for the full
compatibility requirements.
