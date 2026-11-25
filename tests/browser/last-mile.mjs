// Drive a fare in the browser, then reload with all linked object requests blocked.
// Traffic, GPS, lighting and the street must still run from the saved shift.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {join} from 'node:path';
import {realpath, writeFile} from 'node:fs/promises';
import {createCanvas, loadImage} from '@napi-rs/canvas';
import {promisify} from 'node:util';
import {openBrowser, sleep, until} from './chromium.mjs';
import {serve} from './static.mjs';

const [root, screenshot] = process.argv.slice(2);
const {stdout} = await promisify(execFile)(join(root, 'snail-scheme'),
  ['build', '--target', 'browser', 'src/apps/last-mile/main.scm'], {cwd: root});
const server = await serve(await realpath(stdout.trim()));
const objects = new Map();
server.on('request', request => { if (request.url.includes('/store/sha256/')) objects.set(request.url, (objects.get(request.url) ?? 0) + 1); });
const browser = await openBrowser();
const url = 'http://127.0.0.1:' + server.address().port + '/';
const read = selector => browser.evaluate('document.querySelector(' + JSON.stringify(selector) + ')?.textContent');
const expect = (selector, text) => until(async () => (await read(selector))?.includes(text), text, 100);
const key = (key, down) => browser.send('Input.dispatchKeyEvent', {type: down ? 'keyDown' : 'keyUp', key});
const tap = async k => { await key(k, true); await key(k, false); };
const click = selector => browser.evaluate('document.querySelector(' + JSON.stringify(selector) + ').click()');
const selection = selector => browser.evaluate('document.querySelector(' + JSON.stringify(selector) + ').value');
async function choose(selector, value) {
  await browser.evaluate(`(() => {
    const field = document.querySelector(${JSON.stringify(selector)});
    field.value = ${JSON.stringify(value)};
    field.dispatchEvent(new Event('change', {bubbles: true}));
  })()`);
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
  const capture = await browser.send('Page.captureScreenshot', {format: 'png'});
  const bytes = Buffer.from(capture.result.data, 'base64');
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
  await browser.send('Emulation.setDeviceMetricsOverride', {width: 900, height: 600, deviceScaleFactor: 0.6, mobile: false});
  await browser.navigate(url);
  await ready();
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
  assert.equal(await selection('#render-resolution'), '720p');
  assert.deepEqual(await browser.evaluate('[...document.querySelector("#render-resolution").options].map(o => o.value)'),
    ['480p', '720p', '1080p']);
  await browser.send('Emulation.setDeviceMetricsOverride', {width: 390, height: 700, deviceScaleFactor: 2, mobile: false});
  const narrow = await streetChart();
  assert.equal(narrow.box, local.box);
  assert.ok(narrow.labelPixels >= 10, 'street names remain legible at phone width');
  assert.ok(narrow.ratio > 1 && narrow.ratio < 3);
  await choose('#render-resolution', '1080p');
  await until(async () => {
    const match = (await read('.quality'))?.match(/1080p · (\d+)×(\d+)/);
    return match && +match[2] === 1080;
  }, 'fixed 1080p setting on a portrait display', 130);
  // The high-density check above exercises the display resolution. Render the
  // keyboard drive at 300 × 190 so the software GPU can present each manoeuvre.
  await browser.send('Emulation.setDeviceMetricsOverride', {width: 600, height: 380, deviceScaleFactor: 0.5, mobile: false});
  await choose('#render-resolution', '480p');
  await expect('.quality', '480p · ');
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
  await sleep(5500);
  assert.ok(objects.size >= 13, 'the initial load reads the map, graph, rig and textures');
  assert.ok([...objects.values()].every(n => n === 1), 'each linked digest downloads once');
  await browser.send('Network.enable');
  await browser.send('Network.setBlockedURLs', {urls: ['*/store/sha256/*']});
  const before = [...objects];
  await browser.navigate(url);
  await ready();
  await expect('.stage', 'METER RUNNING');
  await expect('.speech', 'Leavenworth');
  await until(visibleStreet, 'cached city, rider and taxi');
  assert.deepEqual([...objects], before);
  const cache = await browser.evaluate(`(async () => {
    const {readLinkedFile} = await import('./storage.mjs');
    const hash = async b => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', b)), n => n.toString(16).padStart(2, '0')).join('');
    const a = Uint8Array.of(13, 42), b = Uint8Array.of(14, 42);
    const first = await hash(a), second = await hash(b);
    let calls = 0, rejected = false;
    try { await readLinkedFile(first, async () => b); } catch { rejected = true; }
    const get = () => readLinkedFile(first, async () => { calls++; return a; });
    await Promise.all([get(), get()]); await get();
    const changed = await readLinkedFile(second, async () => b);
    return [rejected, calls, changed[0]];
  })()`);
  assert.deepEqual(cache, [true, 1, 14]);
  await pause();
  assert.equal(await selection('#render-resolution'), '480p');
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
  await browser.navigate(url);
  await ready();
  await expect('.stage', 'PICKUP');
  await pause();
  assert.equal(await selection('#render-resolution'), '480p');
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
  const day = (await streetImage()).luminance;
  await tap('l');
  await expect('.time', '11:');
  const night = await until(async () => {
    const image = await streetImage();
    return image.colors >= 12 && image.luminance < day * 0.85 && image;
  }, 'the island street growing dark under the night sky', 55);
  if (screenshot) await writeFile(screenshot.replace(/(\.png)?$/, '-island-night.png'), night.bytes);
  assert.deepEqual([...objects], before);
  assert.equal(await browser.evaluate('document.body.dataset.error'), undefined);
  console.log(`Rosa boarded, recovered with her fare, and restarted a shift with all ${before.length} linked requests blocked. Treasure Island daylight/night luminance: ${day.toFixed(1)} / ${night.luminance.toFixed(1)}.`);
} finally {
  browser.close();
  server.close();
}
