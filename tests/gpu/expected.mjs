// What tests/gpu prints after its format, as tests/browser/gpu.mjs checks
// it on the page and tests/gpu.mjs on Node: the page's own lines, then the
// lines of the checks both run ((gpu-test device)), then the page's file
// read. The values are SwiftShader's, the software device of headless
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
  'scene: 230 3 3 255 230 3 3 255 153 153 153 255 153 153 153 255',
  // The same light through Hable's curve and sRGB encoding: the grey
  // tile's 0.6 is 159, as the curve computed by hand gives.
  'filmic: 186 0 0 255 186 0 0 255 159 159 159 255 159 159 159 255',
  'squares: 1 4 9 16 10000',
  'planes: -0.25 -0.0 16777217 -1 0',
  // An exclusive scan of i mod 3 over three levels of tiles, checked at
  // every index; a stable sort of 5,000 keys; and splats: red at the
  // left, green over red at the center, blue at the right, faint green
  // above, until turning the red one's transform stands it up.
  'scan: 0 0 1 3 510 511 513 262143 299998 all',
  'sort: paired sorted stable permutation',
  'splats: 96 2 0 255 40 209 0 255 7 0 225 255 0 2 0 255',
  'turned: 0 2 0 255 40 209 0 255 0 0 225 255 96 2 0 255',
  // A compiled tensor program computes each of its sinks as the CPU
  // evaluates them, and Adam fits a line in 1,000 runs of another.
  'tensor: 11 sinks agree',
  'fitted: from above 1 to below 1e-4, b 1.0',
  // The differentiable splat renderer: a pixel blended as the paper
  // does, every param's gradient of L1 and D-SSIM against central
  // differences, and Adam fitting a cloud to a rendered one.
  'splat forward: blends as the paper does',
  'splat gradients: means agree, scales agree, rotations agree, opacities agree, dc agree, degree1 agree, degree2 agree, degree3 agree',
  'splat fit: the loss falls by more than four times',
];

// The page's own first bytes, and the server's 404 for a file it lacks.
export const fetchedLine = 'fetched: <!doctype 404 fetching missing.bin';

const slack = {scene: 2, filmic: 2, splats: 2, turned: 2, planes: 1e-3};

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
