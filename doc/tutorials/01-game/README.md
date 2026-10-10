# A game that reloads while you play

Build a small arena game: move a player, bounce a few obstacles, and change the
movement rule while the game keeps running. The window and renderer survive;
each frame's temporary Scheme heap disappears after its output is handed off.

**Status: project specification, not a runnable tutorial yet.** All actor APIs in
the sketches are proposed. The [platform design](../../why-snail-scheme.md) defines
their meaning; [requirements](requirements.md) define what a finished version
must demonstrate. The eventual tutorial will include its tested source directly.

## 1. Let the runtime start the game

Start with an actor definition selecting `(arena application)` and its exported
handlers. A build compiles that definition; a native window runtime instantiates
it and supplies events. There is no Scheme-owned polling loop.

Use the shape of winit's
[ApplicationHandler](https://docs.rs/winit/latest/winit/application/trait.ApplicationHandler.html)
as the precedent: resume, window events, suspension, and shutdown are host callbacks.
The Scheme facade exposes ordinary functions and serializable event records,
without copying native event-loop pointers into Scheme messages. Redraw comes
from a window redraw event; an idle callback is not a frame clock.

```scheme
;; Proposed application.sld excerpt; helpers belong to the window/game libraries.
(define-library (arena application)
  (export resumed window-event suspended exiting)
  (import (scheme base) (arena hosting))
  (begin
    (define window #f)

    (define (resumed services)
      (set! window (open-game-window services "Arena")))

    (define (window-event event)
      (cond
        ((redraw-event? event) (schedule-frame window event))
        ((input-event? event) (record-input window event))
        ((close-event? event) (close-game-window window))))

    (define (suspended)
      (release-window-surface window))

    (define (exiting)
      (close-game-window window))))
```

`window` is deliberate actor-local state. The native provider owns the actual
window/surface resources; the facade carries references and connections. Repeated
resume/suspend events must be handled by that facade's lifecycle contract. Add
a save-snapshot action using a file-service connection to show IO beyond rendering.

**Checkpoint G01:** open a window, move it, resize it, and close it. Observe the
exported functions being invoked by the host and resources being released.

## 2. Put the game rule in an ordinary function

Model the world and input as records. `advance-world` returns a new world;
`draw-world` constructs rendering commands. These functions know nothing about
windows, schedulers, connections, or the storage location of the world.

```scheme
;; Proposed frame.sld handler; its helpers are ordinary pure Scheme functions.
(define (step input)
  (let* ((world (advance-world (frame-world input)
                               (frame-input input)
                               (frame-delta input)))
         (drawing (draw-world world)))
    (make-frame-result (frame-number input) world drawing)))
```

Run deterministic input traces through this rule on the compiler host first.
Keep reusable actor/window libraries separate from this application's game rules.
The output commands describe meshes and resource references; they are not a
serialized framebuffer or a fresh copy of every texture.

**Checkpoint G02:** a known input trace produces a known world and draw command
sequence. Save and reload a snapshot through the native file service.

## 3. Give each frame its own actor

The session supervisor supplies a world snapshot, input, frame number, and the
frame artifact to a newly spawned actor. A single-shot spawning policy retires
that actor after its result is encoded or it fails. This is a use of the ordinary
actor lifecycle, not a special frame allocator built into the language.

```scheme
;; Proposed implementation shape inside the session's schedule-frame helper.
(define (compute-frame input frame-artifact frame-policy)
  (let* ((child (spawn frame-artifact '() frame-policy))
         (frame (connect child 'frame/v1)))
    (invoke frame 'step input)))
```

`frame-policy` declares single-shot lifetime, heap budget, GC permission, and
supervision behavior. `compute-frame` can return a future; the session receives
its completion without locking its input and window handlers. The session owns
outstanding frames and closes their connections. Native retained state supplies
the next snapshot. Do not retain a closure or pointer into the dead frame heap.

For the baseline game, permit one simulation frame in flight and coalesce redraw
requests while collecting input. That is a game ordering choice, not an actor
lock. Number outputs so a cancelled or superseded frame cannot commit stale
world state. Later, independent render preparation can use multiple actors.

**Checkpoint G03:** show frame IDs, heap high-water marks, and actor retirement.
After completed frames drain, temporary heap usage returns to its baseline.

## 4. Keep the expensive resources alive

| Owner | Lifetime | What crosses a connection |
| --- | --- | --- |
| Window/session actor | The play session | Window events, service references, world versions. |
| Native world store | The play session or saved game | Snapshots or versioned resource references. |
| Frame actor | One frame computation | Input records and an owned frame result. |
| Native renderer | Device/window lifetime | Draw commands and buffer/texture references. |
| File service | Its configured scope | Paths, snapshot references, completion/errors. |

The renderer pins resources until GPU completion. Discarding a frame heap does
not release a texture still used by submitted work. Every command still uses the
derived S-expression protocol, even when the renderer is in the same process.

**Checkpoint G04:** retain textures across many frames; resizing and a delayed GPU
completion do not access freed data. Inspect encoded message sizes separately
from device allocations.

## 5. Change the rule while playing

Edit movement speed or obstacle behavior. A supervised build uses the changed
source's dependency graph to compile and validate a new frame artifact. Publish
that version for subsequent frame spawns. An already running frame finishes on
its original version; each committed result records the version that produced it.

The window, renderer, and world store remain owned by the session. Invalid code
reports a source diagnostic while the last valid artifact stays active. A world
schema change needs a declared migration or restart, not silent reinterpretation
of retained bytes. Reloading a renderer artifact follows the same principle but
must also respect in-flight GPU work.

**Checkpoint G05:** change a rule successfully, introduce a compile error, and
recover. Show versioned frames and uninterrupted session ownership throughout.

## 6. Make the resource claim measurable

Exercise `no-gc`, `expect-no-gc`, and `allow-gc` with an intentionally small frame
budget. Record collection counts and budget outcomes; debug traps must terminate
the offending isolate through the host's failure mechanism, preserving supervision.
If an implementation can only abort an OS process, the spawner must isolate that
actor accordingly rather than promising recovery inside the aborted process.

**Checkpoint G06:** fail one frame and continue the session cleanly; explicitly
permitted release recovery collects only at a rooted safepoint. Enforce bounded
queues and a cap on concurrent frame actors as well as individual heap budgets.

**Extension G07:** derive an allocation bound for a restricted frame rule with a
fixed maximum entity count. Include decoding, stack/continuation storage, closures,
temporary draw lists, and output encoding. Compare the bound to measurements and
reject inputs outside its assumptions. General allocation proofs remain research;
measurements alone are not a proof.

## Proposed project contents

These paths describe future responsibilities; no source stubs are added yet.

| File | Responsibility |
| --- | --- |
| `build.scm` | Export the game application recipe and select runtime/target configuration. |
| `application.sld` | The root actor's event handlers and connections. |
| `frame.sld` | Pure rules and the single-shot frame handler. |
| `types.sld` | World, input, result, and protocol record types. |
| `fixtures/` | Deterministic input traces, small assets, and incompatible reload candidates. |
| `tests/` | Headless lifecycle tests plus a real window/GPU integration run. |

The host/framework owns scheduling, native service implementations, and reload
machinery. The tutorial should read from game rules through the handlers to their
build definition, with each checkpoint runnable once implemented.
