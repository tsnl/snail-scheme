// Exercise the published app as a rider, including a second visit with all art downloads blocked.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {readFile} from 'node:fs/promises';
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
  ['bell.wav', 'freewheel.wav', 'ground.bin', 'moss.glb', 'roadster.glb', 'surfaces.bin', 'waymarks.bin', 'willowbank.glb']);
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
const browser = await openBrowser();
const text = selector => browser.evaluate('document.querySelector(' + JSON.stringify(selector) + ')?.textContent');
const key = (key, down) => browser.send('Input.dispatchKeyEvent', {type: down ? 'keyDown' : 'keyUp', key});
const tap = async k => { await key(k, true); await key(k, false); };
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

  // Read the canvas area above the instruments. A blank canvas can still have a working HUD.
  const png = (await browser.send('Page.captureScreenshot', {format: 'png'})).result.data;
  const img = await loadImage(Buffer.from(png, 'base64'));
  const ctx = createCanvas(64, 40).getContext('2d'); ctx.drawImage(img, 0, 0, 64, 40);
  const pixels = ctx.getImageData(8, 12, 48, 16).data, colors = new Set();
  for (let i = 0; i < pixels.length; i += 4) colors.add((pixels[i] >> 4) * 256 + (pixels[i+1] >> 4) * 16 + (pixels[i+2] >> 4));
  assert.ok(colors.size > 10, 'the rendered landscape should contain distinct material colours');
  if (screenshot) await browser.screenshot(screenshot);

  await key('w', true);
  try { await until(async () => await metres() >= 3, 'pedalling out of town', 55); }
  finally { await key('w', false); }
  await key(' ', true);
  try { await until(async () => await text('.speed') === '0 km/h', 'braking to a stop', 45); }
  finally { await key(' ', false); }
  await browser.evaluate('document.querySelector(".light").click()');
  await until(async () => await text('.light') === 'High sun', 'new sky', 30);
  await tap('b');
  await until(async () => await browser.evaluate('document.querySelectorAll("audio").length') === 2, 'bell and hub', 25);
  await browser.evaluate('document.querySelector(".pause").click()');
  await until(async () => await text('.pause') === 'Resume', 'pause and save', 30);

  offline = true; const before = fetched, saved = await metres();
  await browser.navigate('http://127.0.0.1:' + server.address().port);
  await ready(); await until(async () => await metres() >= saved, 'saved ride', 25);
  assert.equal(await text('.light'), 'High sun');
  assert.equal(fetched, before, 'reload attempted to download village art again');
  await tap('r');
  await until(async () => await metres() === 0, 'return to Lantern Row', 25);
  console.log('Willowbank rendered, rode, braked and reloaded with all village downloads blocked.');
} finally { browser.close(); server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
