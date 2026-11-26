// Run from the repository root against a served game, using Chromium's Vulkan backend.
import {execFileSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {openBrowser, sleep, until} from '../../tests/browser/chromium.mjs';

const [url = 'http://127.0.0.1:4193/', preset = '1080p', samples = '1', bounces = '2'] = process.argv.slice(2);
const base = new URL(url.endsWith('/') ? url : url + '/');
execFileSync('./snail-scheme', ['run', '--target', 'node', 'benches/iygtw/checkpoints.scm'], {stdio: 'inherit'});
const browser = await openBrowser({hardware: true});

// Only a command buffer that draws to the canvas finishes a frame. Count its
// completion after all queued GPU work, including earlier compute submissions.
function observeFrames() {
  function after(target, method, inspect) {
    const original = target.prototype[method];
    target.prototype[method] = function(...args) {
      const result = original.apply(this, args);
      inspect(this, args, result);
      return result;
    };
  }
  const surfaces = new WeakSet(), views = new WeakSet(), encoders = new WeakSet(), draws = new WeakSet();
  const frames = [];
  let firstSubmit, resolution;
  after(GPUDevice, 'createTexture', (_, [desc], texture) => {
    if (desc.label === 'trace/gbuffer') resolution = [texture.width, texture.height];
  });
  after(GPUCanvasContext, 'getCurrentTexture', (_, args, texture) => surfaces.add(texture));
  after(GPUTexture, 'createView', (texture, args, view) => { if (surfaces.has(texture)) views.add(view); });
  after(GPUCommandEncoder, 'beginRenderPass', (encoder, [pass]) => {
    if (pass.colorAttachments.some(a => views.has(a?.view))) encoders.add(encoder);
  });
  after(GPUCommandEncoder, 'finish', (encoder, args, buffer) => { if (encoders.has(encoder)) draws.add(buffer); });
  after(GPUQueue, 'submit', (queue, [commands]) => {
    firstSubmit ??= performance.now();
    if (!commands.some(command => draws.has(command))) return;
    const start = firstSubmit;
    firstSubmit = undefined;
    queue.onSubmittedWorkDone().then(() => frames.push([performance.now(), start]));
  });
  globalThis.rideFrames = () => ({frames: frames.splice(0), resolution});
}

const evaluate = expression => browser.evaluate(expression);
const key = (key, down) => browser.send('Input.dispatchKeyEvent', {type: down ? 'keyDown' : 'keyUp', key});
const quality = () => evaluate('document.querySelector(".quality")?.textContent');
const metres = () => evaluate('Number(document.querySelector(".speed").dataset.metres)');
async function openRide(place) {
  await browser.navigate(new URL('valley.css', base).href);
  await until(() => evaluate('location.pathname.endsWith("valley.css") && document.readyState === "complete"'), 'origin');
  const save = [...await readFile('build/' + place + '.ride')];
  await evaluate(`import('./storage.mjs').then(m => m.storeSave("iygtw-willowbank-v1", new Uint8Array(${JSON.stringify(save)})))`);
  await browser.navigate(base.href);
  const state = await until(() => evaluate('document.body?.dataset.error || document.body?.dataset.ready'), 'ride', 150);
  if (state !== 'true') throw Error(state);
  await evaluate('document.querySelector(".pause").click()');
  await until(() => evaluate('document.querySelector(".pause-screen")?.hidden === false'), 'pause menu');
  for (const [selector, value] of [['.resolution', preset], ['.samples', samples], ['.bounces', bounces]]) {
    const changed = await evaluate(`(() => {const s=document.querySelector(${JSON.stringify(selector)});
      s.value=${JSON.stringify(value)}; if(s.selectedIndex<0)return false;
      s.dispatchEvent(new Event("change",{bubbles:true}));return true})()`);
    if (!changed) throw Error('Unknown ' + selector + ' ' + value);
    await sleep(180);
  }
  await evaluate('document.querySelector(".resume").click()');
  await until(() => evaluate('document.querySelector(".pause-screen")?.hidden'), 'resume');
  if (await quality() !== preset) throw Error('Resolution did not change');
}

function percentile(values, fraction) {
  return +values.sort((a, b) => a - b)[Math.floor((values.length - 1) * fraction)].toFixed(1);
}
// A brief turn follows the lane at each bend, including the exit from the bridge.
async function followLane(place) {
  const [direction, approach, turn] = {
    'lantern-row': ['d', 3800, 300],
    'mill-bridge': ['a', 2400, 640],
    orchard: ['d', 3800, 200],
  }[place];
  await sleep(approach);
  await key(direction, true);
  try { await sleep(turn); } finally { await key(direction, false); }
}

async function measure(place) {
  await openRide(place);
  const adapter = await evaluate('navigator.gpu.requestAdapter().then(a => [a.info.vendor, a.info.architecture, a.info.isFallbackAdapter])');
  if (adapter[2]) throw Error('Chromium selected a software adapter');
  await key('w', true); await sleep(1800);
  await evaluate('rideFrames()'); const from = await metres();
  await Promise.all([sleep(9000), followLane(place)]);
  const {frames, resolution} = await evaluate('rideFrames()');
  await key('w', false);
  if (frames.length < 2 || !resolution) throw Error('No traced frames');
  const elapsed = frames.at(-1)[0] - frames[0][0], distance = await metres() - from;
  const speed = await evaluate('parseInt(document.querySelector(".speed").textContent, 10)');
  if (distance < 25 || speed < 3) throw Error(place + ' covered ' + distance + ' metres and ended at ' + speed + ' km/h');
  const intervals = frames.slice(1).map(([end], i) => end - frames[i][0]);
  console.log(JSON.stringify({place, preset, samples, bounces, resolution, adapter, metres: distance, frames: frames.length,
    fps: +((frames.length - 1) * 1000 / elapsed).toFixed(2), p95IntervalMs: percentile(intervals, .95),
    p95SubmissionToFinishMs: percentile(frames.map(([end, start]) => end - start), .95)}));
}

try {
  await browser.send('Page.addScriptToEvaluateOnNewDocument', {source: '(' + observeFrames.toString() + ')()'});
  await browser.send('Emulation.setDeviceMetricsOverride', {width: 1920, height: 1080, deviceScaleFactor: 1, mobile: false});
  for (const place of ['lantern-row', 'mill-bridge', 'orchard']) await measure(place);
} finally { browser.close(); }
