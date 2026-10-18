# TODO

## Language documentation

Continue improving the existing [book](doc/book/SUMMARY.md) and
[formal summary](doc/book/lofi/reference.md) incrementally. Keep descriptions
of implemented behavior separate from proposed language changes.

- [x] Specify and implement rank-one `All` with an optional `requires` clause:
  rigid variables and assumptions while checking a definition, fresh inference
  holes or explicit type arguments at each use. Retain `=>` as input compatibility.
- [ ] Specify fixed-arity Lofi functions and explicit argument packing for
  Scheme variadic procedures before removing the documented rest forms.

## Deferred: Ott formalization and proofs

Formalization and proof tooling are deferred. They are not prerequisites for
landing documentation improvements.

- [ ] Revisit Ott for the grammar and named inference rules, starting with a
  small fragment of the existing reference.
- [ ] Generate the corresponding book sections from that source once the
  workflow is established, keeping explanations and examples alongside the rules.
- [ ] Choose a proof assistant and check its integration with Ott. Generating
  definitions does not itself prove properties of the language or compiler.
- [ ] Add machine-checked proofs incrementally, beginning with variable scope,
  name categories, application arity, and closed instance heads. State each
  fragment's assumptions and proved properties before expanding its coverage.

The [Agda experiment in draft PR #325](https://github.com/tsnl/snail-scheme/pull/325)
is parked for reference. It does not replace the book or commit the project to
Agda as its eventual proof assistant.

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
- [x] Persistent difficulty indicator inside the next-wave ring.
- [x] Gradually mixed strength ranks with distinctive enemy silhouettes.
- [x] Tower progression: Lv1 sight, Lv2 artillery, Lv3 cart station replacing gun.
- [x] Workers use cart stations and rails for fast personal/cargo travel.
- [x] Wheel/pinch zoom and regular/orbital toggle preserving look-at center.
- [x] Repeated focused simplification followed by a final Astra xhigh code review.
- [x] Confirm Siegework build CI and consolidate the stack into mega-PR #334.
      The PR state records CI and landing status.

World9 checkpoint: 104 application integration checks and Chromium pointer,
controller, touch, save/reopen, camera and GPU cleanup checks passed. Further
source edits remain unchecked until compiled and exercised.

## Final integration checklist

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
- [x] Same explicit select-then-action interface for touch and desktop, including
      extractor confirmation, repeated hub hiring and click-away dismissal.
- [x] Restart confirmation pauses, with cancellation restoring the prior pause.
- [x] Smoke on damage and red/white attack notifications with clickable live views.
- [x] Soft fragment-level fog reveal and continuous display-rate unit/freight motion.
- [x] Verify the final exact artifact in Chromium, publish on 4212 and attach screenshots.
- [x] Reconcile current main and include the Siegework build in CI.
      Merge only after the PR checks pass.

World10 model checkpoint: 123 integration checks plus 31,494 stress commands,
1,026 exact save round-trips and 156 close encounters passed. The original
reported invalid-transition crash remains unreproduced; retained diagnostics
are for obtaining a concrete reproduction if it recurs. The final exact product build, 123 integration checks and 19 real Chromium
hosting/storage sections now pass; current evidence is in
[VALIDATION.md](apps/siegework/VALIDATION.md).