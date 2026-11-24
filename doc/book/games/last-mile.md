# Last Mile Taxi

Rosa is waiting at Hyde and Lombard. Ease forward in the yellow cab and hold the brake beside her. When she sits down, the meter starts and the GPS draws a route to Jones Street. Follow Lombard through the switchbacks and stop at the destination with a clear passenger door. Her receipt adds to the shift total and dispatch offers another fare. The sixteen cab stands take you from the waterfront to Ocean Beach, Lake Merced, Bayview and the islands. [Play Last Mile Taxi](../play/last-mile/)

## Play locally

Run these commands from the repository root inside `nix-shell`. Open the printed local address in a WebGPU-capable browser.

```sh
make last-mile
python3 -m http.server 4193 --bind 127.0.0.1 --directory build/src/apps/last-mile/main
```

| Control | Action |
| --- | --- |
| W / S or ↑ / ↓ | Accelerate, brake and reverse. On foot, move forward or backward. |
| A / D or ← / → | Steer. With the mouse captured, A / D strafe on foot. |
| B | Brake and hold the cab at the curb. Passengers board and leave automatically. |
| E | Leave a stopped cab or approach the driver’s door on foot. |
| Mouse / C | Click to capture and look around, or right-drag. C recentres the driving camera. Escape releases the mouse. |
| M | Switch between the local minimap and the city map. While waiting, click a cab stand or use [ and ] to select one, then Enter to start there with a stopped cab. |
| L | Advance six hours while waiting for a passenger. One real second normally advances the clock one game minute. |
| 1–9 / T | Choose a dialogue reply or continue. Replies also accept mouse and keyboard focus. |
| Q | Switch between adaptive and high tracing resolution. The taximeter shows the active dimensions. |
| P | Pause and resume. |

The local minimap draws street widths, buildings, names, parks and water as vectors from the nine resident sectors. The route and cab marker stay sharp as the map follows the cab. M opens a separate citywide overview. The gold diamond marks the next curb. The traced line and turn instruction follow the directed street graph. The meter charges a fictional $4 flag drop and $0.50 for every 160 metres driven with the passenger aboard. Time, riders, traffic, cab position, dialogue, receipts and the shift total save in the browser. The taxi game uses its own save slot.

Adaptive tracing starts at 720 lines, can ease down to 480 and rises to 1080 when frames allow. High targets the canvas up to 1920 × 1080. Both modes fit the ray queues to the storage-buffer binding size granted by WebGPU. Smaller canvases retain their own dimensions. Map and instrument text use browser resolution in both modes.

## Build the city

