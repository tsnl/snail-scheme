# If You’re Going That Way

From the shop awnings on Lantern Row you can follow the paved lane north, cross Mill Bridge and climb to Foxglove Farm. The first dirt turning on the left climbs through the orchard. The right-hand turn leads past Reedwater, where a footbridge takes you around the millpond. Moss follows the courier by bicycle and on foot. Your position, parked bicycle, distance and settings are saved in this browser. [Ride through Willowbank](../play/iygtw/).

![A cyclist and Moss on the approach to Mill Bridge in morning mist](willowbank.jpg)

| Action | Control |
| --- | --- |
| Get off or mount a nearby bicycle | F or the bicycle button |
| Walk relative to the camera | W, A, S, D or the arrow keys |
| Run | Hold Shift while walking |
| Pedal and steer | W, A, D or the arrow keys |
| Coast | Release the pedals |
| Brake and hold on a hill | Space |
| Stop, then walk the bicycle backwards | Hold S or Down |
| Get back on after a fall | E, once the rider settles |
| Ring the bell | B |
| Orbit the rider and zoom | Click the view, move the mouse, scroll |
| Centre the camera | C |
| Set the time of day | L or the light button |
| Change resolution | Q or the resolution button |
| Open or close the pause menu | P, Esc, or the pause button |
| Return to Lantern Row with Moss | R or **Reset to Lantern Row** in the pause menu |

Willowbank’s rideable survey spans 176 × 176 metres. The roadster has a 1.08 m wheelbase. Holding a steering key gradually turns the bars. At higher speeds the same input makes a wider turn, and the rider banks into it. Each metre travelled under power advances the crank and both feet together. At a start or on a climb, the rider rises, shifts weight forward and puts more force into the downstroke. The rider settles back when coasting and puts a foot down at a stop. The camera follows independently of the lean. The game presents up to 30 frames per second and interpolates between 20 ms physics steps.

Press F while moving and the courier brakes before stepping off on the open side of the saddle. Walk away and the bicycle stays put. Turn the camera to choose a new direction, hold Shift to run, and approach the bicycle to ride again. The controller in `(snail shell game locomotion)` sweeps the walker against the village obstacles and advances the stride by the distance actually covered.

The shallow puddles on Lantern Row are visible from the shop. Take the first dirt turn to the left and ride a figure eight to see the two tyre paths diverge. On soft ground each pass presses a groove, up to 3.5 cm deep. The wheels settle into existing grooves. Turning through a pool pushes water aside and sends a ripple out from the tyre. Runoff seeps back over seconds, and undisturbed tracks soften over roughly three minutes of riding time. Pause freezes that clock. A reload or a return to Lantern Row keeps the marked ground.

A glancing collision can turn the front wheel along a fence. A sharper stop throws the rider forward against the bars. A hard, square hit separates the rider from the bicycle. The torso tumbles under gravity, the limbs draw in, and the bicycle tips onto its side. Once the rider settles, E gets them back on beside the obstacle. Hold S or Down to walk clear, including uphill.

The pause menu gives three independent choices. Resolution ranges from 240p to 1080p, samples per pixel can be 1, 2 or 4, and paths can bounce 1–8 times. A fresh ride starts at 900p, 2 samples and 2 bounces. The selected resolution fits the canvas and the GPU’s ray-buffer limit. The choices stay fixed while riding and survive resetting to Lantern Row and reloading the page. An existing ride from the larger survey keeps its distance and places the cyclist at the corresponding spot on the shorter lanes.

Morning mist gathers near the creek. Sunlight passing through the leaves lights the air between their shadows. The lens focuses at the rider's actual distance from the camera, including when a wall pushes the camera closer. Try the bridge in morning light and the orchard at golden hour.

To measure the ride, serve a build, then run `node benches/iygtw/ride.mjs http://127.0.0.1:4193/ 900p 2 2` from the repository root in the development shell. The arguments after the URL are resolution, samples per pixel and bounce depth. The benchmark pedals three routes in a fresh native Vulkan Chromium profile at a 1920×1080 viewport. It reports the actual render dimensions, completed frames per second and 95th-percentile frame interval.

