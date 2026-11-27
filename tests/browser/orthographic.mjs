// The games share the forward color pass and compositor. Their orthographic
// draws retain per-instance lighting and atlas transparency, respectively.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';
import {mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {observeOutput, captureFrame, assertMatches} from './renderer-trace.mjs';
import {createCanvas, loadImage} from '@napi-rs/canvas';
import {openBrowser, until} from './chromium.mjs';
import {serve} from './static.mjs';

const root = process.argv[2];
const browser = await openBrowser({hardware: process.env.SNAIL_WEBGPU_HARDWARE === '1'});
function observe() {
  window.frameTextures = {};
  window.drawPipelines = new Set();
  window.validation = [];
  const original = GPUDevice.prototype.createTexture;
  const devices = new WeakSet();
  GPUDevice.prototype.createTexture = function(desc) {
    if (!devices.has(this)) {
      devices.add(this);
      this.addEventListener('uncapturederror', event => window.validation.push(event.error.message));
    }
    const t = original.call(this, desc);
    window.frameTextures[t.label] = [t.width, t.height];
    return t;
  };
  const bind = GPURenderPassEncoder.prototype.setPipeline;
  GPURenderPassEncoder.prototype.setPipeline = function(p) {
    window.drawPipelines.add(p.label);
    return bind.call(this, p);
  };
}
async function imageColors() {
  const url = await browser.evaluate('document.querySelector("canvas")?.toDataURL()');
  if (!url?.startsWith('data:image/png;base64,')) return 0;
  const image = await loadImage(Buffer.from(url.split(',')[1], 'base64'));
  const ctx = createCanvas(96, 64).getContext('2d');
  ctx.drawImage(image, 0, 0, 96, 64);
  const {data} = ctx.getImageData(0, 0, 96, 64);
  const colors = new Set();
  for (let i = 0; i < data.length; i += 4)
    colors.add((data[i] >> 3) * 1024 + (data[i + 1] >> 3) * 32 + (data[i + 2] >> 3));
  return colors.size;
}
const temp = await mkdtemp(join(tmpdir(), 'snail-ortho-'));
try {
  await browser.send('Page.addScriptToEvaluateOnNewDocument', {source: '(' + observeOutput.toString() + ')()'});
  await browser.send('Page.addScriptToEvaluateOnNewDocument', {source: '(' + observe.toString() + ')()'});
  for (const name of ['siegework', 'hearsay']) {
    const dir = execFileSync(join(root, 'snail-scheme'), ['build', '--target', 'browser', 'src/apps/' + name + '/main.scm'], {cwd: root, encoding: 'utf8'}).trim();
    const server = await serve(dir);
    try {
      await browser.send('Emulation.setDeviceMetricsOverride', {width: 560, height: 360, deviceScaleFactor: 1, mobile: false});
      await browser.navigate('http://127.0.0.1:' + server.address().port + '/?trace=1');
      if (name === 'hearsay') {
        await until(() => browser.evaluate('!!document.querySelector("[data-key=scenario-0]")'), 'rumor mill');
        await browser.evaluate('document.querySelector("[data-key=scenario-0]").click()');
      }
      const expected = name === 'siegework' ? 'raster/forward_fragment' : 'quad';
      await until(() => browser.evaluate('window.drawPipelines.has(' + JSON.stringify(expected) + ') && window.drawPipelines.has("compositor/blit")'), name + ' forward draws', 90);
      await until(async () => await imageColors() > 12, name + ' visible geography or sprites', 45);
      await browser.send('Emulation.setDeviceMetricsOverride', {width: 360, height: 236, deviceScaleFactor: 2, mobile: false});
      await until(() => browser.evaluate('window.frameTextures["forward/output"]?.join() === "720,472"'), name + ' native-pixel resize');
      const textures = await browser.evaluate('Object.keys(window.frameTextures)');
      assert.ok(!textures.some(t => t.startsWith('shadow/') || t.startsWith('gbuffer/')), name + ' allocated unused passes');
      assert.equal(textures.includes('forward/batch-depth'), name === 'siegework');
      assert.deepEqual(await browser.evaluate('window.validation'), []);
      const snapshot = await captureFrame(browser);
      const trace = join(temp, name + '.jsonl'), png = join(temp, name + '.png');
      const headers = snapshot.trace.trimEnd().split('\n').map(l => JSON.parse(l)).filter(l => typeof l === 'object');
      const upload = name === 'siegework' ? 'setBatch' : 'updateAtlas';
      assert.ok(headers.some(c => c.op === upload && c.bytes[0] > 0), 'inline geometry or atlas texels');
      assert.ok(headers.some(c => c.op === (name === 'siegework' ? 'renderBatches' : 'renderSprites')));
      await writeFile(trace, snapshot.trace);
      execFileSync(join(root, 'snail-scheme'), ['run', '--target', 'node', 'tools/render.scm', 'replay=' + trace, 'output=' + png], {cwd: root});
      await assertMatches(snapshot.image, await readFile(png));
      console.log(name + ' presented its orthographic scene at both resolutions.');
    } finally {server.close();}
  }
} finally {browser.close(); await rm(temp, {recursive: true, force: true});}
