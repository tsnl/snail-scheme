# Game simulation and stories

These libraries run on the CPU. An application chooses a fixed timestep and owns the game world, input, renderer and save. Last Mile uses the same tick in the browser and in its driving fixture. [Build a playable mission](../games/last-mile.md)

## Quests

`(snail shell game quest)` exports `define-quest`. Supply the stage and event types and one row per transition. The generated function takes a stage and an ordered list of observations. It returns the result of the first applicable transition, or the original stage. Payloads bind in ordinary patterns, so a counted goal can carry its current count. A tick advances at most one stage. The application decides which observations the world supplies. [Quest example](../games/last-mile.md#write-a-quest) · [Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/quest.sld)

## Dialogue

`(snail shell game dialogue)` reads a `Dialogue` made of named passages, lines and ordered replies. Each reply names its destination. The game saves a `Cursor` containing the passage ID and line index. Import a baked Ink library or construct a dialogue directly. `open-dialogue`, `continue-dialogue` and `answer-dialogue` return an optional cursor. An out-of-range answer keeps the current cursor. [Ink authoring](../games/last-mile.md#write-dialogue-in-ink) · [Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/dialogue.sld)

## Movement and boarding

`(snail shell game physics)` sweeps a disc through axis-aligned footprints, slides a walking body along a wall, and measures clear paths and shot distances. `(snail shell game vehicle)` integrates a rear-axle bicycle model and checks its rotated chassis extents. Coordinates are metres in the XZ plane. Heading zero faces north along −Z and positive angles turn east. [Physics](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/physics.sld) · [Vehicle](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/vehicle.sld)

`(snail shell game boarding)` advances a saved `Rider` toward a driver or passenger door, across the sill and into the seat. The car’s placement determines both anchors. An approach uses the four expanded chassis corners to find a clear way around either end. The game holds the car while `crossing?` is true and may reposition it if a waiting rider’s door is blocked. `rider-body` and `seat-weight` locate the actor and blend the seated pose from the same progress. [Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/boarding.sld)

## Actors and scenery

`(snail shell game humanoid)` blends idle, stride, upper-body action and riding clips on a generic rig. Distance walked advances stride. `(snail shell game pedestrian)` follows waypoints and resumes them after fleeing a nearby disturbance. [Humanoid](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/humanoid.sld) · [Pedestrian](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/pedestrian.sld)

`(snail shell game drawing)` places rigid parts relative to a model. `(snail shell game figure)` assembles figures from these parts. `(snail shell game scenery)` places the same shapes into a glTF scene and builds matrices for moving them. [Drawing](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/drawing.sld) · [Figure](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/figure.sld) · [Scenery](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/game/scenery.sld)
