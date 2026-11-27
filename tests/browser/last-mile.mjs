// Drive a fare in the browser, then reload with every city object request blocked.
// Traffic, GPS, lighting and the street must still run from the saved shift.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {join} from 'node:path';
import {readFile, realpath, writeFile} from 'node:fs/promises';
import {createCanvas, loadImage} from '@napi-rs/canvas';
import {promisify} from 'node:util';
import {openBrowser, sleep, until} from './chromium.mjs';
import {serve} from './static.mjs';
import {blobPartSize, objectPath, partPath} from '../../host/browser/load.mjs';

const [root, screenshot] = process.argv.slice(2);
const {stdout} = await promisify(execFile)(join(root, 'snail-scheme'),
  ['build', '--target', 'browser', 'src/apps/last-mile/main.scm'], {cwd: root});
const directory = await realpath(stdout.trim());
const catalog = JSON.parse(await readFile(join(directory, 'resources.json')));
const program = new WebAssembly.Module(await readFile(join(directory, 'main.wasm')));
assert.equal(WebAssembly.Module.imports(program).filter(i => i.module === 'snail.runtime.link').length, 0);
const total = Object.values(catalog).reduce((n, file) => n + file.size, 0);
const totalMiB = (Math.floor(total * 10 / 1048576) / 10).toFixed(1);
const paths = ({sha256, size}) => size <= blobPartSize ? [objectPath(sha256)] :
  Array.from({length: Math.ceil(size / blobPartSize)}, (_, i) => partPath(sha256, i));
const object = name => paths(catalog[name])[0];
const assetPaths = new Set(Object.values(catalog).flatMap(paths));
const held = Promise.withResolvers();
let hold = true, fail = true;
const server = await serve(directory, async (path, response) => {
  if (path === 'seed.html') {
    response.writeHead(200, {'content-type': 'text/html'}).end('<title>Prior install</title>');
    return true;
  }
  if (path === object('sf-1.bin') && hold) {
    hold = false;
    const bytes = await readFile(join(directory, path));
    response.writeHead(200); // No Content-Length. The catalog supplies the denominator.
    response.write(bytes.subarray(0, 1 << 20));
    await held.promise;
    response.end(bytes.subarray(1 << 20));
    return true;
  }
  if (path === object('sf-2.bin') && fail) {
    fail = false;
    response.writeHead(503).end();
    return true;
  }
  return false;
});
const objects = new Map();
server.on('request', request => { if (assetPaths.has(request.url.slice(1))) objects.set(request.url, (objects.get(request.url) ?? 0) + 1); });
const browser = await openBrowser({hardware: process.env.SNAIL_WEBGPU_HARDWARE === '1'});
const url = 'http://127.0.0.1:' + server.address().port + '/';
const read = selector => browser.evaluate('document.querySelector(' + JSON.stringify(selector) + ')?.textContent');
const expect = (selector, text) => until(async () => (await read(selector))?.includes(text), text, 100);
const key = (key, down) => browser.send('Input.dispatchKeyEvent', {type: down ? 'keyDown' : 'keyUp', key});
const tap = async k => { await key(k, true); await key(k, false); };
const click = selector => browser.evaluate('document.querySelector(' + JSON.stringify(selector) + ').click()');
const selection = selector => browser.evaluate('document.querySelector(' + JSON.stringify(selector) + ').value');
const savedShift = () => browser.evaluate(`import('./storage.mjs').then(async ({loadSave}) => {
  const bytes = await loadSave('last-mile-sf-taxi-v1');
  return bytes ? [...bytes] : null;
})`);
const choose = (selector, value) => chooseTogether([[selector, value]]);
async function chooseTogether(changes) {
  await browser.evaluate(`(() => {
    for (const [selector, value] of ${JSON.stringify(changes)}) {
      const field = document.querySelector(selector);
      field.value = value;
      field.dispatchEvent(new Event('change', {bubbles: true}));
    }
  })()`);
}
async function expectGraphics(samples, size) {
  await until(async () => {
    const value = await selection('#msaa');
    const state = await browser.evaluate(`({
      depth: window.streetDepth, output: window.streetOutput,
      width: document.querySelector('canvas').width, height: document.querySelector('canvas').height
    })`);
    return (!size || (state.width === size[0] && state.height === size[1])) &&
      value === String(samples) && state.depth?.[2] === samples &&
      state.depth[0] === state.width && state.depth[1] === state.height &&
      state.output?.[0] === state.width && state.output[1] === state.height;
  }, 'native resolution at ' + samples + '× MSAA', 130);
}

