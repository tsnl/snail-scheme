# If You’re Going That Way

From the shop awnings on Lantern Row you can follow the paved lane north, cross Mill Bridge and climb to Foxglove Farm. The first dirt turning on the left climbs through the orchard. The right-hand turn leads past Reedwater, where a footbridge takes you around the millpond. Moss runs alongside the bike. Your position, distance and settings are saved in this browser. [Ride through Willowbank](../play/iygtw/).

![A cyclist and Moss on the approach to Mill Bridge in morning mist](willowbank.jpg)

| Action | Control |
| --- | --- |
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

The shallow puddles on Lantern Row are visible from the shop. Take the first dirt turn to the left and ride a figure eight to see the two tyre paths diverge. On soft ground each pass presses a groove, up to 3.5 cm deep. The wheels settle into existing grooves. Turning through a pool pushes water aside and sends a ripple out from the tyre. Runoff seeps back over seconds, and undisturbed tracks soften over roughly three minutes of riding time. Pause freezes that clock. A reload or a return to Lantern Row keeps the marked ground.

A glancing collision can turn the front wheel along a fence. A sharper stop throws the rider forward against the bars. A hard, square hit separates the rider from the bicycle. The torso tumbles under gravity, the limbs draw in, and the bicycle tips onto its side. Once the rider settles, E gets them back on beside the obstacle. Hold S or Down to walk clear, including uphill.

The pause menu gives three independent choices. Resolution ranges from 240p to 1080p, samples per pixel can be 1, 2 or 4, and paths can bounce 1–8 times. A fresh ride starts at 900p, 2 samples and 2 bounces. The selected resolution fits the canvas and the GPU’s ray-buffer limit. The choices stay fixed while riding and survive resetting to Lantern Row and reloading the page. An existing ride from the larger survey keeps its distance and places the cyclist at the corresponding spot on the shorter lanes.

Morning mist gathers near the creek. Sunlight passing through the leaves lights the air between their shadows. The lens focuses at the rider's actual distance from the camera, including when a wall pushes the camera closer. Try the bridge in morning light and the orchard at golden hour.

To measure the ride, serve a build, then run `node benches/iygtw/ride.mjs http://127.0.0.1:4193/ 900p 2 2` from the repository root in the development shell. The arguments after the URL are resolution, samples per pixel and bounce depth. The benchmark pedals three routes in a fresh native Vulkan Chromium profile at a 1920×1080 viewport. It reports the actual render dimensions, completed frames per second and 95th-percentile frame interval.

## Editing Willowbank

Open `src/apps/iygtw/art/Willowbank.blend` in Blender to edit the level. The collections group the village, water, roads, farms and distant hills. The road meshes supply the visible surface and wheel contact. Their survey curves record the alignments. Edit the mesh when changing the riding surface. A mesh tagged `iy_surface` supplies the surface type and wheel height. The exporter projects the `iy_solid` and `iy_fence` meshes into obstacle spans. The `iy_waymark` empties name places, and marker zero sets the starting position.

`Roadster.blend` contains the weighted bicycle and character. The seated and standing pedal actions share a crank phase. Two steering actions place the hands on the grips at either posture. With the roadster open in Blender, `src/blender/bake_roadster.py` rebuilds these actions from the rest rig. The rig also has a bracing pose, tucked and extended fall poses, and a backward walking cycle. The editable hollows in the level’s **Road drainage** collection set the pool centres and radii. In the level file, `src/blender/plant_verges.py` replants the dedicated collection of sedges, dock, foxgloves, hazel and the ash canopy along the lanes. `Moss.blend` contains the dog's rig and trot. Both actors share the path tracer's skinning pass. The rider's skin takes its scattering weight from Blender's Principled BSDF.

After an art edit, run `make iygtw-art` with Blender on the path. Check in the source and its exports together. A normal `make iygtw` uses the checked-in exports. The browser downloads the eight files in `main.resources` with progress, caches them locally and reuses them on subsequent visits. Tree sprays, grass blades, gravel, plaster, timber and other material scans are credited in the game. [Willowbank art credits](../play/iygtw/CREDITS.txt).
