// Exercise the published app as a rider, including a second visit with all art downloads blocked.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {createCanvas, loadImage} from '@napi-rs/canvas';
import {openBrowser, until} from './chromium.mjs';
import {serve} from './static.mjs';
import {blobPartSize, objectPath, partPath} from '../../host/browser/load.mjs';

const [root, screenshot] = process.argv.slice(2);
const {stdout} = await promisify(execFile)(join(root, 'snail-scheme'),
  ['build', '--target', 'browser', 'src/apps/iygtw/main.scm'], {cwd: root});
const directory = stdout.trim();
const catalog = JSON.parse(await readFile(join(directory, 'resources.json')));
assert.deepEqual(Object.keys(catalog).sort(),
  ['basins.bin', 'bell.wav', 'freewheel.wav', 'ground.bin', 'moss.glb', 'roadster.glb', 'surfaces.bin', 'waymarks.bin', 'willowbank.glb']);
const artPaths = new Set(Object.values(catalog).flatMap(({sha256, size}) =>
  size <= blobPartSize ? [objectPath(sha256)] :
    Array.from({length: Math.ceil(size / blobPartSize)}, (_, i) => partPath(sha256, i))));
let fetched = 0, offline = false;
const server = await serve(directory, (path, res) => {
  if (!artPaths.has(path)) return false;
  fetched++;
  if (!offline) return false;
  res.writeHead(503).end(); return true;
});
const browser = await openBrowser({hardware: process.env.SNAIL_WEBGPU_HARDWARE === '1'});
const text = selector => browser.evaluate('document.querySelector(' + JSON.stringify(selector) + ')?.textContent');
const key = (key, down) => browser.send('Input.dispatchKeyEvent', {type: down ? 'keyDown' : 'keyUp', key});
const tap = async k => { await key(k, true); await key(k, false); };
const click = selector => browser.evaluate(`document.querySelector(${JSON.stringify(selector)}).click()`);
const choice = selector => browser.evaluate(`document.querySelector(${JSON.stringify(selector)}).value`);
const choose = (selector, value) => browser.evaluate(`(() => {
  const field=document.querySelector(${JSON.stringify(selector)}); field.value=${JSON.stringify(value)};
  field.dispatchEvent(new Event("change", {bubbles: true}));
})()`);
const metres = () => browser.evaluate('Number(document.querySelector(".speed")?.dataset.metres)');
const ready = () => until(async () => {
  const result = await browser.evaluate('({ready:document.body?.dataset.ready, error:document.body?.dataset.error})');
  if (result?.error) throw Error(result.error);
  return result?.ready;
}, 'Willowbank to draw', 140);
try {
  await browser.send('Emulation.setDeviceMetricsOverride', {width: 640, height: 400, deviceScaleFactor: 0.65, mobile: false});
  await browser.navigate('http://127.0.0.1:' + server.address().port);
  await ready();
  assert.equal(await text('.place'), 'Lantern Row');
  assert.equal(await text('.surface'), 'Paved lane');
  assert.equal(await text('.quality'), '900p');
  assert.equal(fetched, artPaths.size);
  assert.equal(await browser.evaluate('const b=document.querySelector("progress"); b.value===b.max && b.max>0'), true);

  // Headless Vulkan may omit the GPU surface from the compositor screenshot.
  // Snapshot the actual WebGPU canvas and wait for material colours to appear.
  const landscape = await until(async () => {
    const url = await browser.evaluate('document.getElementById("view").toDataURL("image/png")');
    if (!url?.startsWith('data:image/png;base64,')) return false;
    const bytes = Buffer.from(url.split(',')[1], 'base64');
    const img = await loadImage(bytes), ctx = createCanvas(64, 40).getContext('2d');
    ctx.drawImage(img, 0, 0, 64, 40);
    const pixels = ctx.getImageData(8, 12, 48, 16).data, colors = new Set();
    for (let i = 0; i < pixels.length; i += 4) colors.add((pixels[i] >> 4) * 256 + (pixels[i+1] >> 4) * 16 + (pixels[i+2] >> 4));
    return colors.size > 10 && bytes;
  }, 'colours in the WebGPU landscape', 60);
  if (screenshot) await writeFile(screenshot, landscape);

  await key('w', true);
  try { await until(async () => await metres() >= 3, 'pedalling out of town', 55); }
  finally { await key('w', false); }
  await key(' ', true);
  try { await until(async () => await text('.speed') === '0 km/h', 'braking to a stop', 45); }
  finally { await key(' ', false); }
  for (const reverse of ['s', 'ArrowDown']) {
    await key(reverse, true);
    try { await until(async () => await text('.surface') === 'Walking bike back', 'walking backwards with ' + reverse, 25); }
    finally { await key(reverse, false); }
    await key(' ', true);
    try { await until(async () => await text('.speed') === '0 km/h', 'holding after reverse', 25); }
    finally { await key(' ', false); }
  }
  await browser.evaluate('document.querySelector(".light").click()');
  await until(async () => await text('.light') === 'High sun', 'new sky', 30);
  await tap('b');
  await until(async () => await browser.evaluate('document.querySelectorAll("audio").length') === 2, 'bell and hub', 25);
  await browser.evaluate('document.querySelector(".pause").click()');
  await until(async () => await text('.pause') === 'Resume', 'pause and save', 30);

  await browser.evaluate('document.querySelector(".reset").focus()');
  await tap('Tab');
  await until(() => browser.evaluate('document.activeElement.matches(".resolution")'), 'wrap focus to resolution');
  await browser.send('Input.dispatchKeyEvent', {type:'keyDown', key:'Tab', modifiers:8});
  await browser.send('Input.dispatchKeyEvent', {type:'keyUp', key:'Tab', modifiers:8});
  await until(() => browser.evaluate('document.activeElement.matches(".reset")'), 'wrap focus to reset');
  await choose('.resolution', '360p');
  await until(async () => await text('.quality') === '360p', 'fixed resolution', 30);
  await choose('.samples', '4'); await choose('.bounces', '3');
  const stopped = await metres();
  await key('w', true); await new Promise(resolve => setTimeout(resolve, 350)); await key('w', false);
  assert.equal(await metres(), stopped, 'ride advanced while the menu was open');
  await click('.resume');
  await until(async () => await text('.pause') === 'Pause', 'resume after saving settings');

  await click('.bicycle');
  await until(async () => await text('.bicycle') === 'Ride · F', 'park beside the roadster');
  await tap('f');
  await until(async () => await text('.bicycle') === 'Get off · F', 'step back into the saddle');
  await tap('f');
  await until(async () => await text('.bicycle') === 'Ride · F', 'dismount with the keyboard');
  await key('w', true);
  try {
    await until(async () => await text('.surface') === 'Walking' && await text('.bicycle') === '', 'walk away from the parked bicycle');
    assert.ok(parseInt(await text('.speed')) <= 7);
    await key('Shift', true);
    try { await until(async () => await text('.surface') === 'Running' && parseInt(await text('.speed')) > 12, 'break into a run'); }
    finally { await key('Shift', false); }
    await until(async () => await text('.surface') === 'Walking', 'return to a walk');
  } finally { await key('w', false); }
  await until(async () => await text('.surface') === 'On foot', 'come to rest');
  await tap('f');
  assert.equal(await text('.surface'), 'On foot');
  await click('.pause');
  await until(async () => await text('.pause') === 'Resume', 'save away from the bicycle');

  offline = true; const before = fetched, saved = await metres();
  await browser.navigate('http://127.0.0.1:' + server.address().port);
  await ready(); await until(async () => await metres() >= saved, 'saved ride', 25);
  assert.equal(await text('.light'), 'High sun');
  assert.equal(await text('.surface'), 'On foot');
  assert.equal(fetched, before, 'reload attempted to download village art again');
  await tap('p');
  await until(async () => await text('.pause') === 'Resume', 'open saved settings');
  assert.deepEqual(await Promise.all(['.resolution','.samples','.bounces'].map(choice)), ['360p','4','3']);
  await click('.reset');
  await until(async () => await metres() === 0, 'return to Lantern Row', 25);
  assert.equal(await text('.place'), 'Lantern Row');
  await tap('p');
  await until(async () => await text('.pause') === 'Resume', 'settings after reset');
  assert.deepEqual(await Promise.all(['.resolution','.samples','.bounces'].map(choice)), ['360p','4','3']);
  console.log('Willowbank rendered, rode, parked, remounted, walked, ran, changed settings, reset and reloaded on foot offline.');
} finally { browser.close(); server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
