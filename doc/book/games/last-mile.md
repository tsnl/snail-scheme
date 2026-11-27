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
| B or Space | Brake and hold the cab at the curb. Passengers board and leave automatically. |
| E | Leave a stopped cab or approach the driver’s door on foot. |
| Mouse / C | Click to capture and look around, or right-drag. C recentres the driving camera. Escape releases the mouse. |
| M | Switch between the local minimap and the city map. While waiting, click a cab stand or use [ and ] to select one, then Enter to start there with a stopped cab. |
| L | Advance six hours during the shift. One real second normally advances the clock one game minute. |
| P / Pause | Open the pause menu. Save or load a shift, resume driving, recover the cab, restart or change settings. |

A glowing 5.5-metre ring marks the active stop on the street. It clears when the receipt is paid and follows the next dispatch, including consecutive pickups at the same curb. The local minimap draws street widths, buildings, names, parks and water as vectors from the nine resident sectors. The route and cab marker stay sharp as the map follows the cab. M opens a separate citywide overview. The gold diamond marks the next curb. The traced line and turn instruction follow the directed street graph. The meter charges a fictional $4 flag drop and $0.50 for every 160 metres driven with the passenger aboard. Opening the page starts a fresh shift. In the pause menu, **Save game** records the time, riders, traffic, cab position, receipts, earnings and settings in this browser. **Load game** resumes the last saved shift, including saves from earlier versions. You can restart a shift and still load the old one until you choose **Save game** again.

The cab renders at the canvas’s full pixel resolution. By default it draws on every browser animation frame. **Refresh divisor** in the pause menu accepts a positive whole number. On a 60 Hz display, 2 targets 30 FPS. **FPS and frame times** toggles the eight-second graph in the upper right. The browser remembers these display preferences across shifts. The pause menu redraws the street when the size or MSAA setting changes. In the pause menu choose 1× or 4× MSAA. The dashboard shows the actual dimensions and sample count. Moving headlights and brake lights follow the model sockets. Stationary lights are grouped by street cell, and the sky and shadows follow the shift clock. The city reuses its facade textures while preparing upcoming sectors. [Forward rendering](../graphics/rasterizer.md).

**Recover cab** seats the driver in a stopped cab on a nearby clear lane. The current fare, meter, earnings and shift clock carry over. **Restart game** asks for confirmation and starts a new shift at Hyde and Lombard with Rosa waiting and zero earnings. Graphics and mouse settings carry over to the new game. Saves from the earlier driving model resume with their fare and street population.

## Measure a shift

`./snail-scheme run --release --target node benches/last-mile/shift.scm`
drives a six-car shift on the published streets. It repeats the same sequence of
throttle, brake and reverse-steering inputs for 240 ticks. After warming up, it
prints nine elapsed times in nanoseconds. Divide each by 240 to get time per
tick. The measurement includes traffic AI, pedestrians and Rapier. Map loading,
rendering and save I/O are outside the timed loop.

## Build the city

1. **Start with surveyed geometry.** The baker reads the San Francisco OpenStreetMap extract and clips it to the city shoreline and its road connections. It keeps shared OSM node IDs for junctions, one-way directions and street names. Building heights and road widths use tags where available and estimates elsewhere. The coastline bounds the playable mainland, Treasure Island and Yerba Buena Island. The Golden Gate Bridge extends to its north landing. The offshore Farallones have no connecting streets. [OpenStreetMap extract](https://download.bbbike.org/osm/bbbike/SanFrancisco/) · [DataSF shoreline](https://data.sfgov.org/resource/txuc-3kzm.geojson)
2. **Make wheels and pixels agree.** Sample the USGS bare-earth elevation every 32 metres. Clip road, kerb, pavement and land polygons against each grid triangle. The same centimetre-quantized vertices supply CPU ground heights and GPU surfaces. The 128-metre distant relief uses the same triangle diagonal. Each shared corner is lowered by the largest overestimate in its neighbouring cells, with another 25 centimetres for clearance. Bevelled 16-centimetre kerbs let the cab climb onto the pavement. Mapped building footprints and trees supply nearby obstacles. Bridge decks use approximate grades above the water. Each mapped lake gets a single surface elevation sampled inside its shoreline. The bay and ocean meet sea level. The surface has one height per location, so vertically stacked roads share a driving surface. [USGS 3DEP](https://www.usgs.gov/3d-elevation-program) The chase camera clips its ray against the resident obstacle spans and carries the nearest distance across sectors.
3. **Separate downloading from drawing.** Six packed files hold the whole city’s compressed sectors. At startup the client requests `resources.json` and shows byte progress for the map, road graph, scenery, vehicles and textures. Each sector covers 256 metres square. The cab’s velocity predicts the next sector up to 125 metres ahead. New neighbours inflate from memory one per event, then the new neighbourhood uploads its vertex and index buffers. The old neighbourhood remains visible until the cab crosses the margin and the new scene is ready. When a turn changes the forecast, the resident outer sectors still supply the road during preparation. Both scenes share their material images and packed skin bindings. Cache Storage keeps each verified object by digest. The next shift reuses those bytes, including city files saved by older builds in IndexedDB. Only a changed or evicted object needs another download.
4. **Give the road network two jobs.** A* computes routes for the minimap and GPS. Traffic uses the same directed exits to choose its next road, keeps to the right and yields to nearby vehicles and pedestrians. Five nearby cars and six sidewalk pedestrians make up the local population. The city does not simulate a distant vehicle for every road.
5. **Put activity at the curb.** A storefront starts as a mapped shop, café or other business. The baker projects its frontage toward a road, places windows and an awning, and keeps the name for the street HUD. The bake distinguishes timber, stucco, brick, industrial and curtain-wall façades using mapped use, height and footprint, with deterministic fallbacks. Narrow residential façades can have projecting bays and pitched roofs. Simplified footprints carry the skyline beyond the detailed sectors. It also places mapped trees, benches, lamps and bins. Additional litter and furniture use a stable seed and vary with street class. Rebuilding the same inputs and revisiting the block reproduce their positions.
6. **Run a shift.** Each 50 ms tick advances pedestrians, boarding, the meter and the clock. Four 12.5 ms Rapier steps advance all six cars together in the same Wasm module as the Snail game. Four raycast wheels follow each car’s local grade. Bodywork contacts walls, pedestrians and other cars, so a glancing impact can push the cab sideways and turn it. The shift saves the resulting poses and momenta. Traffic steers back toward its route after an impact. Keyboard steering and throttle take time to reach full travel. Engine pull falls with speed, air and rolling resistance slow a coasting car, and braking leaves less tyre grip for cornering. The brake holds the cab on a grade. A passenger walking out triggers one payment. Each display frame interpolates the vehicles and poses the actors. The shift clock moves the directional light and selects the sky and its filtered environment. Cascaded shadow maps cover the street. Lamps, headlights and brake lights use the forward renderer’s local lights. The camera independently follows the cab with a damped spring. A vehicle can knock a walker off their feet. Their body responds to subsequent contacts and gravity until they get up. [Game libraries](../libraries/games.md) · [Forward rendering](../graphics/rasterizer.md)

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

## Swap the art

The browser catalog publishes the cab, civilian sedan, shared palette, facades and rig from `src/apps/last-mile/main.resources/`. Keep their filenames and local axes when swapping a model. The credits in the app identify the asset and map sources.
