// Opens a page in headless Chromium through the DevTools protocol, reports
// console output and errors, runs any JavaScript steps a second apart, and
// saves a screenshot:  node page.mjs URL SCREENSHOT [SECONDS] [STEP ...]
import {spawn} from 'node:child_process';
import {writeFile, mkdtemp} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const [url, screenshot, seconds = '6', ...steps] = process.argv.slice(2);
const chrome = process.env.CHROMIUM ?? 'chromium';
const profile = await mkdtemp(join(tmpdir(), 'lofi-page-'));
const port = 9300 + Math.floor(Math.random() * 500);
const browser = spawn(chrome, ['--headless=new', '--no-sandbox', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  '--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader', '--use-angle=swiftshader',
  '--window-size=1280,800', 'about:blank'], {stdio: 'ignore'});
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function target() {
  for (let i = 0; i < 100; i++) {
    try {
      const pages = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      const page = pages.find(entry => entry.type === 'page');
      if (page) return page.webSocketDebuggerUrl;
    } catch {}
    await sleep(100);
  }
  throw new Error('Chromium did not start');
}

const socket = new WebSocket(await target());
await new Promise(resolve => socket.addEventListener('open', resolve));
let next = 0;
const pending = new Map();
socket.addEventListener('message', event => {
  const message = JSON.parse(event.data);
  if (message.id !== undefined) { pending.get(message.id)?.(message); pending.delete(message.id); return; }
  if (message.method === 'Runtime.consoleAPICalled')
    console.log(`console.${message.params.type}:`, message.params.args.map(arg => arg.value ?? arg.description).join(' '));
  if (message.method === 'Runtime.exceptionThrown')
    console.log('exception:', message.params.exceptionDetails.exception?.description ?? message.params.exceptionDetails.text);
});
const send = (method, params = {}) => new Promise(resolve => {
  const id = ++next;
  pending.set(id, resolve);
  socket.send(JSON.stringify({id, method, params}));
});

await send('Runtime.enable');
await send('Page.enable');
await send('Page.navigate', {url});
await sleep(Number(seconds) * 1000);
for (const step of steps) {
  const result = await send('Runtime.evaluate', {expression: step, returnByValue: true});
  console.log('step:', step, '->', JSON.stringify(result.result?.result?.value));
  await sleep(1000);
}
const state = await send('Runtime.evaluate', {expression: 'JSON.stringify(document.body.dataset)', returnByValue: true});
console.log('page state:', state.result?.result?.value);
const shot = await send('Page.captureScreenshot', {format: 'png'});
await writeFile(screenshot, Buffer.from(shot.result.data, 'base64'));
socket.close();
browser.kill();
