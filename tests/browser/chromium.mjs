// Headless Chromium with software WebGPU, driven through the DevTools
// protocol: one page, whose console output and exceptions are printed.
// CHROMIUM names the browser's executable.
import {spawn} from 'node:child_process';
import {mkdtemp, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

export const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

async function pageSocketUrl(port) {
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

function printEvent(message) {
  if (message.method === 'Runtime.consoleAPICalled')
    console.log(`console.${message.params.type}:`, message.params.args.map(arg => arg.value ?? arg.description).join(' '));
  if (message.method === 'Runtime.exceptionThrown')
    console.log('exception:', message.params.exceptionDetails.exception?.description ?? message.params.exceptionDetails.text);
}

export async function openBrowser() {
  const profile = await mkdtemp(join(tmpdir(), 'lofi-page-'));
  const port = 9300 + Math.floor(Math.random() * 500);
  const browser = spawn(process.env.CHROMIUM ?? 'chromium', ['--headless=new', '--no-sandbox', `--remote-debugging-port=${port}`,
    `--user-data-dir=${profile}`, '--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader',
    '--use-angle=swiftshader', '--window-size=1280,800', 'about:blank'], {stdio: 'ignore'});
  const socket = new WebSocket(await pageSocketUrl(port));
  await new Promise(resolve => socket.addEventListener('open', resolve));
  let next = 0;
  const pending = new Map();
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.id === undefined) { printEvent(message); return; }
    pending.get(message.id)?.(message);
    pending.delete(message.id);
  });
  const send = (method, params = {}) => new Promise(resolve => {
    const id = ++next;
    pending.set(id, resolve);
    socket.send(JSON.stringify({id, method, params}));
  });
  await send('Runtime.enable');
  await send('Page.enable');
  return {
    send,
    navigate: url => send('Page.navigate', {url}),
    async evaluate(expression) {
      return (await send('Runtime.evaluate', {expression, returnByValue: true, awaitPromise: true})).result?.result?.value;
    },
    async screenshot(path) {
      await writeFile(path, Buffer.from((await send('Page.captureScreenshot', {format: 'png'})).result.data, 'base64'));
    },
    close() { socket.close(); browser.kill(); },
  };
}
