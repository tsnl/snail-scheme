# Last Mile

Rosa’s crew has one reel and a street permit that expires at dusk. Take the sedan north to pick her up, turn right past a parked delivery van, and brake on the gold tape facing the red plate. On Rosa’s cue, fire the paint marker. Turn left and park by the editor’s table. Rosa carries the reel the last few metres. The streets stay open after the shoot. [Play Last Mile](../play/last-mile/)

## Play locally

From the repository root, run the following inside `nix-shell`. Open the local address printed by the server in a WebGPU-capable browser.

```sh
make last-mile
python3 -m http.server 0 --bind 127.0.0.1 --directory build/src/apps/last-mile/main
```

| Control | On foot | In the sedan |
| --- | --- | --- |
| W / S or ↑ / ↓ | Walk forward or backward | Accelerate or brake. Hold S through a stop to reverse. |
| A / D or ← / → | Turn | Steer |
| E | Walk to the driver’s door. Press again to cancel the approach. | Exit when stopped with a clear driver’s door |
| B | | Brake and hold at zero, in either direction |
| Number keys / T | Choose a numbered reply / continue speaking | Choose a numbered reply / continue speaking |
| Space or primary mouse button | Fire the paint marker straight ahead | Fire in the car’s heading |
| P or Escape | Pause or resume | Pause or resume |

Replies can also be clicked or focused with Tab and selected with Enter. The gold diamond on the map marks the current objective. The speedometer switches to a distance and bearing readout beside the on-foot indicator. The page saves in this browser every five seconds and when hidden. R starts another take after delivery.

## Build it in six steps

| Step | Smallest piece | What to try |
| --- | --- | --- |
| 1. Walk one block | Give a body a position, velocity and heading. On each 50 ms tick sweep it against the street footprints. Render the same footprints as buildings. | Walk diagonally into a corner. A wall takes away the normal velocity and leaves the tangent. |
| 2. Put someone on the sidewalk | Let distance traveled advance a gait phase. Blend authored idle and walk clips. Layer the paint-marker action on the spine and sample a full-body driving clip at the wheel. Give each pedestrian two waypoints and a timed flee state. | Fire near a pedestrian. Watch them leave their path and return. Walking into a wall should stop the stride. |
| 3. Borrow a car model | Advance the rear axle and yaw with the kinematic bicycle equations. Compute the chassis center from wheelbase and sweep its footprint before accepting the motion. Add pedals and a speed limit in the game. | Turn right in forward and reverse. Try steering while stationary or leaving the vehicle at speed. |
| 4. Shoot one take | Describe the stages and cues with `define-quest`. Measure stopping position, heading and paint contact in the simulation. | Fire too soon, then stop on the tape. The gate stays up until a fresh hit on cue. |
| 5. Light the same poses you draw | Assemble the street, glTF car, figures and props once. Pose the car and skin the figures, refit the triangle hierarchy and draw the G-buffer and traced lights from those vertices. | Park across a sunlit crossing. The car casts a shadow, and its old position admits light after it moves. |
| 6. Run it as a browser app | Give the page the event, GPU, DOM, fetch and storage capabilities. Latch a tap until the next simulation tick. Keep GPU handles and input out of the save. | Tap E between ticks, pause and reload. The mission, car and pedestrians resume together. |

The CPU physics, bicycle step, door interaction, pedestrian behavior, humanoid animation, quests, dialogue and procedural scenery live in `src/snail/shell/game/`. The mission, controls, street and concrete `Renderer` live in `src/apps/last-mile/`. The app composes those pieces by calling them directly. A second mission can reuse the simulation and lighting without adopting a scene graph or a general behavior planner.

## What the language makes easy

A rider stores a body on the pavement, a tick while crossing the sill, or a seat in the car. Both actors use the same door code. The seat and the approach point rotate with the chassis. A blocked passenger can wait while the driver repositions. Deriving serialization for the world carries the pedestrian’s intent and gait through a reload. The headless mission fixture calls the same input-to-tick function as the browser. Typed Pod records also give Scheme and WGSL an agreed buffer layout.

Time and GPU resource lifetime still need explicit attention. A quick press can fall between two simulation ticks. A posed mesh needs a previous position for the denoiser, and a moved vertex needs new ancestor bounds before a shadow ray can see it. A successful compilation proves none of those contracts. The browser input test and a GPU test that moves a blocker between two rays cover them. Testing with the software adapter also makes the cost of tracing at canvas resolution visible.

## Write a quest

Import `(snail shell game quest)`. Declare a stage type and an event type. Each row matches those two values and produces the next stage. A stage or event can carry ordinary typed data.

