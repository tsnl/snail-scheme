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

[Siegework](../games/siegework.md) is the complete example.
