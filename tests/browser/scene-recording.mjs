// Record a viewer frame and replay it on a fresh native WebGPU device.
// A new device has only the JSONL stream, including the browser-only asset.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {pixels, observeOutput, captureFrame, assertMatches} from './renderer-trace.mjs';
import {openBrowser, until} from './chromium.mjs';
import {serve} from './static.mjs';

const run = promisify(execFile), root = process.argv[2], cli = join(root, 'snail-scheme');
const asset = join(root, 'tests/gpu/src/gpu-test/materials.gltf');
const model = await readFile(asset);
const {stdout} = await run(cli, ['build', '--target', 'browser', 'src/apps/viewer/main.scm'], {cwd: root});
const server = await serve(stdout.trim(), (path, res) => {
  if (path !== 'materials.gltf') return false;
  res.writeHead(200, {'content-type': 'model/gltf+json'}).end(model);
  return true;
});
const dir = await mkdtemp(join(tmpdir(), 'snail-scene-'));
const browser = await openBrowser({hardware: process.env.SNAIL_WEBGPU_HARDWARE === '1'});
const tap = async key => {
  for (const type of ['keyDown', 'keyUp']) await browser.send('Input.dispatchKeyEvent', {type, key});
};
try {
  await browser.send('Page.addScriptToEvaluateOnNewDocument', {source: '(' + observeOutput.toString() + ')()'});
  await browser.send('Emulation.setDeviceMetricsOverride', {width: 192, height: 120, deviceScaleFactor: 1, mobile: false});
  const url = 'http://127.0.0.1:' + server.address().port;
  await browser.navigate(url + '/?trace=1&model=' + encodeURIComponent(url + '/materials.gltf'));
  await until(() => browser.evaluate('document.body?.dataset.ready && document.querySelector("#status").textContent !== "Loading…"'), 'viewer model');
  await tap('4');
  const image = await until(async () => {
    const uri = await browser.evaluate('window.cameraSamples === 4 && window.sceneOutput()');
    if (!uri) return false;
    const value = await pixels(Buffer.from(uri.split(',')[1], 'base64'));
    return new Set(value.rgba).size > 20 && value;
  }, 'shaded image');
  await browser.evaluate('new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(resolve))))');
  const {trace: clip, image: rendered} = await captureFrame(browser);
  const headers = clip.trimEnd().split('\n').map(line => JSON.parse(line)).filter(line => typeof line === 'object');
  assert.ok(headers.some(c => c.op === 'createModel' && c.bytes.length >= 2 && c.bytes[1] > 0));
  assert.ok(headers.some(c => c.op === 'setEnvironment' && c.bytes[0] > 0));
  assert.ok(headers.some(c => c.op === 'render' && c.args.samples === 4));
  const trace = join(dir, 'viewer.jsonl');
  await writeFile(trace, clip);
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  const png = join(dir, 'replayed.png');
  await run(cli, ['run', '--target', 'node', 'tools/render.scm', 'replay=' + trace, 'output=' + png], {cwd: root});
  await assertMatches(rendered, await readFile(png));
  // A bounded replay leaves the next header unread. An unbounded replay of
  // the same stream must actually encounter the truncated binary command.
  await writeFile(trace, clip + '{"v":1,"op":"createModel","args":{"id":27},"bytes":[9]}\n');
  const play = count => run(cli, ['run', '--target', 'node', 'tools/render.scm', 'replay=' + trace,
    ...(count === undefined ? [] : ['commands=' + count]), 'output=' + png], {cwd: root});
  await play(headers.length);
  await assertMatches(rendered, await readFile(png));
  await assert.rejects(play(), error => (error.stderr + error.stdout).includes('truncated renderer trace block'));
  console.log('Recorded viewer scene reproduced offline at ' + image.width + '×' + image.height + '.');
} finally {
  browser.close();
  if (server.listening) server.close();
  await rm(dir, {recursive: true, force: true});
}
