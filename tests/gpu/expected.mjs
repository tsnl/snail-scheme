// What tests/gpu prints after its format, as tests/browser/gpu.mjs checks
// it on the page and tests/gpu.mjs on Node: the page's own lines, then the
// lines of the checks both run ((gpu-test device)), then the page's file
// read; Node's training checks follow its device checks. The values are SwiftShader's, the software device of headless
// Chromium. A GPU may round a texel by a step, or a half float in its
// last place, so the lines `slack` names may stray that far in each
// number; every other line must be exact.
import assert from 'node:assert/strict';

export const pageLines = [
  'target: 255 0 0 255 255 0 0 255 255 0 0 255 255 0 0 255',
  'image: 255 0 0 255 0 255 0 255',
  'again: 255 0 0 255 255 0 0 255 255 0 0 255 255 0 0 255',
  'quads: 0 0 255 255 0 0 255 255 0 255 0 255 0 255 0 255',
];

export const deviceLines = [
  'moving shadows: hit open hit open / open hit hit open',
  'skinned shadows: hit open hit open / open hit hit open',
  'wide tree: 400 of 400 boxes hit, 400 of 400 gaps open',
  'reservoirs: weighted draws, capped reuse, visible and blocked light, disocclusion and full coverage',
  'decoded: 255 0 0 255 0 255 0 255',
  'scene: 230 3 3 255 230 3 3 255 153 153 153 255 153 153 153 255',
  // The same light through Hable's curve and sRGB encoding: the grey
  // tile's 0.6 is 159, as the curve computed by hand gives.
  'filmic: 186 0 0 255 186 0 0 255 159 159 159 255 159 159 159 255',
  'photographic: 216 49 49 255 216 49 49 255 194 194 194 255 194 194 194 255',
  'coastal sky: blue noon, warm sunset, cloud extinction, dark night',
  'squares: 1 4 9 16 10000',
  'water normals: 1 1 1 1',
  'planes: -0.25 -0.0 16777217 -1 0',
  'billboard: 73 stationary',
  // An exclusive scan of i mod 3 over three levels of tiles, checked at
  // every index; a stable sort of 5,000 keys; and splats: red at the
  // left, green over red at the center, blue over red's edge at the
  // right, faint green above, until turning the red one's transform
  // stands it up.
  'scan: 0 0 1 3 510 511 513 262143 299998 all',
  'sort: paired sorted stable permutation',
  'splats: 96 2 0 255 40 209 0 255 8 0 219 255 0 2 0 255',
  'turned: 0 2 0 255 40 209 0 255 0 0 219 255 96 2 0 255',
  // The same splats drawn by the training renderer, which blends in
  // floats, agree with the quads within the same slack.
  'viewed splats: 96 2 0 255 40 209 0 255 8 0 219 255 0 2 0 255',
  'viewed turned: 0 2 0 255 40 209 0 255 0 0 219 255 96 2 0 255',
  // A render pass timed on the device; a lowered tensor program computes
  // each of its sinks as the CPU evaluates them, fused or not, and is
  // profiled; and
  // Adam fits a line in 1,000 runs of another.
  'timed: a render pass between 0 and 1 seconds',
  'tensor: 28 sinks agree',
  'fused tensor: 28 sinks agree',
  'profiled: a time for each step, between 0 and 1 seconds',
  'swapped: 5 7 6 8 / 1 2 3 4 / 1 2 3 4',
  'assigned: 9',
  'bound: 2 4 6 8 / 2 3 4 5',
  'fitted: from above 1 to below 1e-4, b 1.0',
  // The differentiable splat renderer: a pixel blended as the paper
  // does, and fused SSIM's gradient against central differences.
  'splat forward: blends as the paper does, for training and for viewing',
  'shared fill: #t',
  'splat tile ranges: 0 2 2 3 3 4',
  'ssim: mean agrees, x agrees',
  // Densification clones a small gaussian, splits a large one and
  // prunes a faint one, the kept first and the new after them; with room
  // for one row, it clones and leaves the large one whole.
  'densify: live 1 1 1 1 1 0 0 0 (5), kept then cloned, two children 1.6 times smaller',
  'room: live 1 1 1 1 (4), cloned, the large one kept whole',
];

// Every param's gradient of L1 and D-SSIM against central differences,
// and Adam fitting a cloud to a rendered one.
export const trainingLines = [
  'splat gradients: means agree, scales agree, rotations agree, opacities agree, dc agree, degree1 agree, degree2 agree, degree3 agree',
  'splat fit: the loss falls by more than four times',
];

// The page's own first bytes, and the server's 404 for a file it lacks.
export const fetchedLine = 'fetched: <!doctype 404 fetching missing.bin';

const slack = {scene: 2, filmic: 2, photographic: 2, splats: 2, turned: 2, 'viewed splats': 2, 'viewed turned': 2, planes: 1e-3};

// The printed lines, each as its expected line says.
export function assertLines(printed, expected) {
  assert.equal(printed.length, expected.length, `printed:\n${printed.join('\n')}`);
  printed.forEach((line, index) => assert.ok(agrees(line, expected[index]), `printed ${line}\nexpected ${expected[index]}`));
}

function agrees(line, expected) {
  const allowed = slack[expected.slice(0, expected.indexOf(':'))] ?? 0;
  const words = line.split(' '), wanted = expected.split(' ');
  return words.length === wanted.length && words.every((word, index) => word === wanted[index]
    || Math.abs(Number(word) - Number(wanted[index])) <= allowed);
}