1. **Start with surveyed geometry.** The baker reads the San Francisco OpenStreetMap extract and clips it to the city shoreline and its road connections. It keeps shared OSM node IDs for junctions, one-way directions and street names. Building heights and road widths use tags where available and estimates elsewhere. The coastline bounds the playable mainland, Treasure Island and Yerba Buena Island. The Golden Gate Bridge extends to its north landing. The offshore Farallones have no connecting streets. [OpenStreetMap extract](https://download.bbbike.org/osm/bbbike/SanFrancisco/) · [DataSF shoreline](https://data.sfgov.org/resource/txuc-3kzm.geojson)
2. **Make wheels and pixels agree.** Sample the USGS bare-earth elevation every 32 metres. Clip road, kerb, pavement and land polygons against each grid triangle. The same centimetre-quantized vertices supply CPU ground heights and GPU surfaces. Bevelled 16-centimetre kerbs let the cab climb onto the pavement. Mapped building footprints and trees supply nearby obstacles. Bridge decks use approximate grades above the water. Each mapped lake gets a single surface elevation sampled inside its shoreline. The bay and ocean meet sea level. The surface has one height per location, so vertically stacked roads share a driving surface. [USGS 3DEP](https://www.usgs.gov/3d-elevation-program)
3. **Separate downloading from drawing.** Six linked objects hold the whole city’s compressed sectors. The client reads them at startup, together with the road graph, overview and distant scenery. Each sector covers 256 metres square. Moving into the next sector retains the overlap and unpacks its new neighbours from memory. The renderer rebuilds its detailed scene around the cab and keeps coarse relief and the skyline visible in the distance. IndexedDB stores linked files by content digest, including the glTF rigs and textures. A change to one object only invalidates that object.
4. **Give the road network two jobs.** A* computes routes for the minimap and GPS. Traffic uses the same directed exits to choose its next road, keeps to the right and yields to nearby vehicles and pedestrians. Five nearby cars and six sidewalk pedestrians make up the local population. The city does not simulate a distant vehicle for every road.
5. **Put activity at the curb.** A storefront starts as a mapped shop, café or other business. The baker projects its frontage toward a road, places windows and an awning, and keeps the name for the street HUD. It also places mapped trees, benches, lamps and bins. Additional litter and furniture use a stable seed and vary with street class. Rebuilding the same inputs and revisiting the block reproduce their positions.
6. **Run a shift.** A 50 ms simulation tick advances the bicycle model, sidewalk walkers, boarding, meter and clock. Keyboard steering and throttle take time to reach full travel. Engine pull falls with speed, air and rolling resistance slow a coasting car, and braking leaves less tyre grip for cornering. The brake holds the cab on a grade. A passenger walking out triggers one payment. The next frame interpolates bodies, poses the skinned actors, refits moving geometry and traces the new sun or moon through the scene. The sky supplies a warm directional sun during the day and a dim moon at night. Shop signs and street lamps have emissive materials. Water reflects the sky and geometry with animated wave normals on a fixed surface. The tracer samples indirect light over two bounces, denoises with SVGF and applies FXAA. The cab has no headlight beams. [Game libraries](../libraries/games.md) · [Moving geometry](../graphics/tracer.md#moving-geometry)

### Rebuild from source data

The app ships the baked result. To author another snapshot, obtain the PBF, shoreline GeoJSON and USGS GeoTIFF named in the map credits. Pass the local filenames to the baker. Its manifest records the source hashes, counts and locations of the downloadable derived database. The map in this build has 18,053 road sections, 93,584 navigation nodes, 7,172 placed storefronts and 2,086 detailed sectors. [Credits and upstream downloads](../play/last-mile/geodata/SOURCES.txt) · [Data manifest](../play/last-mile/geodata/city.json)

```sh
nix-shell -E 'let p = import (import ./npins).nixpkgs {}; in p.mkShell { packages = [(p.python3.withPackages (s: [s.pillow s.shapely s.osmium s.numpy]))]; }' \
  --run 'python3 scripts/bake-sf.py SanFrancisco.osm.pbf shoreline.geojson USGS_13_n38w123.tif'
make last-mile
```

## Write a quest

For a job whose completion depends on several observations, use the reusable `define-quest` macro. Payloads can carry a count between stages.

```scheme
(enum Job (Waiting) (Collecting ((have I64))) (Paid) (Cancelled))
(enum Notice (Hire) (Crate ((count I64))) (Quit))
(define-quest (advance Job Notice)
  ((Waiting) (Hire) (Collecting 0))
  ((Collecting n) (Crate k) (if (>= (+ n k) 3) (Paid) (Collecting (+ n k))))
  ((Collecting _) (Quit) (Cancelled)))
```

Call `(advance stage observations)` each tick. The first applicable event wins. The taxi’s fare takes a shorter path through waiting, hired and paid. Its payment and receipt update together in the transition to paid.

## Write dialogue in Ink

Edit `src/apps/last-mile/rosa.ink` in a text editor or Inky. Brackets delimit a reply. A divert points to the next knot. The `id` tag gives the passage a stable name in saved games.

```ink
-> passenger

=== passenger ===
Rosa: Jones Street, please. # id:passenger
+ [Which turn?] -> directions
+ [Let's go.] -> END

=== directions ===
Rosa: Down Lombard, then left on Jones. # id:directions
-> END
```

The `generate-library` recipe in `src/apps/last-mile/lines.sld` calls `ink-library` on `rosa.ink` and exports the resulting `conversation`. A build runs the pinned inklecate compiler and explores choice histories to generate typed Snail data. List relative `INCLUDE` files after the entry filename in the recipe. The game saves only the passage ID and line index.

`open-dialogue` opens the cursor, `spoken` reads it, and `replies` gives the available choices. Use `answer-dialogue` with a zero-based index, or `continue-dialogue` to move past a line. This bake supports finite, deterministic conversations. It rejects external calls, random instructions and revisiting an explicitly tagged passage on its own choice path. The default budget is 256 turns. Set `(max-turns 512)` before the entry filename for a larger conversation. [Ink library](../libraries/games.md#dialogue) · [Inklecate release](https://github.com/inkle/ink/releases/tag/v1.2.1)

## Swap the art

`src/apps/last-mile/assets.sld` links the cab, civilian sedan, shared palette, facade and rig. The glTF gear and camera belong to the app’s concrete `Renderer`. To substitute a car, match its size, forward axis and wheelbase. To substitute a character, bind its height, forward axis, bones and clip names in `render.sld`. Walking distance advances the stride and boarding blends into the seated pose. The selected Kenney models and their credits ship with the app. [Art credits](../play/last-mile/CREDITS.txt) · [Skinning](../graphics/tracer.md#skinned-animation)
