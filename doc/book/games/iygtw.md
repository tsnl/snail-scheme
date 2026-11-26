# If You’re Going That Way

From the shop awnings on Lantern Row you can follow the paved lane north, cross Mill Bridge and climb to Foxglove Farm. The first dirt turning on the left climbs through the orchard. The right-hand turn leads past Reedwater, where a footbridge takes you around the millpond. Moss runs alongside the bike. Your position, distance and settings are saved in this browser. [Ride through Willowbank](../play/iygtw/).

![A cyclist and Moss on the approach to Mill Bridge in morning mist](willowbank.jpg)

| Action | Control |
| --- | --- |
| Pedal and steer | W, A, D or the arrow keys |
| Coast | Release the pedals |
| Brake and hold on a hill | Space |
| Slow down and back up | S or down arrow |
| Ring the bell | B |
| Orbit the rider and zoom | Click the view, move the mouse, scroll |
| Centre the camera | C |
| Set the time of day | L or the light button |
| Choose a fixed rendering quality | Q or the resolution button |
| Pause and resume | P or the pause button |
| Return to Lantern Row | R |

The bike has a 1.08 m wheelbase. Both wheels follow the terrain. Grass and dirt have more rolling resistance than paving. Cadence moves the pedals and legs, while distance turns the wheels even when coasting. When the bicycle slows to a standstill, the rider lowers his left foot. The camera follows a damped focus independent of the bicycle's lean. The game presents up to 30 frames per second and interpolates between 20 ms physics steps.

The game opens at a fixed 900p internal rendering budget. The 240p and 360p presets trace one path per pixel with one bounce. At 540p the path can bounce twice. At 720p, 900p and 1080p the tracer takes two samples per pixel with two bounces. The chosen budget is bounded by the canvas dimensions and the GPU's ray-buffer limit.

Morning mist gathers near the creek. Sunlight passing through the leaves lights the air between their shadows. The lens focuses at the rider's actual distance from the camera, including when a wall pushes the camera closer. Try the bridge in morning light and the orchard at golden hour.

To measure the ride, serve a build, then run `node benches/iygtw/ride.mjs http://127.0.0.1:4193/ 900p` from the repository root in the development shell. The benchmark pedals three routes in a fresh native Vulkan Chromium profile at a 1920×1080 viewport. It reports the actual render dimensions, completed frames per second and 95th-percentile frame interval.

## Editing Willowbank

Open `src/apps/iygtw/art/Willowbank.blend` in Blender to edit the level. The collections group the village, water, roads, farms and distant hills. The road meshes supply the visible surface and wheel contact. Their survey curves record the alignments. Edit the mesh when changing the riding surface. A mesh tagged `iy_surface` supplies the surface type and wheel height. The exporter projects the `iy_solid` and `iy_fence` meshes into obstacle spans. The `iy_waymark` empties name places, and marker zero sets the starting position.

`Roadster.blend` contains the weighted bicycle and character, including their separate pedal, steering, rolling and resting actions. `Moss.blend` contains the dog's rig and trot. Both actors share the path tracer's skinning pass. The rider's skin takes its scattering weight from Blender's Principled BSDF.

After an art edit, run `make iygtw-art` with Blender on the path. Check in the source and its exports together. A normal `make iygtw` uses the checked-in exports. The browser downloads the eight files in `main.resources` with progress, caches them locally and reuses them on subsequent visits. Tree sprays, grass blades, gravel, plaster, timber and other material scans are credited in the game. [Willowbank art credits](../play/iygtw/CREDITS.txt).
