// Compare the forward HDR target with a 128-spp Cycles reference, or benchmark
// resident-scene throughput with --timing=OPTIX (or another Cycles backend).
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {parseArgs} from 'node:util';
import {createCanvas, GlobalFonts} from '@napi-rs/canvas';

const {values: {village, timing, size}, positionals} = parseArgs({allowPositionals: true,
  options: {village: {type: 'boolean'}, timing: {type: 'string'}, size: {type: 'string'}}});
assert.ok(positionals.length <= 1, 'Expected at most one output directory');
if (timing) assert.ok(['CPU', 'CUDA', 'OPTIX', 'HIP', 'METAL', 'ONEAPI'].includes(timing), 'Unknown Cycles backend');
if (size) assert.ok(timing && /^[1-9]\d*x[1-9]\d*$/.test(size) && size.split('x').every(n => Number(n) <= 16384),
  '--size=WIDTHxHEIGHT applies to timing runs, with sides up to 16384');
const out = resolve(positionals[0] ?? ('build/cycles-' + (village ? 'village' : 'reference') +
  (timing ? '-timing-' + timing.toLowerCase() + (size ? '-' + size : '') : '')));
mkdirSync(out, {recursive: true});
execFileSync(process.env.BLENDER ?? 'blender', ['-noaudio', '-b', '--factory-startup', '--python-exit-code', '1',
  '--python', 'benches/render/cycles.py', '--', out, ...(village ? ['village'] : []),
  ...(timing ? ['--timing=' + timing] : []), ...(size ? ['--size=' + size] : [])],
  {stdio: 'inherit', env: {...process.env, ALSOFT_DRIVERS: 'null'}});
const shot = JSON.parse(readFileSync(join(out, 'shot.json')));
const {width, height, samples, bounces} = shot;
const cameraArgs = ['scene=' + shot.scene, 'environment=' + join(out, 'studio.hdr'),
  'eye=' + shot.eye, 'target=' + shot.target, 'width=' + width, 'height=' + height,
  'msaa=4', 'exposure=1'];
if (timing) {
  const {create} = await import('webgpu');
  const dawn = create(['disable-dawn-features=timestamp_quantization']);
  const adapter = await dawn.requestAdapter() ?? await dawn.requestAdapter({powerPreference: 'high-performance'});
  assert.ok(adapter, 'No WebGPU adapter');
  const {vendor, device, description, architecture, isFallbackAdapter} = adapter.info;
  if (timing !== 'CPU') assert.ok(!isFallbackAdapter, 'WebGPU selected a software adapter');
  const prefix = join(out, 'snail-timing');
  execFileSync('./snail-scheme', ['run', '--release', '--target', 'node', 'tools/render.scm',
    ...cameraArgs, 'timing=' + prefix, 'linear=' + prefix + '.rgba32f'], {stdio: 'inherit'});
  const snail = {...JSON.parse(readFileSync(prefix + '.json')), device: {vendor, device, description, architecture, isFallbackAdapter}};
  const cycles = shot.timing;
  function summarize(result) {
    assert.equal(result.renderSeconds.length, 5);
    assert.ok(result.renderSeconds.every(t => Number.isFinite(t) && t > 0));
    result.medianSeconds = [...result.renderSeconds].sort((a, b) => a - b)[2];
    result.millionOutputPixelsPerSecond = width * height / (1e6 * result.medianSeconds);
  }
  summarize(snail); summarize(cycles);
  const film = compareTimedFilms(image('snail-timing.rgba32f'), image('cycles-timing.rgba32f'));
  const result = {scene: shot.scene, blender: shot.blender, width, height, samples, bounces, snail, cycles, film,
    snailOverCycles: snail.medianSeconds / cycles.medianSeconds};
  const report = JSON.stringify(result, null, 2);
  writeFileSync(join(out, 'timing.json'), report + '\n');
  console.log(report);
  process.exit(0);
}
execFileSync('./snail-scheme', ['run', '--release', '--target', 'node', 'tools/render.scm',
  ...cameraArgs, 'output=' + join(out, 'forward.png'), 'linear=' + join(out, 'forward.rgba32f')], {stdio: 'inherit'});