async function pause() {
  await click('.pause-toggle');
  await until(() => browser.evaluate('!document.querySelector(".pause-scrim").hidden'), 'pause menu', 100);
}
async function restart(accept) {
  const clicked = click('.restart-game');
  await until(async () => {
    const reply = await browser.send('Page.handleJavaScriptDialog', {accept});
    return !reply.error;
  }, 'restart confirmation');
  await clicked;
}
const ready = () => until(async () => {
  const {ready, error} = await browser.evaluate('document.body && ({...document.body.dataset})') ?? {};
  if (error) throw new Error(error);
  return ready;
}, 'first rendered frame', 130);

// Read the SVG the browser actually displays. Its extent should cover the
// neighbourhood at native screen density even after changing device scale.
async function streetChart() {
  return browser.evaluate(`(() => {
    const image = document.querySelector('.local-chart');
    if (!image?.complete || !image.src.startsWith('data:image/svg+xml;base64,')) return;
    const doc = new DOMParser().parseFromString(atob(image.src.split(',')[1]), 'image/svg+xml');
    const tile = image.getBoundingClientRect(), map = document.querySelector('.map').getBoundingClientRect();
    return {box: doc.documentElement.getAttribute('viewBox'), width: image.naturalWidth,
      paths: doc.querySelectorAll('path[stroke]').length, names: [...doc.querySelectorAll('svg > use')].filter(node =>
        doc.getElementById(node.getAttribute('href').slice(1))?.tagName === 'text').length,
      labelPixels: Number(doc.querySelector('text')?.getAttribute('font-size')) * tile.width / image.naturalWidth,
      ratio: tile.width / map.width, overview: getComputedStyle(document.querySelector('.geography')).display};
  })()`);
}

// The instruments alone can pass every interaction check while an eye inside
// an opaque tree sees black. Sample the street between the map and HUD.
async function streetImage() {
  const url = await browser.evaluate('document.querySelector("canvas").toDataURL("image/png")');
  const bytes = Buffer.from(url.split(',')[1], 'base64');
  const image = await loadImage(bytes);
  const ctx = createCanvas(32, 16).getContext('2d');
  ctx.drawImage(image, image.width * 0.16, image.height * 0.23,
    image.width * 0.65, image.height * 0.39, 0, 0, 32, 16);
  const {data} = ctx.getImageData(0, 0, 32, 16);
  const colors = new Set();
  let luminance = 0;
  for (let i = 0; i < data.length; i += 4) {
    luminance += 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2];
    if (Math.max(data[i], data[i + 1], data[i + 2]) > 55)
      colors.add([data[i] >> 4, data[i + 1] >> 4, data[i + 2] >> 4].join('/'));
  }
  return {bytes, colors: colors.size, luminance: luminance / (data.length / 4)};
}

async function visibleStreet() {
  const image = await streetImage();
  return image.colors >= 12 && image.bytes;
}

