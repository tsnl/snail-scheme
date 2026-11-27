# Game simulation and stories

These libraries run on the CPU. An application chooses a fixed timestep and owns the game world, input, renderer and save.

## Frame pacing

`(snail shell game display)` gives a browser game a refresh divisor and a frame-time graph.
Construct a `GameDisplay` from its `Clock` and `PageStorage`. Advance the simulation on
each frame event. `(display-frame! display ms paused redraw)` returns the elapsed
milliseconds for the camera when a draw is due. A divisor of three draws on every
third animation callback. A resize or graphics change can request one immediate draw
even while paused. Call `presented!` just after submitting the frame to the canvas and
`interrupt-display!` when the page is hidden. The optional HUD shows submitted FPS
and the longest interval in each quarter second over the last eight seconds.
The guide marks 16.7 ms. The vertical scale reaches 100 ms and the numeric peak
continues above it.

## Quests

`(snail shell game quest)` exports `define-quest`. Supply the stage and event types and one row per transition. The generated function takes a stage and an ordered list of observations. It returns the result of the first applicable transition, or the original stage. Payloads bind in ordinary patterns, so a counted goal can carry its current count. A tick advances at most one stage. The application decides which observations the world supplies. [Quest example](https://github.com/tsnl/snail-scheme/blob/main/tests/programs/game-quest.sld) · [Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/quest.sld)

## Dialogue

`(snail shell game dialogue)` reads a `Dialogue` made of named passages, lines and ordered replies. Each reply names its destination. Construct the dialogue directly in an application library. The game saves a `Cursor` containing the passage ID and line index. `open-dialogue`, `continue-dialogue` and `answer-dialogue` return an optional cursor. An out-of-range answer keeps the current cursor. [Dialogue example](https://github.com/tsnl/snail-scheme/blob/main/tests/programs/game-dialogue.sld) · [Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/dialogue.sld)

## Movement and boarding

`(snail shell game terrain)` reads GRD1 and GRD2 contact meshes. GRD2 also records the number of obstacle strips per metre and the upper surface of each solid span. `nearby-columns` exposes those heights to a 3D body. `ground-height` evaluates the triangle under an XZ position, `ground-slope` samples a grade across a given span, and `nearby-solids` supplies local building and trunk footprints for a sweep. A cell index bounds the triangle search. Ground and kerbs support movement, while obstacles restrict it. [Terrain file layout](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/terrain.sld)

`(snail shell game physics)` sweeps a disc through axis-aligned footprints, slides a walking body along a wall, and measures clear paths and shot distances. `(snail shell game vehicle)` integrates a rear-axle bicycle model and checks its rotated chassis extents. Coordinates are metres in the XZ plane. Heading zero faces north along −Z and positive angles turn east. [Physics](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/physics.sld) · [Vehicle](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/vehicle.sld) A caller keeps one `DriverControls`, advances it with `adjust-driver!` each tick, and passes its pedal and wheel to `road-speed` and `road-steering`. These functions model power-limited acceleration, braking, road grade and a shared longitudinal/lateral grip limit. `bicycle-step` integrates the resulting signed speed and steering angle. For a bicycle with a separate rider, `bicycle-contact` sweeps both wheel positions, slides along the contacting faces and returns the velocity lost to the obstacle. The rider can use that vector as an impulse.

`(snail shell game rigid-body)` gives each body a 3D centre, unit quaternion, world-space linear and angular momentum, inverse mass and body-space inverse inertia. Construct a box with `box-body`. Apply gravity with `accelerate!` and an impact with `apply-impulse!` at a world-space point. Rotate local spheres into world space with `world-balls`. Generate sphere-pair and plane contacts, pass them together to `solve-contacts!`, then advance every body with `integrate!`. Each solver sweep accumulates a normal impulse and bounds the tangential impulse by Coulomb friction. The caller chooses the step size and sweep count. Fast objects can cross thin geometry between discrete steps. [Sequential impulses](https://box2d.org/files/ErinCatto_SequentialImpulses_GDC2006.pdf)

`(snail shell game chassis)` puts these bodies on a road. `road-chassis` aligns a car with the grade. `step-cars!` drives Rapier's four raycast wheels, with steering at the front axle. Each car's wheels sample its own local road plane. All cars share building footprints and sloped, solid bodywork. Gravity and off-centre contacts can pitch, roll or overturn them. `chassis-body` projects the result onto the street map for routing and boarding. [Rapier vehicle controller](https://docs.rs/rapier3d-f64/0.36.1/rapier3d_f64/control/struct.DynamicRayCastVehicleController.html)

`step-traffic!` includes the nearby people supplied by `walker-step`. A moving car's contact switches a walker to rigid-body motion. Snail owns the poses and world-space momenta. Rust builds one Rapier world per fleet tick and writes the results into the same Snail bodies. Wheel and contact caches last for the four substeps of a game tick. Reloading a shift or interleaving two shifts requires only their respective saved bodies. A browser game can call `warm-traffic!` once during loading. It steps a copy of the cab against a pedestrian so the first contact path is ready when play begins.

`(snail shell game boarding)` advances a saved `Rider` toward a driver or passenger door, across the sill and into the seat. The car’s placement determines both anchors. An approach uses the four expanded chassis corners to find a clear way around either end. The game holds the car while `crossing?` is true and may reposition it if a waiting rider’s door is blocked. `rider-body` and `seat-weight` locate the actor and blend the seated pose from the same progress. [Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/boarding.sld)

## Roads and local traffic

`(snail shell game atlas)` opens compressed map bands already read through `Resources`. An `Area` holds the current sector and its eight neighbours. Call `focus-area!` as the player moves. The area keeps one eighth of a sector as a margin across its centre’s edge so that a switchback can cross the seam without rebuilding twice. `prepare-area!` takes a forecast position and inflates at most one missing sector per call. When ready, it returns the candidate area in drawing order. The current area advances only through `focus-area!`, which reuses completed work and handles teleports immediately. Overlapping sectors keep their decoded contact data, mesh and signs. `area-height`, `area-slope` and `area-solids` query the same geometry the renderer uses.

`(snail shell game roads)` reads a directed junction and street-name table. `road-route` uses A* with straight-line distance as its lower bound. `follow-edge` places a body a given distance along an edge and a lateral distance from its centre. `(snail shell game traffic)` uses the outgoing edges for its drivers and chooses clear sidewalk segments for pedestrian patrols. `replacement-motor` checks the snapped lane position against the cab’s actual direction of travel, its stopping space and nearby bodies. It returns an option so a caller can keep an existing car when every candidate is unsuitable. The application supplies the nearby people and vehicles, traffic density and time step. [Road graph](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/roads.sld)

## Following a moving body

`(snail shell game chase)` advances a camera focus in world space. Pass `follow` the previous `Chase` (or `(None)` for the first frame), a target position, heading in radians, elapsed seconds and initial boom length. The focus follows a critically damped spring, the heading takes the short arc, and a displacement of 24 metres or more resets the rig at the target. The caller places the camera using that focus and boom. [Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/chase.sld)

## Actors and scenery

`(snail shell game humanoid)` blends idle, stride, upper-body action and riding clips on a generic rig. Distance walked advances stride. `(snail shell game pedestrian)` follows waypoints and resumes them after fleeing a nearby disturbance. [Humanoid](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/humanoid.sld) · [Pedestrian](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/pedestrian.sld)

`(snail shell game drawing)` places rigid parts relative to a model. `(snail shell game figure)` assembles figures from these parts. `(snail shell game scenery)` places the same shapes into a glTF scene and builds matrices for moving them. [Drawing](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/drawing.sld) · [Figure](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/figure.sld) · [Scenery](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/scenery.sld)
