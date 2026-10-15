# A game that reloads while you play

In this model example, a game node owns the world and retained graphics
resources. A [native GUI runtime](../platforms/native-gui.md) delivers input and
redraw events. A temporary frame node computes the next world and drabing
commands from a snapshot.

## Artifacts and state

`build.scm` assembles the game artifact, a replaceable frame artifact, and assets
such as cooked GLB and shader code. The same pure frame rules can be exercised
by a test script and compiled into the frame artifact.

The game keeps meshes and textures. Messages to a frame contain the world
snapshot and input; replies contain the next world and small drabing commands.
The nodes' message contract defines the meaning and lifetime of any resource
names. It does not transfer raw GPU pointers or mutable Scheme objects.

## One frame at a time

The game spawns a frame node and owns its lifetime. It connects to that node and
requests a frame computation. Only one frame computation is in flight:

1. Give the frame node a copy of the world and queued input.
2. Keep collecting new input in a separate queue while the frame runs.
3. Accept the returned world and commands; use the new input in the next frame.
4. Hang up and stop the temporary frame node when its work is complete.

The event thread keeps running. A result cannot overwrite newly queued input,
though a slow frame delays that input's visible effect. The workflow/session
also bounds queued input. More concurrent simulation requires an explicit rule
for accepting or merging results.

Stopping a frame releases its temporary state. The game retains graphics
resources until the GPU has finished using them. Closing a connection cannot
free resources that already dispatched work still needs.

## Replacing the frame artifact

A completed build publishes a new frame artifact. The game validates its
contract before choosing it for the next spawn. A frame already running keeps
the artifact version it started with. A failed build leaves the previous output
available, and a rejected replacement leaves the running game using its previous
version.

A changed world schema requires migration or a reset chosen by the game. Node
isolation alone does not supply migration, a frame-time guarantee, or control
over the collector. Those guarantees belong to the selected runtime and the
application's workflow/session.