try {
  await browser.send('Page.addScriptToEvaluateOnNewDocument', {source: `
    const createTexture = GPUDevice.prototype.createTexture;
    GPUDevice.prototype.createTexture = function(descriptor) {
      const texture = createTexture.call(this, descriptor);
      if (texture.label === 'forward/depth') window.streetDepth = [texture.width, texture.height, texture.sampleCount];
      if (texture.label === 'forward/output') window.streetOutput = [texture.width, texture.height];
      return texture;
    };`});
  await browser.send('Emulation.setDeviceMetricsOverride', {width: 900, height: 600, deviceScaleFactor: 0.6, mobile: false});
  // Seed a real prior-version IndexedDB entry before the new app runs.
  const legacyFile = 'Textures/colormap.png', legacyHash = catalog[legacyFile].sha256;
  await browser.navigate(url + 'seed.html');
  await until(() => browser.evaluate('location.pathname.endsWith("seed.html")'), 'fixture origin');
  const legacyBytes = await readFile(join(directory, object(legacyFile)));
  assert.equal(await browser.evaluate(`new Promise((resolve, reject) => {
    const open = indexedDB.open('snail-linked-files', 1);
    open.onupgradeneeded = () => open.result.createObjectStore('objects');
    open.onsuccess = () => {
      const tx = open.result.transaction('objects', 'readwrite');
      tx.objectStore('objects').put(Uint8Array.from(atob('${legacyBytes.toString('base64')}'), c => c.charCodeAt(0)), '${legacyHash}');
      tx.oncomplete = () => { open.result.close(); resolve(true); };
      tx.onabort = reject;
    };
  })`), true);
  await browser.navigate(url);
  const prior = Object.keys(catalog).slice(0, Object.keys(catalog).indexOf('sf-1.bin'))
    .reduce((n, name) => n + catalog[name].size, 0);
  await until(() => browser.evaluate(`document.querySelector('.city-progress')?.value === ${prior + (1 << 20)}`),
    'byte progress inside an unfinished city file', 90);
  assert.equal(await browser.evaluate("document.querySelector('.city-progress').max"), total);
  assert.match(await read('.loading-title'), /Downloading/);
  if (screenshot) await browser.screenshot(screenshot.replace(/\.png$/, '-download.png'));
  held.resolve();
  await expect('#status-text', 'sf-2.bin');
  assert.equal(await browser.evaluate("document.querySelector('#retry').hidden"), false);
  await click('#retry');
  await until(() => browser.evaluate('document.body && !document.body.dataset.error'), 'fresh retry');
  await ready();
  assert.equal(objects.get('/' + object('sf-1.bin')), 1, 'retry retained the completed transfer');
  assert.equal(objects.get('/' + object(legacyFile)), undefined, 'old IndexedDB bytes avoided a download');
  assert.ok(await browser.evaluate(`(async () => !!await (await caches.open('snail-static-resources-v1'))
    .match('/.snail/sha256/${legacyHash}'))()`), 'old bytes were promoted to Cache Storage');
  await expect('.stage', 'PICKUP');
  await expect('h2', 'Rosa');
  await expect('.time', 'PM');
  assert.ok(await until(visibleStreet, 'city and taxi in daylight'));
  const local = await until(async () => (await streetChart())?.paths && streetChart(), 'vector street chart');
  assert.equal(local.width, 768);
  assert.ok(local.paths > 15 && local.names > 0 && local.box.endsWith('768 768'));
  assert.ok(local.ratio > 1 && local.ratio < 3);
  assert.equal(local.overview, 'none');
  await pause();
  await click('.load-game');
  await expect('.save-status', 'No saved game available.');
  await expectGraphics(1);
  assert.deepEqual(await browser.evaluate('[...document.querySelector("#msaa").options].map(o => o.value)'), ['1', '4']);
  await browser.send('Emulation.setDeviceMetricsOverride', {width: 390, height: 700, deviceScaleFactor: 2, mobile: false});
  const narrow = await streetChart();
  assert.equal(narrow.box, local.box);
  assert.ok(narrow.labelPixels >= 10, 'street names remain legible at phone width');
  assert.ok(narrow.ratio > 1 && narrow.ratio < 3);
  await expectGraphics(1, [780, 1400]);
  await browser.send('Emulation.setDeviceMetricsOverride', {width: 600, height: 380, deviceScaleFactor: 0.5, mobile: false});
  await choose('#msaa', '4');
  await expectGraphics(4, [300, 190]);
  await expect('.quality', '300×190 · 4× MSAA');
  await choose('#mouse-sensitivity', 'High');
  await click('.resume-game');
  await expect('.stage', 'PICKUP');
  const activation = {x: 550, y: 290, button: 'left', clickCount: 1};
  await browser.send('Input.dispatchMouseEvent', {type: 'mousePressed', ...activation});
  await browser.send('Input.dispatchMouseEvent', {type: 'mouseReleased', ...activation});
  await until(() => browser.evaluate('document.pointerLockElement === document.querySelector("canvas")'), 'mouse capture');
  await browser.evaluate('document.exitPointerLock()');
  await tap('m');
  await expect('.picker', 'Enter to start here');
  assert.equal(await browser.evaluate('getComputedStyle(document.querySelector(".local-chart")).display'), 'none');
  assert.equal(await browser.evaluate('getComputedStyle(document.querySelector(".geography")).display'), 'block');
  await tap(']');
  await expect('.picker', 'Jones');
  assert.equal(await browser.evaluate('document.querySelectorAll(".stand-dot").length'), 16);
  await browser.evaluate('[...document.querySelectorAll(".stand-dot")].find(node => node.title === "Ocean Beach").click()');
  await expect('.picker', 'Ocean Beach');
  await tap('m');
  await key('w', true);
  // Ease off before the curb. A full-throttle run downhill has a longer
  // stopping distance, especially when the software GPU draws few frames.
  await until(async () => parseInt(await read('.mode'), 10) >= 6, 'taxi rolling', 130);
  await key('w', false);
  await until(async () => parseInt(await read('.range'), 10) <= 5, 'Rosa’s curb', 150);
  await key('b', true);
  await expect('.stage', 'METER RUNNING');
  await key('b', false);
  await expect('.meter', '$4.00');
  await expect('h2', 'Jones Street');
  const fareHour = parseInt(await read('.time'), 10);
  await tap('l');
  await until(async () => parseInt(await read('.time'), 10) % 12 === (fareHour + 6) % 12, 'time change during the fare');
  await expect('.stage', 'METER RUNNING');

  await tap('1');
  await expect('.speech', 'Leavenworth');
  await until(() => browser.evaluate('document.querySelector(".route").style.backgroundImage.includes("polyline")'), 'GPS polyline');
  if (screenshot) await writeFile(screenshot, await until(visibleStreet, 'occupied taxi'));
  await tap('p');
  await expect('.stage', 'SHIFT PAUSED');
  await browser.evaluate("import('./application.mjs').then(({running}) => running[0].runtime.send(12))");
  await sleep(5500);
  assert.equal(await savedShift(), null, 'playing, hiding and changing settings leave the slot empty');
  await click('.save-game');
  await expect('.save-status', 'Shift saved.');
  const saved = await savedShift();
  assert.ok(saved?.length);
  assert.equal(objects.size, assetPaths.size - 1);
  for (const [path, count] of objects)
    assert.equal(count, path === '/' + object('sf-2.bin') ? 2 : 1, path);
  await browser.send('Network.enable');
  await browser.send('Network.setBlockedURLs', {urls: ['*/store/*']});
  const before = [...objects];
  await browser.navigate(url);
  await ready();
  await expect('.stage', 'PICKUP');
  await pause();
  await expectGraphics(1);
  assert.equal(await selection('#mouse-sensitivity'), 'Medium');
  await click('.load-game');
  await expect('.stage', 'METER RUNNING');
  await expect('.speech', 'Leavenworth');
  await until(visibleStreet, 'cached city, rider and taxi');
  assert.deepEqual([...objects], before);
  assert.ok((await read('.loading-bytes')).includes(totalMiB + ' MiB cached'));
  const cache = await browser.evaluate(`(async () => {
    const {readLinkedFile, readImmutable} = await import('./storage.mjs');
    const hash = async b => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', b)), n => n.toString(16).padStart(2, '0')).join('');
    const a = Uint8Array.of(13, 42), b = Uint8Array.of(14, 42);
    const first = await hash(a), second = await hash(b);
    let calls = 0, rejected = false;
    try { await readLinkedFile(first, async () => b); } catch { rejected = true; }
    const get = () => readLinkedFile(first, async () => { calls++; return a; });
    await Promise.all([get(), get()]); await get();
    const changed = await readLinkedFile(second, async () => b);
    const store = await caches.open('snail-static-resources-v1');
    await store.put('/.snail/sha256/' + first, new Response(b));
    let repairs = 0;
    const repaired = await readImmutable(first, a.length, async () => { repairs++; return a; });
    const c = Uint8Array.of(15, 42), third = await hash(c), put = Cache.prototype.put;
    let uncached;
    try {
      Cache.prototype.put = () => Promise.reject(new DOMException('full', 'QuotaExceededError'));
      uncached = await readImmutable(third, c.length, async () => c);
    } finally { Cache.prototype.put = put; }
    return [rejected, calls, changed[0], repairs, repaired[0], uncached[0], !!await store.match('/.snail/sha256/' + third)];
  })()`);
  assert.deepEqual(cache, [true, 1, 14, 1, 13, 15, false]);
  await pause();
  await expectGraphics(4);
  assert.equal(await selection('#mouse-sensitivity'), 'High');
  await click('.recover-cab');
  await expect('.stage', 'METER RUNNING');
  await expect('.meter', '$4.00');
  await expect('h2', 'Jones Street');
  await expect('.speech', 'Leavenworth');
  await pause();
  await restart(false);
  await expect('.stage', 'SHIFT PAUSED');
  await click('.resume-game');
  await expect('.stage', 'METER RUNNING');
  await pause();
  await restart(true);
  await expect('.stage', 'PICKUP');
  await expect('h2', 'Rosa');
  assert.deepEqual(await savedShift(), saved, 'recover and restart preserve the saved fare');
  await pause();
  await click('.save-game');
  await expect('.save-status', 'Shift saved.');
  assert.notDeepEqual(await savedShift(), saved, 'an explicit save replaces the old shift');
  await browser.navigate(url);
  await ready();
  await expect('.stage', 'PICKUP');
  await pause();
  await click('.load-game');
  await until(() => browser.evaluate('document.querySelector(".pause-scrim").hidden'), 'loaded shift');
  await pause();
  await expectGraphics(4);
  assert.equal(await selection('#mouse-sensitivity'), 'High');
  await click('.resume-game');
  await expect('.stage', 'PICKUP');
  await tap('m');
  for (let i = 0; i < 3; i++) await tap('[');
  await expect('.picker', 'Treasure Island');
  await tap('Enter');
  await expect('.message', 'Treasure Island');
  await until(async () => {
    const chart = await streetChart();
    return chart?.paths > 0 && chart.box !== local.box && chart.overview === 'none';
  }, 'island vector chart from the cached city');
  await until(visibleStreet, 'the independently drawn island streets', 65);
  const dayImage = await until(async () => { const image = await streetImage(); return image.colors >= 12 && image; }, "daylight exposure");
  const day = dayImage.luminance;
  await tap('l');
  await expect('.time', '11:');
  const night = await until(async () => {
    const image = await streetImage();
    return image.colors >= 12 && image.luminance < day * 0.85 && image;
  }, 'the island street growing dark under the night sky', 55);
  if (screenshot) await writeFile(screenshot.replace(/(\.png)?$/, '-island-night.png'), night.bytes);
  assert.deepEqual([...objects], before);
  assert.ok((await read('.loading-bytes')).includes(totalMiB + ' MiB cached'));
  assert.equal(await browser.evaluate('document.body.dataset.error'), undefined);
  const oldShift = await readFile(join(root, 'tests/programs/data/taxi-v3.save'));
  await browser.evaluate(`import('./storage.mjs').then(m => m.storeSave('last-mile-sf-taxi-v1', Uint8Array.of(${[...oldShift]})))`);
  await pause();
  await click('.load-game');
  await expect('.stage', 'METER RUNNING');
  await expect('.total', '$12.34');
  console.log(`Rosa boarded, recovered with her fare, and restarted a shift with all ${assetPaths.size} city object URLs blocked. Treasure Island daylight/night luminance: ${day.toFixed(1)} / ${night.luminance.toFixed(1)}.`);
} finally {
  held.resolve();
  browser.close();
  server.close();
}
