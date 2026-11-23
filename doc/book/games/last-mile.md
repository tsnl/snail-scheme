# Last Mile

Rosa’s crew has a street permit and one take left. Pick up the picture car, drive north on Mercer Street, shoot the red prop plate with a paint marker and bring the film can to the editor’s table. The streets stay open after the shoot. [Play Last Mile](../play/last-mile/)

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
| E | Enter the car or hand over the can at the table | Exit when stopped with a clear door |
| Space or primary mouse button | Fire the paint marker straight ahead | Fire in the car’s heading |
| P or Escape | Pause or resume | Pause or resume |

The gold diamond on the map marks the current objective. The speedometer switches to a distance and bearing readout beside the on-foot indicator. The page saves in this browser every five seconds and when hidden. R starts another take after delivery.

## Build it in six steps

| Step | Smallest piece | What to try |
| --- | --- | --- |
| 1. Walk one block | Give a body a position, velocity and heading. On each 50 ms tick sweep it against the street footprints. Render the same footprints as buildings. | Walk diagonally into a corner. A wall takes away the normal velocity and leaves the tangent. |
| 2. Put someone on the sidewalk | Let distance traveled advance a gait phase. Blend authored idle and walk clips. Layer the paint-marker action on the spine and sample a full-body driving clip at the wheel. Give each pedestrian two waypoints and a timed flee state. | Fire near a pedestrian. Watch them leave their path and return. Walking into a wall should stop the stride. |
| 3. Borrow a car model | Advance the rear axle and yaw with the kinematic bicycle equations. Compute the chassis center from wheelbase and sweep its footprint before accepting the motion. Add pedals and a speed limit in the game. | Turn right in forward and reverse. Try steering while stationary or leaving the vehicle at speed. |
| 4. Shoot one take | Express pickup, action, delivery and wrap as four mission states. Clip the paint shot to the nearest wall before testing the prop. | Hit the plate, leave the car and deliver the can. Save and restore partway through the drive. |
| 5. Light the same poses you draw | Assemble the street, glTF car, figures and props once. Pose the car and skin the figures, refit the triangle hierarchy and draw the G-buffer and traced lights from those vertices. | Park across a sunlit crossing. The car casts a shadow, and its old position admits light after it moves. |
| 6. Run it as a browser app | Give the page the event, GPU, DOM, fetch and storage capabilities. Latch a tap until the next simulation tick. Keep GPU handles and input out of the save. | Tap E between ticks, pause and reload. The mission, car and pedestrians resume together. |

The CPU physics, bicycle step, pedestrian behavior, humanoid animation and procedural scenery live in `src/snail/shell/game/`. The mission, controls, street and concrete `Renderer` live in `src/apps/last-mile/`. The app composes those pieces by calling them directly. A second mission can reuse the simulation and lighting without adopting a scene graph or a general behavior planner.

## What the language makes easy

A seat is either an on-foot body or the driver of the one stored car. Pattern matching makes the ownership of the player’s pose visible. Deriving serialization for the world carries the pedestrian’s intent and gait through a reload. The headless mission fixture calls the same input-to-tick function as the browser. Typed Pod records also give Scheme and WGSL an agreed buffer layout.

Time and GPU resource lifetime still need explicit attention. A quick press can fall between two simulation ticks. A posed mesh needs a previous position for the denoiser, and a moved vertex needs new ancestor bounds before a shadow ray can see it. A successful compilation proves none of those contracts. The browser input test and a GPU test that moves a blocker between two rays cover them. Testing with the software adapter also makes the cost of tracing at canvas resolution visible.

## Assets and the next increment

The sedan uses its original glTF wheel and body nodes and external palette. Replace `public/sedan.glb` and its referenced textures, then match the model’s forward axis, size and wheelbase in the renderer and game. The vehicle update is adapted from PythonRobotics. The app’s `CREDITS.txt` includes the upstream license. [Kenney Car Kit](https://kenney.nl/assets/car-kit) · [PythonRobotics vehicle update](https://github.com/AtsushiSakai/PythonRobotics/blob/master/PathTracking/stanley_control/stanley_control.py)

The player and both pedestrians share `public/crew.glb`, a CC0 mesh from Kenney’s Animated Characters Bundle. Each keeps its own saved gait. The renderer advances the walk in proportion to distance, including when a pedestrian flees. The marker clip controls the spine and its descendants, so an actor can shoot mid-stride. Entering the sedan blends the whole body into the driving clip. To replace the asset, set its height, forward axis, spine and four clip names in `(apps last-mile render)`. The engine takes ordinary glTF joints, weights and clips. [Skinning and the tracer](../graphics/tracer.md#skinned-animation)

This slice assumes level streets, rigid wheels and swept rectangular obstacles. The next driving increment worth testing is a longer route with a tight turn, a braking zone and a parked obstacle. A foot planted on a curb or a hand holding a steering wheel would give a concrete test for inverse kinematics. For lighting, measure the refit and tracing passes separately on the target browser GPU before adding traffic or extending the district.
