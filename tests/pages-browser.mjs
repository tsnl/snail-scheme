// Run the generated Pages site under its real project prefix in a private browser.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {existsSync, mkdtempSync, readFileSync, rmSync, statSync} from 'node:fs';
import {extname, join, resolve, sep} from 'node:path';
import {tmpdir} from 'node:os';
import {checkPages} from '../scripts/check-pages.mjs';

const site = resolve(process.argv[2] ?? 'build/pages');
const profile = mkdtempSync(join(tmpdir(), 'snail-pages-browser-'));
const prefix = '/snail-scheme/', missing = [];
const types = {'.html': 'text/html', '.mjs': 'text/javascript', '.js': 'text/javascript',
  '.css': 'text/css', '.json': 'application/json', '.wasm': 'application/wasm', '.wgsl': 'text/plain',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.woff': 'font/woff', '.woff2': 'font/woff2'};
const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

async function until(check, message) {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline) { const value = await check(); if (value) return value; await delay(50); }
  throw new Error(message);
}

const server = createServer((request, response) => {
  const path = new URL(request.url, 'http://localhost').pathname;
  let file = resolve(site, decodeURIComponent(path.slice(prefix.length)));
  if (path.startsWith(prefix) && existsSync(file) && statSync(file).isDirectory()) file = join(file, 'index.html');
  if (!path.startsWith(prefix) || !file.startsWith(site + sep) || !existsSync(file)) {
    if (path !== '/favicon.ico') missing.push(path);
    response.writeHead(404); response.end('Not found'); return;
  }
  response.writeHead(200, {'content-type': types[extname(file)] ?? 'application/octet-stream', 'cache-control': 'no-store'});
  response.end(readFileSync(file));
});

let browser, socket, sequence = 0;
const pending = new Map();
function call(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++sequence, timer = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 30000);
    pending.set(id, value => { clearTimeout(timer); value.error ? reject(new Error(value.error.message)) : resolve(value.result); });
    socket.send(JSON.stringify({id, method, params}));
  });
}
async function evaluate(expression) {
  const value = await call('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
  if (value.exceptionDetails) throw new Error(value.exceptionDetails.exception?.description ?? value.exceptionDetails.text);
  return value.result.value;
}
async function ready() {
  await until(async () => {
    const state = await evaluate("({ready: !!globalThis.snailApp, note: document.querySelector('[data-connection]')?.textContent})");
    if (state.note?.startsWith('Cannot start:')) throw new Error(state.note);
    return state.ready;
  }, 'Siegework did not start');
}

try {
  const manifest = checkPages(site);
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  const base = `http://127.0.0.1:${server.address().port}${prefix}`;
  const game = base + 'play/siegework/', guide = base + 'games/siegework.html';
  const packaged = await (await fetch(game + 'manifest.json')).json();
  assert.match((await fetch(game + packaged.module)).headers.get('content-type'), /^application\/wasm/);
  browser = spawn(process.env.CHROMIUM ?? 'chromium', ['--headless=new', '--no-sandbox', '--enable-unsafe-webgpu',
    '--disable-dev-shm-usage', '--no-first-run', '--window-size=1280,900', '--enable-features=Vulkan', '--use-angle=vulkan',
    '--use-vulkan=swiftshader', '--use-webgpu-adapter=swiftshader', '--disable-vulkan-surface',
    '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank'], {stdio: 'ignore'});
  const portFile = join(profile, 'DevToolsActivePort');
  await until(() => existsSync(portFile), 'private Chromium did not start');
  const devtools = `http://127.0.0.1:${readFileSync(portFile, 'utf8').split('\n')[0]}`;
  const target = await (await fetch(`${devtools}/json/new?about:blank`, {method: 'PUT'})).json();
  socket = new WebSocket(target.webSocketDebuggerUrl); await once(socket, 'open');
  socket.onmessage = event => {
    const value = JSON.parse(event.data); if (value.id) { pending.get(value.id)?.(value); pending.delete(value.id); }
  };
  await call('Page.enable'); await call('Page.navigate', {url: guide});
  await until(() => evaluate(`document.readyState === 'complete' && location.href === ${JSON.stringify(guide)}`), 'guide did not load');
  assert.equal(await evaluate("document.querySelector('main h1').textContent.trim()"), 'Siegework');
  await until(() => evaluate('navigator.gpu.requestAdapter().then(adapter => !!adapter)'), 'private Chromium WebGPU did not become available');
  await evaluate("[...document.querySelectorAll('main a')].find(link => link.textContent === 'Play Siegework').click()");
  await ready(); assert.equal(await evaluate('location.href'), game);
  assert.equal(await evaluate("document.querySelector('.player-help').checkVisibility()"), false);
  assert.equal(await evaluate('snailApp.generation'), manifest.generation);
  console.log('ok - guide Play link boots actual Wasm and WebGPU under /snail-scheme/play/siegework/');

  await evaluate("snailApp.local('pause-menu')");
  await until(() => evaluate("document.querySelector('[data-ui-key=resume]')?.disabled === false"), 'pause did not settle');
  for (const [width, height] of [[1280, 900], [390, 844], [320, 568], [844, 390], [640, 360], [480, 320]]) {
    await call('Emulation.setDeviceMetricsOverride', {width, height, deviceScaleFactor: 1, mobile: width < 700});
    await until(() => evaluate(`snailApp.viewport?.[0] === ${width} && snailApp.viewport?.[1] === ${height} && !snailApp.dirty`), 'viewport did not settle');
    const result = await evaluate(`(() => {
      const help = document.querySelector('.player-help'), rect = help.getBoundingClientRect(); help.focus();
      const overlaps = [...document.querySelectorAll('[data-ui-key=pause-dialog]')].some(node => {
        const other = node.getBoundingClientRect();
        return node.checkVisibility() && rect.left < other.right && other.left < rect.right && rect.top < other.bottom && other.top < rect.bottom;
      });
      return {visible: help.checkVisibility(), focused: document.activeElement === help, hit: document.elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2) === help,
        fits: rect.left >= 0 && rect.top >= 0 && rect.right <= innerWidth && rect.bottom <= innerHeight, touch: rect.width >= 44 && rect.height >= 44,
        overlaps, href: help.href, target: help.target, rel: help.rel};
    })()`);
    assert.deepEqual(result, {visible: true, focused: true, hit: true, fits: true, touch: true, overlaps: false,
      href: 'https://tsnl.github.io/snail-scheme/games/siegework.html', target: '_blank', rel: 'noopener'}, `${width} × ${height}`);
  }
  console.log('ok - paused Help is focusable, tappable and clear of menus at six desktop/phone/landscape sizes');
  await evaluate("snailApp.local('resume')");
  await until(() => evaluate("!document.querySelector('.player-help').checkVisibility()"), 'Help stayed visible after Resume');
  assert.equal(await evaluate("document.querySelector('.player-help').getClientRects().length"), 0);
  assert.deepEqual(missing, []);
  console.log('ok - Resume removes the Help hit target; browser requested no missing site assets');
} finally {
  socket?.close();
  if (browser && browser.exitCode === null && browser.signalCode === null) {
    const ended = once(browser, 'exit'); browser.kill('SIGTERM'); await ended;
  }
  await new Promise(resolve => server.close(resolve));
  rmSync(profile, {recursive: true, force: true});
}
