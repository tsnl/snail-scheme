// Exercise the real forward material and irradiance shaders through the standalone browser app.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';
import {openBrowser, until} from './chromium.mjs';
import {serve} from './static.mjs';

const [root, screenshot] = process.argv.slice(2);
const directory = execFileSync(join(root, 'snail-scheme'),
  ['build', '--release', '--target', 'browser', 'src/apps/furnace/main.scm'], {cwd: root, encoding: 'utf8'}).trim();
const server = await serve(directory);
const browser = await openBrowser({hardware: process.env.SNAIL_WEBGPU_HARDWARE === '1'});
const read = selector => browser.evaluate('document.querySelector(' + JSON.stringify(selector) + ')?.textContent');
async function result(label) {
  await until(async () => {
    const failure = await read('#failure');
    assert.ok(!failure, failure);
    return await read('[role="status"]') === label;
  }, label, 120);
  assert.equal(await read('#environment'), '1.000');
  assert.equal(await browser.evaluate('document.querySelector("#environment").dataset.rgb'), 'RGB 1.000 / 1.000 / 1.000');
  assert.ok(parseInt(await read('#duration')) > 0);
  return Number(await read('#surface'));
}
const rerun = (material, roughness, samples) => browser.evaluate(
  'Object.values(document.querySelectorAll("select")).forEach((s,i)=>s.value=' +
  JSON.stringify([material, roughness, samples]) + '[i]); document.querySelector("button").click()');
try {
  await browser.send('Emulation.setDeviceMetricsOverride',
    {width: 1200, height: 1080, deviceScaleFactor: 1, mobile: false});
  await browser.navigate('http://127.0.0.1:' + server.address().port);
  const rough = await result('White metal · 100% roughness · 1× MSAA');
  // For F=1, alpha=1 and V=N, the single-scatter GGX integral is 1-ln(2).
  assert.ok(Math.abs(rough - (1 - Math.log(2))) < 0.025, 'Rough metal returned ' + rough);
  await until(() => browser.evaluate('document.images.length === 2 && Array.from(document.images).every(i=>i.complete && i.naturalWidth === 192)'),
    'both furnace images to decode');
  if (screenshot) await browser.screenshot(screenshot);
  await rerun('White metal', '10', '1');
  const smooth = await result('White metal · 10% roughness · 1× MSAA');
  assert.ok(Math.abs(smooth - 1) < 0.04, 'Smooth metal returned ' + smooth);
  await rerun('White dielectric', '50', '4');
  const dielectric = await result('White dielectric · 50% roughness · 4× MSAA');
  assert.ok(dielectric > 0.88 && dielectric < 1.1, 'Dielectric returned ' + dielectric);
  await rerun('White metal', '100', '1');
  assert.ok(Math.abs(rough - await result('White metal · 100% roughness · 1× MSAA')) < 0.002);
  await browser.send('Page.addScriptToEvaluateOnNewDocument',
    {source: 'Object.defineProperty(navigator, "gpu", {value: undefined})'});
  await browser.navigate('http://127.0.0.1:' + server.address().port);
  await until(async () => await read('#failure') === 'This browser does not support WebGPU.', 'WebGPU error');
  console.log(JSON.stringify({roughMetal: rough, smoothMetal: smooth, dielectric, sky: 1}));
} finally {
  browser.close();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
