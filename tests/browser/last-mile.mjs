// Drive the shipped page through keyboard events. The headless Scheme
// fixture finishes the mission. This test crosses the page, GPU and save
// boundaries and reads only the instruments a player sees.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {join} from 'node:path';
import {writeFile} from 'node:fs/promises';
import {createCanvas, loadImage} from '@napi-rs/canvas';
import {promisify} from 'node:util';
import {openBrowser, sleep, until} from './chromium.mjs';
import {serve} from './static.mjs';

const [root, screenshot] = process.argv.slice(2);
const {stdout} = await promisify(execFile)(join(root, 'snail-scheme'),
  ['build', '--target', 'browser', 'src/apps/last-mile/main.scm'], {cwd: root});
const server = await serve(stdout.trim());
const browser = await openBrowser();
const url = 'http://127.0.0.1:' + server.address().port + '/';
const read = selector => browser.evaluate('document.querySelector(' + JSON.stringify(selector) + ')?.textContent');
const expect = (selector, text) => until(async () => (await read(selector))?.includes(text), text);
const key = (key, down) => browser.send('Input.dispatchKeyEvent', {type: down ? 'keyDown' : 'keyUp', key});
const tap = async k => { await key(k, true); await key(k, false); };
const ready = () => until(async () => {
  const {ready, error} = await browser.evaluate('({...document.body.dataset})');
  if (error) throw new Error(error);
  return ready;
}, 'first rendered frame');

// The instruments alone can pass every interaction check while an eye inside
// an opaque tree sees black. Sample the street between the map and HUD.
async function visibleStreet() {
  const capture = await browser.send('Page.captureScreenshot', {format: 'png'});
  const bytes = Buffer.from(capture.result.data, 'base64');
  const image = await loadImage(bytes);
  const ctx = createCanvas(32, 16).getContext('2d');
  ctx.drawImage(image, image.width * 0.16, image.height * 0.23,
    image.width * 0.65, image.height * 0.39, 0, 0, 32, 16);
  const {data} = ctx.getImageData(0, 0, 32, 16);
  const colors = new Set();
  for (let i = 0; i < data.length; i += 4) {
    if (Math.max(data[i], data[i + 1], data[i + 2]) > 55)
      colors.add([data[i] >> 4, data[i + 1] >> 4, data[i + 2] >> 4].join('/'));
  }
  return colors.size >= 12 && bytes;
}

try {
  await browser.navigate(url);
  await ready();
  await expect('.stage', 'PICTURE CAR');
  await until(visibleStreet, 'sunlit street at the starting position');
  await tap('e');
  await expect('.stage', 'PASSENGER PICKUP');
  await expect('.mode', 'KM/H');
  await key('w', true);
  await until(async () => parseInt(await read('.range'), 10) <= 5, 'the pickup curb');
  await key('w', false);
  await key('b', true);
  await expect('.stage', 'SHOOTING MARK');
  await key('b', false);
  await expect('.speech', 'one reel');
  await expect('.answers', 'Talk me through the turn');
  const shot = await until(visibleStreet, 'both riders at the pickup');
  if (screenshot) await writeFile(screenshot, shot);
  await tap('2');
  await expect('.speech', 'Gold tape, eastbound');
  await tap('p');
  await expect('.signal', 'PAUSED');
  const range = await read('.range');
  // One whole autosave period passes while the simulation is paused.
  await sleep(5300);
  assert.equal(await read('.range'), range);
  await browser.navigate(url);
  await ready();
  await expect('.stage', 'SHOOTING MARK');
  await expect('.speech', 'Gold tape, eastbound');
  await tap('t');
  await until(async () => (await read('.speech')) === '', 'finished conversation');
  await expect('.mode', 'KM/H');
  await tap('e');
  await expect('.mode', 'ON FOOT');
  assert.equal(await browser.evaluate('document.body.dataset.error'), undefined);
  console.log('Last Mile picked up Rosa, chose an Ink reply, restored the conversation and dismounted in Chromium.');
} finally {
  browser.close();
  server.close();
}
