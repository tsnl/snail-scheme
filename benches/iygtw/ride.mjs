// Run from the repository root against a served game, using Chromium's Vulkan backend.
import {execFileSync} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {openBrowser, sleep, until} from '../../tests/browser/chromium.mjs';

const args = process.argv.slice(2);
const profile = args.includes('--profile'), memory = args.includes('--memory');
const vsync = !args.includes('--no-vsync');
const [url = 'http://127.0.0.1:4193/', size = '1920x1080', samples = '1'] = args.filter(arg => !arg.startsWith('--'));
if (!/^\d+x\d+$/.test(size)) throw Error('Expected viewport WIDTHxHEIGHT');
const [width, height] = size.split('x').map(Number);
const base = new URL(url.endsWith('/') ? url : url + '/');
if (profile) base.searchParams.set('profile', '');
execFileSync('./snail-scheme', ['run', '--target', 'node', 'benches/iygtw/checkpoints.scm'], {stdio: 'inherit'});
const browser = await openBrowser({hardware: true, vsync});

// Only a command buffer that draws to the canvas finishes a frame. Count its
// completion after all queued GPU work, including earlier compute submissions.
function observeFrames(profile) {
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
  let firstSubmit, resolution, submitted = 0, refresh = 0, stamp = -1, sceneUploads = 0;
  // Count distinct display refreshes, even when the game's pacer skips a draw.
  const raf = window.requestAnimationFrame.bind(window);
  window.requestAnimationFrame = callback => raf(time => {
    if (time !== stamp) { stamp = time; refresh++; }
    callback(time);
  });
  const turns = [], fences = [];
  const passTimes = new Map(), complete = new Set();
  if (profile) new PerformanceObserver(list => {
    for (const {name, detail, startTime, duration} of list.getEntries()) {
      if (name === 'main: turn') turns.push([startTime, startTime + duration]);
      if (name === 'wait: gpu done') fences.push([startTime, startTime + duration]);
      if (!name.startsWith('gpu: ') || !detail?.frame) continue;
      if (name === 'gpu: frame complete') { complete.add(detail.frame); continue; }
      const times = passTimes.get(detail.frame) ?? {};
      const pass = name.slice(5);
      times[pass] = (times[pass] ?? 0) + duration;
      passTimes.set(detail.frame, times);
    }
  }).observe({type: 'measure'});
  globalThis.rideProfile = (first, last) => {
    const result = [];
    for (let id = first; id <= last; id++) {
      if (!complete.has(id) || !passTimes.has(id)) return null;
      result.push(passTimes.get(id));
    }
    for (const id of complete) if (id <= last) { complete.delete(id); passTimes.delete(id); }
    return result;
  };
  globalThis.rideCpu = () => ({turns: turns.splice(0), fences: fences.splice(0)});
  // scene/data stages input geometry. Pose buffers and mud updates reuse the resident mesh.
  after(GPUDevice, 'createBuffer', (_, [desc]) => { if (desc.label === 'scene/data') sceneUploads++; });
  after(GPUDevice, 'createTexture', (_, [desc], texture) => {
    if (desc.label === 'forward/depth') resolution = [texture.width, texture.height];
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
    const frame = {firstSubmit, submit: performance.now(), id: ++submitted, refresh, sceneUploads,
                   place: document.querySelector('.place')?.textContent};
    firstSubmit = undefined;
    queue.onSubmittedWorkDone().then(() => frames.push({...frame, finished: performance.now()}));
  });
  globalThis.rideFrames = () => ({frames: frames.splice(0), resolution});
}

const evaluate = expression => browser.evaluate(expression);
const key = (key, down) => browser.send('Input.dispatchKeyEvent', {type: down ? 'keyDown' : 'keyUp', key});
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
  for (const [selector, value] of [['.msaa', samples]]) {
    const changed = await evaluate(`(() => {const s=document.querySelector(${JSON.stringify(selector)});
      s.value=${JSON.stringify(value)}; if(s.selectedIndex<0)return false;
      s.dispatchEvent(new Event("change",{bubbles:true}));return true})()`);
    if (!changed) throw Error('Unknown ' + selector + ' ' + value);
    await sleep(180);
  }
  await evaluate('document.querySelector(".resume").click()');
  await until(() => evaluate('document.querySelector(".pause-screen")?.hidden'), 'resume');
}

function percentile(values, fraction, digits = 1) {
  return +values.sort((a, b) => a - b)[Math.floor((values.length - 1) * fraction)].toFixed(digits);
}
function gpuCosts(frames) {
  const stats = values => ({p50Ms: percentile(values, .5, 3), p95Ms: percentile(values, .95, 3)});
  const table = rows => [...new Set(rows.flatMap(Object.keys))]
    .map(name => ({name, ...stats(rows.map(row => row[name] ?? 0))}))
    .sort((a, b) => b.p50Ms - a.p50Ms || b.p95Ms - a.p95Ms);
  const features = frames.map(frame => {
    const totals = {};
    for (const [pass, cost] of Object.entries(frame)) {
      const name = pass.split('/')[0];
      totals[name] = (totals[name] ?? 0) + cost;
    }
    return totals;
  });
  return {frames: frames.length, timedWork: stats(frames.map(frame => Object.values(frame).reduce((a, b) => a + b, 0))),
          features: table(features), passes: table(frames)};
}
// Union of the portions of these sorted spans inside the observation window.
function occupied(spans, lo, hi) {
  let end = lo, total = 0;
  for (const [begin, finish] of spans) {
    if (begin >= hi) break;
    const start = Math.max(begin, end), stop = Math.min(finish, hi);
    if (stop > start) { total += stop - start; end = stop; }
  }
  return total;
}

