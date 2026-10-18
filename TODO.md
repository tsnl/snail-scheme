# TODO

## Language documentation

Continue improving the existing [book](doc/book/SUMMARY.md) and
[formal summary](doc/book/lofi/reference.md) incrementally. Keep descriptions
of implemented behavior separate from proposed language changes.

- [x] Specify and implement rank-one `All` with an optional `requires` clause:
  rigid variables and assumptions while checking a definition, fresh inference
  holes or explicit type arguments at each use.
- [x] Remove legacy `=>` signatures and kind annotations from source, library
  builders, and transfer packets. Store schemes directly as variables,
  requirements, and an ordinary type; derive category and arity from declarations.
- [x] Make Lofi functions fixed-arity throughout source, builders, inference,
  specialization and emission. Replace collection rest functions with explicit
  list workers and hygienic packing macros.
- [ ] Specify general first-class Scheme variadic procedures and their lowering
  to fixed-arity calls. The current typed Scheme subset requires proper parameter
  lists; collection packing macros are implemented separately.

## Compiler memory use

- [ ] Measure and reduce host memory during emission of the complete Compiler
  benchmark. The [checked-type validation](benchmarks/lofi/evidence/20261018-checked-types-full57.md#separate-follow-up)
  completed checking and specialization but exceeded an 8 GiB process-group
  limit during emission with Chibi `-h64M/4G`. Distinguish retained syntax,
  checked/concrete trees and emitted Wasm before choosing a change; preserve
  the complete workload and the recorded failures.

## Deferred: Ott formalization and proofs

Formalization and proof tooling are deferred. They are not prerequisites for
landing documentation improvements.

- [ ] Review the Ott grammar and named inference rules in the draft against
  the implemented language.
- [ ] Generate the corresponding book sections from that source once the
  workflow is established, keeping explanations and examples alongside the rules.
- [ ] Review the Ott-to-Rocq build before landing the proof tooling. Generating
  definitions does not itself prove properties of the language or compiler.
- [ ] Add machine-checked proofs incrementally, beginning with variable scope,
  name categories, application arity, and closed instance heads. State each
  fragment's assumptions and proved properties before expanding its coverage.

The [Ott/Rocq experiment in draft PR #325](https://github.com/tsnl/snail-scheme/pull/325)
explores generated definitions and formation proofs. It remains separate from
the landed compiler and book; it does not prove compiler correctness.

## Siegework iteration

Checked items have passed focused real-Wasm or browser checks. Unchecked items include work in progress;
source changes alone do not count as a playable result. Keep the preview at **4212**.

## Current playtest requests

- [x] Q/E animates between 90-degree snaps, preserving orthographic projection;
      panning and picking follow its orientation. Camera, picking and Chromium input verified.
- [x] Reduce tower height so deposits behind towers remain accessible.
- [x] Clicking outside a build chooser dismisses it and acts on the new tile.
- [x] Remove the Move button and M binding.
- [x] Workers flee with shaking and sweat droplets.
- [x] Workers visibly carry ore or construction supplies, with destination markers.
- [x] An existing worker must assemble a paid new worker; production is not instant.
- [x] Towers and artillery share interchangeable 25-ore construction kits:
      one kit for a tower, two for artillery. Redirect deliveries safely.
- [x] Adding artillery to an existing tower takes a worker and an additional kit;
      keep the existing tower useful while the upgrade is pending.
- [x] About 10% of enemies may begin a mountain excavation. Enemies stop and
      visibly break rock over several seconds, permanently opening the tile.
      Other enemies route around rock and may join an existing excavation.
- [x] Distinct, much larger final boss silhouette.
- [x] Leave ordinary building construction speed unchanged for this playtest.

## World and objective

- [x] Keep the hub stationary; win by finding and destroying the nest.
- [x] Waves strengthen over time rather than ending at an eight-minute deadline.
- [x] Map is 8–16 times larger **per dimension**; bound rendering and pathfinding
      work instead of processing every tile each frame.
- [x] Randomize player spawn inside a circle near the map center.
- [x] Randomize nest position; approaching waves provide costly directional clues.
- [x] Keep seeded maps reproducible; use fresh randomness for new runs.
- [x] Add cheap walls, diverse enemy behavior, impassable water with a gentle
      shimmer, and less rectangular mountain ranges.
- [x] Three extractor levels; expensive upgrades offer a fallback to exploration.
- [x] Remove investment automation; workers retain automatic jobs and hauling.
- [x] Restrict artillery range; nearer targets take more damage.
- [x] Transparent pulsing build previews.
- [x] Worker/enemy/projectile motion interpolates at display frame rate;
      simulation and durable saves retain a fixed clock.

## Presentation and delivery

- [x] Prominent ore, worker and difficulty readouts with radial health/wave indicators.
- [x] Full-screen world rendering; pointing popups beside the selected tile,
      separate from the fixed menu. Opening them must not shift the camera.
- [x] Clearer outcomes, off-screen attack arrows, and prominent resource deposits.
- [x] Dramatic fog reveal when construction completes.
- [x] Retain geometry during panning and animation; use native HiDPI rendering.
- [x] Keep code and shaders hot-reloadable; preserve compatible saved colonies
      when client-only controls change. Protocol changes may require a page refresh.
- [x] Rebase the game stack onto Perf PR #331's compiler improvements.
- [x] Publish a playable draft PR (#334), attach a screenshot, and update port4212.
- [x] Publish the larger-world / camera-snap revision to the same PR and preview.
- [x] Run focused game, UI, persistence, and browser checks on the published artifact.

No resources are awarded for defeated enemies. Multiplayer remains deferred;
the supported game is the static client-side 3D bundle.

## Polish pass in progress

- [x] Non-scrollable control cards with visible hotkeys beside every button.
- [x] Translucent turquoise shield walls and vivid violet/indigo gemstones.
- [x] Persistent difficulty indicator inside a circular progress readout.
- [x] Gradually mixed strength ranks with distinctive enemy silhouettes.
- [x] Separate artillery and observation/logistics upgrade trees. Preserve all
      existing offensive capabilities when upgrading either structure.
- [x] Workers use cart stations and rails for fast personal/cargo travel.
- [x] Wheel/pinch zoom preserving look-at center.
- [x] Touch, mouse and pen drag the map; taps select and pinches never select.
- [x] Repeated focused simplification followed by a final Astra xhigh code review.
- [x] Confirm Siegework build CI and consolidate the stack into mega-PR #334.
      The PR state records CI and landing status.

World9 checkpoint: 104 application integration checks and Chromium pointer,
controller, touch, save/reopen, camera and GPU cleanup checks passed. Further
source edits remain unchecked until compiled and exercised.

## Final integration checklist

- [x] Give exploration a longer opening and slow wave, strength and group-size escalation.
- [x] Use one circle size for HUD controls and icon-only construction actions;
      group all controls and readouts in a vertical left/right edge strip, with
      pill-shaped panels, visible hotkeys and a left-handed setting.
- [x] Separate health from ore, enlarge the resource icon, and show counts in
      matching high-contrast labels or badges.
- [x] Quote hub repairs to the highest affordable percentage, spending only the
      ore needed or available; complete the paid work with a worker.
- [x] Allow buildings on laid tracks and intersections, retaining the rail network.
- [x] Join adjacent and diagonally adjacent shield walls; use rail-aware structure
      bases and junction meshes instead of tracks piercing solid foundations.
- [x] Use a hard, continuous reveal contour instead of a fuzzy or grid-aligned edge.
- [x] Give artillery a distinct gun silhouette.
- [x] Count down to the next difficulty increase, never to an unseen wave spawn;
      keep hidden enemy spawns out of the HUD and accessible status.
- [x] Keep New worker readily available in the edge strip and selected-hub actions.
- [x] Reserve and display a full 3×3 hub; offer explicit paid worker repairs.
- [x] Outline the combined range of active artillery on the map.
- [x] Enemies under fire pursue the attacker, with walls still blocking them.
- [x] Build with a selected brush and a local multi-cell plan. Tapping toggles a
      planned cell; Done submits orders and Cancel spends nothing. Keep rejected
      cells visible for correction and prevent overlapping submissions.
- [x] Fix lighting relative to the camera, including intermediate Q/E rotations.
- [x] Keep drag for panning and pinch for zoom; expose compact quarter-turn
      buttons directly on screen. Do not add twist rotation.
- [x] Keep mobile attack notifications separate from controls, with white-on-red
      titles, small live thumbnails and a dismiss action; inspect portrait and
      landscape layouts, and permit later attacks to alert again.
- [x] Profile representative mobile-sized simulation, view and GPU work;
      preserve native pixel density and avoid claiming an unproved thermal cause.
- [x] Add the max-dps-test using actual model facts, three-minute discovery and
      0.5 utilization; report its optimistic assumptions and finite horizon.
- [x] Spread nearby enemies across open approaches without crossing terrain or
      bypassing walls; verify crowd movement and saved-route invariants.
- [x] Exercise new orders on surveyed but currently hidden tiles, stale menus,
      observer destruction and fogged kit delivery in actual Wasm. Five checks
      pass; the reported rejected transition remains unreproduced.
- [x] Weighted worker routes account for walking versus cart travel time.
- [x] Enemies may attack a wall instead of always detouring around it.
- [x] Worker sight reveals a small radius without unbounded survey history.
- [x] Hidden construction stalls new assignments/pickup and explains why;
      existing carriers can reveal their destination while following a known route.
- [x] Physical rails remain after stations disappear; active freight ownership
      and reserved ground remain separate and checked.
- [x] First accepted order starts the clock; inspection and selection do not.
- [x] Rejecting a transition keeps the exact committed colony; retain one
      separate command/snapshot reproduction for debugging.
- [x] Restart confirmation pauses, with cancellation returning to the Pause menu.
- [x] Smoke on damage and red/white attack notifications with clickable live views.
- [x] Continuous display-rate unit/freight motion; hard reveal contour checked above.
- [x] Verify the final exact artifact in Chromium, publish on 4212 and attach screenshots.
- [x] Reconcile current main and include the Siegework build in CI.
      Merge only after the PR checks pass.

World10 model checkpoint: the compact edge-strip build passes 175 integration
checks. Earlier stress runs covered 31,494 commands, 1,026 exact save round-trips
and 156 close encounters. The original reported invalid-transition crash remains
unreproduced; retained diagnostics can capture a recurrence. Current evidence,
including the separately checked final mobile package, is recorded in
[VALIDATION.md](apps/siegework/VALIDATION.md).

## Focused menu simplification

- [x] Remove the map-scale toggle; retain wheel/pinch zoom and Q/E buttons.
- [x] Consolidate Pause, Resume, Restart and handedness into a labeled centered
      menu. Restart cancellation returns to Pause; saved paused colonies expose
      Resume. Keep unpaid plans intact and block covered gameplay controls.
- [x] Keep first-extractor guidance visible and anchor its callout beside Build.
- [x] Keep menu operations pending until save settlement, retain retry controls
      after failures and synchronize paused startup/imports without adding World
      reads to camera input.
- [x] Verify the new menu and callout in actual Wasm and Chromium at portrait
      and short landscape sizes, on both control sides.
