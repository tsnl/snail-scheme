# TODO

Completed work lives in git history. Keep this list to open items, and keep
proposed language changes separate from implemented behavior.

## Language

- [ ] Complex numbers, mutable pairs and shared-structure labels in the
  dynamic Scheme libraries, which the port left out.
- [ ] Grow `(scheme compiler)` toward R7RS: macros, quasiquote, vectors and
  strings in full, and calls into typed Lofi code through `type-convert`.
- [ ] Literals at a generic numeric type, through the `Num` evidence.
- [ ] Superclasses, so `(Ord T)` can imply an equality class.
- [ ] Explicit overflow-checking arithmetic.
- [ ] Mutually recursive local functions.

## Compiler

- [ ] Decision trees for `match` with many cases, and nullable references for
  `Option`-shaped enums.
- [ ] Source locations in emitted Wasm.

## Siegework

### Restoring removed functionality

Use the rewritten implementation as the base and keep its simplifications.
This is a roadmap for manual implementation, not a description of current
support. The renderer, UI and asset items also include capabilities to grow.
The pre-rewrite visual reference is commit `92f38fd1`, particularly Siegework's
`view.sld`, `hud.sld` and `style.css` at that revision.

- [ ] Restore the bright grass, teal surroundings, violet ore, golden roofs
  and warm cream HUD palette. Keep the current meshes; recolor them rather
  than replacing the models.
- [ ] Restore the 30-degree orthographic camera and 2:1 dimetric ground grid.
  Keep projection, picking and screen-direction panning consistent, and make
  the projection explicit in the shared rendering API.
- [ ] Restore the compact edge dock, circular readouts/buttons and contextual
  actions below the main controls, using the same touch-friendly arrangement
  on desktop and mobile. Preserve the old visual character with a simpler UI.
- [ ] Grow a reusable Elm-style UI library: immutable view descriptions and
  typed events around `init`, `update` and `view`. The client should describe
  a DOM root containing a dedicated 3D canvas and ordinary DOM HUD elements.
- [ ] Grow a small, typed Three.js-style rendering library with composable
  geometry, materials, meshes, transforms, cameras and scenes. Preserve
  instancing and retained batches; keep game-specific rules out of the host.
- [ ] Evaluate reusable asset packaging/embedding and optional GLB loading
  as separate capabilities. Keep the present procedural models until authored
  assets justify a loader, with resource ownership explicit at the host boundary.
- [ ] Add state-preserving hot reload. A stable host/runtime should own the
  state lifetime across replaceable modules, with an explicit snapshot and
  compatibility/migration boundary. Restore and test the candidate before
  replacing working code; rebuild presentation caches and retain the previous
  code/state on failure. Do not serialize the model on every display frame.
- [ ] Review and restore desired gameplay functionality after hands-on
  playtesting; decide the feature list separately from this visual/API work.
- [ ] Retire or supersede PR #359: it fixes a terrain-list builder removed by
  the rewrite and must not be merged unchanged. Carry forward its full-map
  reveal stack-safety regression intent where relevant to the replacement.