function pacing(frames, cpu) {
  const first = frames[0], last = frames.at(-1), count = frames.length - 1;
  const intervals = frames.slice(1).map((frame, i) => frame.submit - frames[i].submit);
  const elapsed = last.submit - first.submit, round = value => +value.toFixed(2);
  const crossings = [];
  for (let i = 1; i < frames.length; i++) {
    const from = frames[i - 1], to = frames[i];
    if (to.place !== from.place) crossings.push({from: from.place, to: to.place, intervalMs: round(to.submit - from.submit)});
  }
  const timing = {meanIntervalMs: round(elapsed / count), callbacksPerDraw: round((last.refresh - first.refresh) / count),
    p99SubmissionIntervalMs: percentile(intervals, .99), worstSubmissionIntervalMs: round(Math.max(...intervals)),
    geometryUploads: last.sceneUploads - first.sceneUploads, crossings};
  if (!cpu) return timing;
  // The browser can execute GPU work during an app turn or a wait. Report GPU
  // passes independently. Only attribute time outside a turn to the queue fence.
  const spans = [...cpu.turns, ...cpu.fences].sort((a, b) => a[0] - b[0]);
  const busy = occupied(cpu.turns, first.submit, last.submit);
  const active = occupied(spans, first.submit, last.submit);
  return {...timing, meanAppCpuMs: round(busy / count), meanFenceOutsideCpuMs: round((active - busy) / count),
          meanOutsideAppAndFenceMs: round((elapsed - active) / count)};
}

const counters = async () => (await browser.send('Memory.getDOMCounters')).result;
async function collectedCounters() {
  await browser.send('HeapProfiler.collectGarbage');
  return counters();
}
async function sampleCounters(samples) {
  for (let i = 0; i < 18; i++) { await sleep(500); samples.push(await counters()); }
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
  if (profile && !await evaluate('navigator.gpu.requestAdapter().then(a => a.features.has("timestamp-query"))'))
    throw Error('Per-pass profiling requires WebGPU timestamp-query');
  await key('w', true); await sleep(1800);
  const baseline = memory ? await collectedCounters() : null, samplesInRide = [];
  await evaluate('rideFrames();rideCpu()'); const from = await metres();
  await Promise.all([memory ? sampleCounters(samplesInRide) : sleep(9000), followLane(place)]);
  const {frames, resolution} = await evaluate('rideFrames()');
  await key('w', false);
  if (frames.length < 2 || resolution?.[0] !== width || resolution?.[1] !== height) throw Error('Missing native-resolution raster frames');
  if (!frames[0].sceneUploads) throw Error('Did not observe the initial scene upload');
  const elapsed = frames.at(-1).finished - frames[0].finished, distance = await metres() - from;
  const speed = await evaluate('parseInt(document.querySelector(".speed").textContent, 10)');
  if (distance < 25 || speed < 3) throw Error(place + ' covered ' + distance + ' metres and ended at ' + speed + ' km/h');
  const intervals = frames.slice(1).map((frame, i) => frame.finished - frames[i].finished);
  const timing = pacing(frames, profile ? await evaluate('rideCpu()') : null);
  if (timing.geometryUploads !== 0) throw Error('A ride reuploaded village geometry');
  let gpu;
  if (profile) {
    const range = [frames[0].id, frames.at(-1).id];
    const times = await until(() => evaluate(`rideProfile(${range})`), 'per-pass GPU timestamps (timestamp-query required)', 5);
    gpu = gpuCosts(times);
  }
  const dom = memory && {baseline, peakNodes: Math.max(...samplesInRide.map(v => v.nodes)),
    peakListeners: Math.max(...samplesInRide.map(v => v.jsEventListeners)), collected: await collectedCounters()};
  console.log(JSON.stringify({place, samples, resolution, adapter, vsync, gpu, timing, dom: dom || undefined, metres: distance, frames: frames.length,
    fps: +((frames.length - 1) * 1000 / elapsed).toFixed(2), p95IntervalMs: percentile(intervals, .95),
    p95SubmissionToFinishMs: percentile(frames.map(frame => frame.finished - frame.firstSubmit), .95)}));
}

try {
  await browser.send('Page.addScriptToEvaluateOnNewDocument', {source: '(' + observeFrames.toString() + ')(' + profile + ')'});
  await browser.send('Emulation.setDeviceMetricsOverride', {width, height, deviceScaleFactor: 1, mobile: false});
  for (const place of ['lantern-row', 'mill-bridge', 'orchard']) await measure(place);
} finally { browser.close(); }
