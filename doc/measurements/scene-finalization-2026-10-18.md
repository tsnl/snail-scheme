# Numeric scene finalization: 2026-10-18

A mobile playtest reported progressive slowdown and heat. These measurements
identify one avoidable CPU cost; they do not establish the phone's bottleneck,
temperature, battery impact, or frame rate.

The scene bridge constructs ordinary arrays of validated numeric vertices,
indices, and previous positions. Once a batch completes, no builder can write
those arrays again. Freezing these leaves there lets the existing recursive
presentation finalizer skip them. The batch wrapper and reveal metadata still
receive the existing deep freeze. Validation, retained identities, motion,
resolution, animation scheduling, and rendering are unchanged.

## Method and evidence

The baseline was the shipped generation `f8040dec59bb7797f31cd51d`, with its
matching packaged JavaScript and 702,518-byte Wasm. A private copy changed only
numeric-array finalization. No compiler or simulation source changed between
the measured pair. Each process was limited to two CPUs, 4 GiB RAM, no swap,
and three minutes; no new game compilation was needed. Node was v24.19.0.

The bounded encounter fixture starts from the actual seed-1 reducer, then
restores a schema-10 world with 128 enemies, each carrying a 64-cell route.
The world has about 27,500 snapshot words. The three-inset case adds three
current attack alerts near the hub. All transitions and views execute the
actual compiled Scheme. Viewport: 390 by 844 logical pixels.

Four alternating baseline/candidate rounds each warm five ticks and measure
25 tick-plus-view operations. Baseline round medians were 29.44, 28.57, 29.29,
and 29.20 ms; candidate medians were 27.17, 26.73, 26.72, and 26.48 ms.
These shared-host timings are indicative, not controlled hardware benchmarks.
A repeat using the final named helper, rather than the initial inline private
overlay, produced baseline medians 31.37, 30.48, 30.26, and 30.31 ms versus
27.05, 27.07, 26.34, and 26.66 ms. Output equivalence and the avoided-work count
below also passed for that exact helper.

A separate diagnostic counted `Object.values` calls over large numeric arrays
in one changing three-inset view: **26 arrays / 333,334 scalar entries before,
zero after**. The general finalizer's CPU self samples fell from 201/1699 to
3/1520 in separate 60-operation profiles. Garbage collection remained a large
cost. Four fixtures, each advanced through six tick/view pairs, produced
identical complete presentation outputs and snapshots between the two builds;
all published geometry arrays remained frozen and rejected writes.

The bridge checks execute linked Wasm fixtures and assert frozen geometry,
mutation rejection, cached identity, motion endpoints, reveal-wrapper sharing,
empty buffers, and failed-frame cache retention. The existing main-task
zero-width reveal compatibility change was included only in the private
integration test overlay; this patch does not change reveal validation.

## Remaining costs and resource observations

On the baseline, median tick-plus-view costs were 0.31 ms for a fresh world,
18.53 ms for the busy encounter, 16.74 ms for the same encounter paused, and
29.89 ms with three attack insets. Pausing still executes the codec: the
diagnostic counted 55,211 snapshot reads and 27,550 writes per paused tick,
including replacement validation. A view reads the current and prior world.
Those costs remain. A separate compact debug artifact had similar order of
cost, but differs in UI/source and is not an isolated compiler-profile test.

A private Chromium SwiftShader session used the full native DPR of 3:
1170 by 2532 backing pixels. Resource diagnostics covered paused rendering,
paused ticks, active ticks, three visible insets, and close. They establish
software correctness and bounded resource behavior, not physical GPU speed.

- Paused rendering with the clock stopped submitted 46 animated frames in its
  six-second observation window, with no new geometry uploads, buffers,
  textures, or bindings. The renderer retained 40 buffers, about 1.17 MB of
  buffer capacity, one depth texture, and three pipelines.
- Active ticks updated geometry while retaining the same resource counts.
  Three insets raised retained buffers to 160 (about 4.72 MB) and textures to
  seven. Counts stayed steady within the observation windows; close released
  all tracked buffers and textures. This is not a long-session leak proof.
- There is no MSAA: the pipeline uses the default sample count of one.
  Persistent water/mineral pulses redraw the main view and visible insets at
  display opportunities. At DPR 3 the main target contains 2,962,440 pixels.
  The patch preserves those animations and full resolution.

Raw CPU rounds, call counts, and GPU resource snapshots are recorded in
[`scene-finalization-2026-10-18.json`](scene-finalization-2026-10-18.json).
The scoped explanation review stopped after this leaf-finalization change:
moving metadata finalization or redesigning renderer scheduling would add
unnecessary scope and would not address the measured redundant array walk.
