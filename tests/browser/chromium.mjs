// Headless Chromium with software WebGPU, driven through the DevTools
// protocol: one page, whose console output and exceptions are printed.
// CHROMIUM names the browser's executable. The tests that drive it wait
// for what they expect with `until`.
import {spawn} from 'node:child_process';
import {rmSync} from 'node:fs';
import {mkdtemp, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

export const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

// The first true value `test` resolves to, asked every tenth of a second.
export async function until(test, what, seconds = 30) {
  for (let waited = 0; waited < seconds * 10; waited++) {
    const value = await test();
    if (value) return value;
    await sleep(100);
  }
  throw new Error(`timed out waiting for ${what}`);
}

function printEvent(message) {
  if (message.method === 'Runtime.consoleAPICalled')
    console.log(`console.${message.params.type}:`, message.params.args.map(arg => arg.value ?? arg.description).join(' '));
  if (message.method === 'Runtime.exceptionThrown')
    console.log('exception:', message.params.exceptionDetails.exception?.description ?? message.params.exceptionDetails.text);
}

// The DevTools protocol goes over a pipe, not a port: the browser reads
// commands on its descriptor 3 and writes replies and events on 4, each a
// JSON message ended by a NUL, and exits when the pipe closes. So a
// browser cannot outlive the test that opened it, however the test ends,
// and a test cannot reach any browser but its own. The pipe speaks to the
// browser; its page is spoken to through a session attached to it.
export async function openBrowser() {
  const profile = await mkdtemp(join(tmpdir(), 'snail-page-'));
  const browser = spawn(process.env.CHROMIUM ?? 'chromium', ['--headless=new', '--no-sandbox', '--remote-debugging-pipe',
    `--user-data-dir=${profile}`, '--enable-unsafe-webgpu', '--enable-features=Vulkan', '--use-vulkan=swiftshader',
    '--use-angle=swiftshader', '--window-size=1280,800', 'about:blank'], {stdio: ['ignore', 'ignore', 'ignore', 'pipe', 'pipe']});
  const [, , , commands, replies] = browser.stdio;
  process.on('exit', () => { browser.kill('SIGKILL'); rmSync(profile, {recursive: true, force: true}); });
  let next = 0, session, unfinished = '';
  const pending = new Map();
  replies.setEncoding('utf8');
  replies.on('data', chunk => {
    const messages = (unfinished + chunk).split('\0');
    unfinished = messages.pop();
    for (const message of messages.map(text => JSON.parse(text))) {
      if (message.id === undefined) { printEvent(message); continue; }
      pending.get(message.id)?.(message);
      pending.delete(message.id);
    }
  });
  const send = (method, params = {}) => new Promise(resolve => {
    const id = ++next;
    pending.set(id, resolve);
    commands.write(`${JSON.stringify({id, method, params, sessionId: session})}\0`);
  });
  const page = await until(async () => (await send('Target.getTargets')).result?.targetInfos.find(target => target.type === 'page'),
    'Chromium to start');
  session = (await send('Target.attachToTarget', {targetId: page.targetId, flatten: true})).result.sessionId;
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
    close() { commands.end(); browser.kill(); },
  };
}
