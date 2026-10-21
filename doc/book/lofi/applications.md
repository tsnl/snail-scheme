# Application model

`(lofi app)` defines interactive applications as total functions over a
state:

| Function | Meaning |
| --- | --- |
| `init : seed width height -> State` | The first state. |
| `update : State Input -> State` | Applies one input: a key, a pointer, a HUD button, the screen's size, or the milliseconds since the last display frame. |
| `view : State -> Frame` | A frame of mesh instances under a camera and a light. |
| `hud : State -> (List Panel)` | The HUD's panels of labels, buttons and dials. |
| `save : State -> Save` | What to store; it may be a record of how to rebuild the state. |
| `restore : Save -> State` | The state again. |

`define-application` exposes these to the browser host. The host forwards
raw input, reports elapsed time before each display frame, draws each
frame with WebGPU and stores the serialized save in the browser. Because
time is input, an application decides how time passes, and can stop it at
any frame.

Frames are built from batches of instances. The host keeps a batch until
its version changes, so a still scene costs nothing to send; each
instance also carries where it was, and the host moves it toward where it
is as the frame's motion goes from 0 to 1. Batches may be solid,
translucent, or revealed within a growing disc. The camera is perspective
or orthographic.

HUD panels stack in columns from the screen's corners or appear as dialogs.
The host keeps elements by key, so hover and focus survive updates, and
reports presses and hovering back as input. `recognize` turns raw pointer
events into points, taps, drags and pinches.

## Live reload

`lofi serve APP-DIRECTORY` builds an application, serves it at
`http://127.0.0.1:8000/`, and builds it again whenever the application's
directory, the standard library or the browser host changes. Each page it
serves swaps in the new module without reloading: the running module's
save is restored into the new one, so the state survives while every
function changes. That is the contract a page reload already relies on, so
an application whose save is a journal, as Siegework's is, replays the
journal under the new code.

- A failed build is shown over the page, and the old module keeps running.
- A module that cannot restore the save, because the Save type changed or
  restoring panics, leaves the old module running and offers to start
  over.
- A module that traps stops its clock with the state from before the
  update that trapped, and the next build resumes from that state.
- A changed style sheet is fetched again; a changed page or host script
  reloads the page after saving.

`lofi watch SOURCE` is the same loop for a program: it builds and runs the
program again whenever its sources change, stopping a run still in
progress once a new build succeeds.

[Siegework](../games/siegework.md) is the complete example.