```scheme
(enum Job (Waiting) (Collecting ((have I64))) (Paid) (Cancelled))
(enum Notice (Hire) (Crate ((count I64))) (Quit))
(define-quest (advance Job Notice)
  ((Waiting) (Hire) (Collecting 0))
  ((Collecting n) (Crate k) (if (>= (+ n k) 3) (Paid) (Collecting (+ n k))))
  ((Collecting _) (Quit) (Cancelled)))
```

Call `(advance stage observations)` once per tick. It takes the first applicable event in list order, tries rows in source order, and retains the stage if none match. An event seen before its stage is active expires that tick. In Last Mile this makes a shot fired while parking different from a shot fired after Rosa calls action. The game saves the current stage alongside the riders and car.

## Write dialogue in Ink

Edit `src/apps/last-mile/rosa.ink` in a text editor or Inky. Put choice text in square brackets to show it only on the choice, and divert to a named knot for its answer. An `id` tag gives the saved passage a stable name when an author reorders choices.

```ink
-> curb

=== curb ===
Rosa: Ready? # id:curb
+ [Tell me the turn.] -> turn
+ [Let's roll.] -> END

=== turn ===
Rosa: First right, before the van. # id:turn
-> END
```

Inside the project’s Nix shell, set `INKLECATE` to the reference compiler executable and bake the conversation. Version 1.2.1 produces Ink format 21. Use `--check` to compare the current source with the committed library. `make test-ink` also exercises rejected stories. Building and playing the game uses that library. [Inklecate releases](https://github.com/inkle/ink/releases/tag/v1.2.1)

```sh
export INKLECATE=/path/to/inklecate
scripts/bake-ink src/apps/last-mile/rosa.ink src/apps/last-mile/lines.sld
```

The producer compiles the Ink, then plays every reachable sequence of player choices with the reference runtime. It writes the spoken lines, ordered replies and destinations as a Snail `Dialogue`. Inside the game, `open-dialogue` returns a cursor. `spoken` reads the current line, `continue-dialogue` advances it, and `replies` exposes choices after the last line. `answer-dialogue` takes a zero-based reply index. A finished conversation returns `None`. Only the passage ID and line index go into the save. Without an explicit ID the producer uses the choice path, so keep tagged IDs for released conversations.

Baking suits finite, deterministic conversations whose inputs are the player’s replies. The producer rejects random and shuffle instructions, external calls, and a tagged passage revisited along its own choice path. Its default limit is 256 explored turns, including separate histories leading to the same passage. An untagged loop reaches this limit. Keep simulation facts in the quest and select the appropriate conversation at its start.

Full Ink supports live variables, external bindings and serializing the interpreter’s state as JSON. The reference runtime is C# and inkjs would introduce a JavaScript application dependency. A future integration for stories that need these features could put the existing Rust interpreter behind a scalar service with a story handle, a choice operation and a save boundary. That would require building and testing the service on both browser and native hosts. [Ink runtime guide](https://github.com/inkle/ink/blob/master/Documentation/RunningYourInk.md) · [Rust Ink interpreter](https://github.com/bladecoder/blade-ink-rs)

## Assets and the next increment

The sedan and delivery van share their original glTF palette. The van is a placed static model with a matching curbside footprint. Replace `public/sedan.glb` and its referenced textures, then match the model’s forward axis, size and wheelbase in the renderer and game. The vehicle update is adapted from PythonRobotics. The app’s `CREDITS.txt` includes the upstream license. [Kenney Car Kit](https://kenney.nl/assets/car-kit) · [PythonRobotics vehicle update](https://github.com/AtsushiSakai/PythonRobotics/blob/master/PathTracking/stanley_control/stanley_control.py)

The player, Rosa and both pedestrians share `public/crew.glb`, a CC0 mesh from Kenney’s Animated Characters Bundle. Each keeps its own saved gait. The renderer advances the walk in proportion to distance, including when a pedestrian flees. The marker clip controls the spine and its descendants, so an actor can shoot mid-stride. Entering the sedan blends the whole body into the driving clip. To replace the asset, set its height, forward axis, spine, hand nodes and four clip names in `(apps last-mile render)`. The engine takes ordinary glTF joints, weights and clips. [Skinning and the tracer](../graphics/tracer.md#skinned-animation)

This slice assumes level streets, rigid wheels and swept rectangular obstacles. A foot planted on a curb or a hand holding a steering wheel would give a concrete test for inverse kinematics. For lighting, measure the refit and tracing passes separately on the target browser GPU before adding traffic or extending the district.