To time individual GPU pipelines in the same ride, add `--profile`. The benchmark reads WebGPU timestamps and sums every invocation of each pipeline within each completed frame. It reports median and 95th-percentile milliseconds for both the individual pipelines and their feature totals across frames. `timedWork` sums GPU pass time. Presentation intervals also include pacing and queue delays. Run the ride once with profiling off for a frame-budget comparison. Profiling opens new compute passes at pipeline changes and adds asynchronous query readback.

```sh
node benches/iygtw/ride.mjs http://127.0.0.1:4193/ 900p 2 2 --profile
```

On an RTX 5090 with NVIDIA driver 595.104.02, Chromium Vulkan, a 1920×1080 viewport and a 1600×900 render at 2 spp, these are milliseconds of GPU work per riding frame. Ray traversal includes both continuation and shadow rays.

| Route | Raster p50 | Ray traversal p50 | Total p50, 2 bounces | Total p95, 2 bounces | Total p50, 1 bounce |
| --- | ---: | ---: | ---: | ---: | ---: |
| Lantern Row | 0.20 | 10.73 | 15.55 | 17.12 | 9.91 |
| Mill Bridge | 0.18 | 10.40 | 14.98 | 15.97 | 9.73 |
| Orchard | 0.17 | 6.65 | 10.84 | 11.42 | 9.06 |

With instrumentation off, all three routes averaged 30 completed frames per second. The 95th-percentile interval between completed frames was 34.4–35.8 ms. The game caps presentation at 30 fps.

## Editing Willowbank

Open `src/apps/iygtw/art/Willowbank.blend` in Blender to edit the level. The collections group the village, water, roads, farms and distant hills. The road meshes supply the visible surface and wheel contact. Their survey curves record the alignments. Edit the mesh when changing the riding surface. A mesh tagged `iy_surface` supplies the surface type and wheel height. The exporter projects the `iy_solid` and `iy_fence` meshes into obstacle spans. The `iy_waymark` empties name places, and marker zero sets the starting position.

`Roadster.blend` contains the weighted bicycle and courier. The seated and standing pedal actions share a crank phase. Two steering actions keep the hands on the grips in either posture. The rig includes bracing, tumbling and walking the bicycle backwards. On foot, the idle, walk, run and two saddle-crossing poses animate the courier independently of the parked bicycle. With the file open in Blender, `src/blender/bake_roadster.py` rebuilds these actions from the rest rig.

The courier's head, eyes and continuous forearm and hand meshes use Blender Studio’s CC0 Human Base Meshes. The jacket, cap, hair and post bag are authored for Willowbank. To rebuild the character mesh in Blender, run `src/blender/dress_courier.py` with the roadster file open and the extracted human base mesh file after `--`. The arm fit uses the shared wrist loop of the sculpt and three articulated joints per digit. The seated and standing actions orient the knuckles along the swept grips. Run the action bake after redressing the character. The finished roadster packs all its textures. The rider's skin takes its scattering weight from Blender's Principled BSDF.

The editable hollows in the level’s **Road drainage** collection set the pool centres and radii. In the level file, `src/blender/plant_verges.py` replants the sedges, dock, foxgloves, hazel and ash canopy along the lanes. `Moss.blend` contains the dog's rig and trot. Run `src/blender/groom_moss.py` with the dog open to comb its coat. The dog and courier keep an opaque undercoat or hairline under skinned, alpha-tested ribbons. Each ribbon carries a painted comb of individual fibers. Both actors share the path tracer's skinning pass.

After an art edit, run `make iygtw-art` with Blender on the path. Check in the source and its exports together. A normal `make iygtw` uses the checked-in exports. The browser downloads the nine files in `main.resources` with progress, caches them locally and reuses them on subsequent visits. Tree sprays, grass blades, gravel, plaster, timber and other material scans are credited in the game. [Willowbank art credits](../play/iygtw/CREDITS.txt).