function image(path) {
  const data = readFileSync(join(out, path));
  assert.equal(data.length, width * height * 16);
  const floats = new Float32Array(data.buffer, data.byteOffset, data.length / 4);
  assert.ok(floats.every(Number.isFinite), 'Non-finite radiance in ' + path);
  return floats;
}
// Validate the last timed frames after the timers stop. Only RGB carries light.
function compareTimedFilms(a, b) {
  let sa = 0, sb = 0, square = 0, aMin = Infinity, aMax = -Infinity, bMin = Infinity, bMax = -Infinity;
  for (let i = 0; i < a.length; i += 4) for (let c = 0; c < 3; c++) {
    const x = a[i + c], y = b[i + c];
    aMin = Math.min(aMin, x); aMax = Math.max(aMax, x);
    bMin = Math.min(bMin, y); bMax = Math.max(bMax, y);
    sa += x; sb += y; square += (x - y) ** 2;
  }
  assert.ok(aMax - aMin > 0.01 && bMax - bMin > 0.01 && sa > 0 && sb > 0, 'Empty benchmark film');
  const n = width * height * 3;
  return {snailMean: sa / n, cyclesMean: sb / n, biasPercent: 100 * (sa / sb - 1), rmse: Math.sqrt(square / n)};
}
const s0 = image('forward.rgba32f'), c0 = image('cycles-0.rgba32f'), c1 = image('cycles-128.rgba32f');
const rounded = value => +value.toPrecision(5);
function score(x0, y0, x1, y1) {
  let snail = 0, cycles = 0, square = 0, cyclesNoise = 0;
  const n = (x1 - x0) * (y1 - y0) * 3;
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
    for (let c = 0; c < 3; c++) {
      const i = (y * width + x) * 4 + c, reference = (c0[i] + c1[i]) * .5;
      snail += s0[i]; cycles += reference;
      square += (s0[i] - reference) ** 2;
      cyclesNoise += (c0[i] - c1[i]) ** 2;
    }
  }
  assert.ok(cycles > 0 && snail > 0, 'Expected nonzero radiance');
  return {pixels: n / 3, snailMean: rounded(snail / n), cyclesMean: rounded(cycles / n),
    biasPercent: rounded(100 * (snail / cycles - 1)), rmse: rounded(Math.sqrt(square / n)),
    cyclesNoiseRmse: rounded(Math.sqrt(cyclesNoise / (2 * n)))};
}
function preview() {
  const canvas = createCanvas(width * 3, height + 27), ctx = canvas.getContext('2d');
  ctx.fillStyle = '#17191d'; ctx.fillRect(0, 0, canvas.width, canvas.height);
  try {
    const font = execFileSync('fc-match', ['-f', '%{file}', 'sans-serif'], {encoding: 'utf8'});
    GlobalFonts.registerFromPath(font, 'Benchmark');
  } catch {} // Hosts with system font discovery need no explicit face.
  ctx.font = '14px Benchmark, sans-serif'; ctx.fillStyle = '#ffffff';
  const srgb = v => 255 * (v < 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055);
  for (const [j, title] of ['Snail · 4× MSAA', 'Cycles · 128 spp', 'Absolute difference ×4'].entries()) {
    ctx.fillText(title, j * width + 7, 18);
    const patch = ctx.createImageData(width, height);
    for (let i = 0; i < s0.length; i += 4) {
      for (let c = 0; c < 3; c++)
        patch.data[i+c] = srgb([s0[i+c], c0[i+c], 4 * Math.abs(s0[i+c] - c0[i+c])][j]);
      patch.data[i + 3] = 255;
    }
    ctx.putImageData(patch, j * width, 27);
  }
  writeFileSync(join(out, 'comparison.png'), canvas.toBuffer('image/png'));
}

const regions = village ? {image: [0, 0, width, height], ashCanopy: [75, 35, 104, 52],
  lane: [112, 122, 137, 138], shopfront: [30, 69, 44, 81]} : {image: [0, 0, width, height], backWall: [124, 45, 148, 61], clay: [93, 83, 102, 94],
  metal: [151, 84, 160, 97], floor: [114, 140, 137, 151]};
const metrics = Object.fromEntries(Object.entries(regions).map(([name, rect]) => [name, score(...rect)]));
if (!village) {
  // Calibration catches exposure, radiance units and vertical flips. The
  // directly visible sky is exactly 1/8. The emitter's red channel is 6.
  for (const data of [s0, c0, c1]) {
    const red = (x, y) => data[(y * width + x) * 4];
    assert.ok(Math.abs(red(235, 50) - 0.125) < 0.002, 'Sky radiance calibration failed');
    assert.ok(Math.abs(red(100, 10) - 6) < 0.12, 'Mesh emitter radiance calibration failed');
  }
}
const report = JSON.stringify({shot, metrics}, null, 2);
writeFileSync(join(out, 'metrics.json'), report + '\n');
preview();
console.log(report);
