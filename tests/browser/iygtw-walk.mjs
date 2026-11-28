// The published walking study runs the same controller as the headless trials.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {join, resolve} from 'node:path';
import {promisify} from 'node:util';
import {openBrowser, until} from './chromium.mjs';
import {serve} from './static.mjs';

const [directory, screenshot] = process.argv.slice(2);
const root = resolve(directory);
const {stdout} = await promisify(execFile)(join(root, 'snail-scheme'),
  ['build', '--target', 'browser', 'src/apps/iygtw/main.scm'], {cwd: root});
const server = await serve(stdout.trim());
const browser = await openBrowser();
try {
  await browser.send('Emulation.setDeviceMetricsOverride',
    {width: 1080, height: 800, deviceScaleFactor: 1, mobile: false});
  await browser.navigate('http://127.0.0.1:' + server.address().port);
  const distance = () => browser.evaluate('parseFloat(document.querySelectorAll("dd")[1]?.textContent)');
  await until(async () => await distance() > 0.7, 'pelvis to advance on the first course');
  const pose = () => browser.evaluate('Array.from(document.querySelectorAll(".bone"), b => b.style.transform || b.style.cssText).join(" ")');
  const first = await pose();
  assert.ok(first.includes('--r:'));
  await until(async () => await pose() !== first, 'simulated joints to move');
  await browser.evaluate('document.querySelectorAll("select")[1].value = "0.8 m/s"');
  await browser.evaluate('document.querySelectorAll("select")[0].value = "Mill Bridge"');
  await until(async () => await distance() < 0.5, 'course change to reset the trial');
  await until(async () => await distance() > 1.0, 'slower controller to cross a metre');
  if (screenshot) await browser.screenshot(screenshot);
  await browser.evaluate('document.querySelector(".restart").click()');
  await until(async () => await distance() < 0.5, 'restart to reset distance');
  assert.ok(await browser.evaluate('document.body.dataset.ready && !document.body.dataset.error'));
} finally {
  browser.close();
  server.close();
}
