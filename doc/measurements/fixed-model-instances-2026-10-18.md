# Fixed colored model instances: 2026-10-18

Siegework now shares immutable colored vertex/index buffers between occurrences.
Tiles use colored primitive meshes. Buildings, workers, freight and enemies use
composite models baked once during module initialization. Aimed guns remain
separate instances. A changed occurrence transfers two affine poses and its
current normal matrix; the shader interpolates the transformed endpoints.

Ordinary batches preserve node order, including coincident opaque surfaces and
transparent A/B/A sequences. The terrain explicitly permits opaque regrouping.
The bridge keys primitive colors by material values, scopes prototype identities
to their Wasm instance, and retains only prototypes referenced by the completed
frame. The renderer similarly releases unused GPU meshes. Neither cache keeps a
history of all models ever presented.

## Paired method

The baseline is immutable source checkpoint `679c4dd1`, including native HiDPI,
live transport, houses, compact attack notifications and decoded-snapshot caching.
Its default `-O1` build is generation `8138945b801b7eff2aeaef96`, 567,429 bytes,
SHA-256 `c62641cd75c5d1178d22897757f4e6526b82e40710c9ef9564c3806e4a56b465`.
The instanced build is generation `2ffe90d18d12b3cb9fb2dc6a`, 583,357 bytes,
SHA-256 `809d28a60d8ebecaf832d6966de3ac39e23ba0a92518773bca1ace40eb62f3db`.
Both retain World10 and the same simulation rules. The candidate also keeps Q/E
together on short mobile layouts; the measured portrait viewport has unchanged UI.

The five saved inputs are the same controlled fixtures used in the
[decoded-snapshot investigation](decoded-snapshots-2026-10-18.md): fresh, grown,
96-enemy encounter, paused encounter and encounter with three attack alerts.
The grown colony contains twelve workers, sixteen level-three towers, two mines,
four guns and sixteen freight links. These builds emit no attack inset scenes.
The fixture-file SHA-256 is recorded with the raw results.

`tests/draw3d/instance-profile.mjs` loads each package's own host and Wasm in
Node v24.19.0. Four rounds alternate package order. Each fixture/operation restores
its inputs, warms five calls, then measures twenty-five calls. This task ran no compiler or
browser checks during the timing run. Timings remain shared-host CPU
diagnostics; they do not measure IndexedDB, a physical GPU, mobile thermals or FPS.
Endpoint expansion and transfer accounting run separately from timing.

## Results

Ranges are the four round medians in milliseconds.

| Operation | Expanded baseline | Fixed instances |
| --- | ---: | ---: |
| Grown colony, tick and changing view | 18.94–19.29 | 2.57–2.71 |
| Encounter, tick and changing view | 21.37–21.99 | 7.19–7.65 |
| Encounter with alerts, tick and changing view | 21.25–22.44 | 7.22–7.64 |
| Paused encounter, tick and view | 4.58–4.76 | 4.50–4.81 |
| Encounter, retained view | 0.08–0.10 | 0.09–0.11 |
| Encounter, camera command and view | 0.12–0.14 | 0.12–0.15 |

One warmed encounter tick previously replaced 1,302,720 vertex bytes, 190,488
index bytes and 309,984 prior-position bytes. It now replaces 125,160 current
transform/normal bytes and 7,344 prior-transform bytes, with **zero mesh bytes**:
1,803,192 bytes falls to 132,504, about 93% less. These are logical payload bytes,
not GPU allocation capacities. Both packages transfer zero geometry or instance
bytes for the measured retained view and camera-only command. The changed
encounter uses 38 instance runs instead of 13 expanded batch draws; preserving
actor and transparent ordering is deliberate.

All sixty paired tick/view and camera/view steps preserve both owner snapshots
and complete UI outputs exactly. Ordered current/prior geometry endpoints and
normals match within 0.00001404; this is the expected binary32 boundary change
from transformed vertices to local vertices plus affine matrices. Regrouped
terrain preserves its colored triangle multiset at 0.001-unit rounding. Generic
pixel probes separately cover depth ties, blending, nonuniform normals, motion,
phased opacity, radial reveals and native-resolution inset views.

The retained-view and paused-tick costs are essentially unchanged. Snapshot
encoding and fresh candidate validation still run on simulation transitions.
Entity frustum culling, new batching policies and gameplay balance changes are
outside this measurement. A later bridge guard rejects copied singular bases
and subnormal normal coefficients; that additional boundary check is not part
of the recorded package pair.

The [raw record](fixed-model-instances-2026-10-18.json) includes every round,
artifact hashes, host hashes, equivalence count and separate transfer counts.
The profiling command accepts baseline/candidate `solo` paths, the fixture
directory containing `fixtures.json` and `grown-fixtures.json`, and an output
JSON path; `--verify-only` skips timing.
