# Game simulation and stories

These libraries run on the CPU. An application chooses a fixed timestep and owns the game world, input, renderer and save. Last Mile uses the same tick in the browser and in its driving fixture. [Drive a taxi in San Francisco](../games/last-mile.md)

## Quests

`(snail shell game quest)` exports `define-quest`. Supply the stage and event types and one row per transition. The generated function takes a stage and an ordered list of observations. It returns the result of the first applicable transition, or the original stage. Payloads bind in ordinary patterns, so a counted goal can carry its current count. A tick advances at most one stage. The application decides which observations the world supplies. [Quest example](../games/last-mile.md#write-a-quest) · [Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/quest.sld)

## Dialogue

`(snail shell game dialogue)` reads a `Dialogue` made of named passages, lines and ordered replies. Each reply names its destination. The game saves a `Cursor` containing the passage ID and line index. Import a baked Ink library or construct a dialogue directly. `open-dialogue`, `continue-dialogue` and `answer-dialogue` return an optional cursor. An out-of-range answer keeps the current cursor. [Ink authoring](../games/last-mile.md#write-dialogue-in-ink) · [Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/dialogue.sld)

## Compiling Ink

`(snail shell game ink)` supplies `ink-library` for a `generate-library` recipe. Its first filename is the Ink entry point. Each additional filename links a source used by an `INCLUDE`. At build time the producer calls inklecate and returns a library exporting `conversation` as a `Dialogue`. Games import that generated library. `make test-ink` builds an independent project, edits its story and included knot, and exercises failed generations. [Recipe and authoring example](../games/last-mile.md#write-dialogue-in-ink) · [Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/ink.sld)

## Movement and boarding

`(snail shell game terrain)` reads a GRD1 contact mesh. `ground-height` evaluates the triangle under an XZ position, `ground-slope` samples a grade across a given span, and `nearby-solids` supplies local building and trunk footprints for a sweep. A cell index bounds the triangle search. Ground and kerbs support movement, while obstacles restrict it. [City data](../games/last-mile.md#build-the-city)

`(snail shell game physics)` sweeps a disc through axis-aligned footprints, slides a walking body along a wall, and measures clear paths and shot distances. `(snail shell game vehicle)` integrates a rear-axle bicycle model and checks its rotated chassis extents. Coordinates are metres in the XZ plane. Heading zero faces north along −Z and positive angles turn east. [Physics](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/physics.sld) · [Vehicle](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/vehicle.sld) A caller keeps one `DriverControls`, advances it with `adjust-driver!` each tick, and passes its pedal and wheel to `road-speed` and `road-steering`. These functions model power-limited acceleration, braking, road grade and a shared longitudinal/lateral grip limit. `bicycle-step` integrates the resulting signed speed and steering angle.

`(snail shell game boarding)` advances a saved `Rider` toward a driver or passenger door, across the sill and into the seat. The car’s placement determines both anchors. An approach uses the four expanded chassis corners to find a clear way around either end. The game holds the car while `crossing?` is true and may reposition it if a waiting rider’s door is blocked. `rider-body` and `seat-weight` locate the actor and blend the seated pose from the same progress. [Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/boarding.sld)

## Roads and local traffic

`(snail shell game atlas)` opens compressed map bands already read through `Resources`. An `Area` holds the current sector and its eight neighbours. Call `focus-area!` as the player moves. The area keeps one eighth of a sector as a margin across its centre’s edge so that a switchback can cross the seam without rebuilding twice. Overlapping sectors keep their decoded contact data, mesh and signs. `area-height`, `area-slope` and `area-solids` query the same geometry the renderer uses.

`(snail shell game roads)` reads a directed junction and street-name table. `road-route` uses A* with straight-line distance as its lower bound. `follow-edge` places a body a given distance along an edge and a lateral distance from its centre. `(snail shell game traffic)` uses the outgoing edges for its drivers and chooses clear sidewalk segments for pedestrian patrols. The application supplies the nearby people and vehicles, traffic density and time step. [City and navigation](../games/last-mile.md#build-the-city)

## Actors and scenery

`(snail shell game humanoid)` blends idle, stride, upper-body action and riding clips on a generic rig. Distance walked advances stride. `(snail shell game pedestrian)` follows waypoints and resumes them after fleeing a nearby disturbance. [Humanoid](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/humanoid.sld) · [Pedestrian](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/pedestrian.sld)

`(snail shell game drawing)` places rigid parts relative to a model. `(snail shell game figure)` assembles figures from these parts. `(snail shell game scenery)` places the same shapes into a glTF scene and builds matrices for moving them. [Drawing](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/drawing.sld) · [Figure](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/figure.sld) · [Scenery](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/scenery.sld)
