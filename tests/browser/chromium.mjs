// Headless Chromium with software or native WebGPU, driven through the DevTools
// protocol: one page, whose console output and exceptions are printed.
// CHROMIUM names the browser's executable, `chromium` by default, which
// shell.nix provides on Linux. The tests that drive it wait
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

// What a trace records: the page's own spans, its measures
// (host/browser/trace.mjs), the main thread's tasks and frames, V8's
// work, and the GPU process's.
const TRACED = ['blink.user_timing', 'devtools.timeline', 'disabled-by-default-devtools.timeline.frame', 'v8.execute', 'gpu'];

// The DevTools protocol goes over a pipe, not a port: the browser reads
// commands on its descriptor 3 and writes replies and events on 4, each a
// JSON message ended by a NUL, and exits when the pipe closes. So a
// browser cannot outlive the test that opened it, however the test ends,
// and a test cannot reach any browser but its own. The pipe speaks to the
// browser; its page is spoken to through a session attached to it.
// WebGPU's developer features are on, so the device's timestamps are not
// rounded to 100 microseconds.
export async function openBrowser({hardware = false} = {}) {
  const profile = await mkdtemp(join(tmpdir(), 'snail-page-'));
  const backend = hardware
    ? ['--disable-vulkan-surface', '--use-angle=vulkan', '--enable-gpu', '--ignore-gpu-blocklist']
    : ['--use-vulkan=swiftshader', '--use-angle=swiftshader'];
  const browser = spawn(process.env.CHROMIUM ?? 'chromium', ['--headless=new', '--no-sandbox', '--remote-debugging-pipe',
    `--user-data-dir=${profile}`, '--enable-unsafe-webgpu', '--enable-webgpu-developer-features', '--enable-features=Vulkan',
    ...backend, '--window-size=1280,800', 'about:blank'], {stdio: ['ignore', 'ignore', 'ignore', 'pipe', 'pipe']});
  const [, , , commands, replies] = browser.stdio;
  process.on('exit', () => { browser.kill('SIGKILL'); rmSync(profile, {recursive: true, force: true}); });
  let next = 0, session, unfinished = '', traced = null, traceComplete = null;
  const pending = new Map();
  replies.setEncoding('utf8');
  replies.on('data', chunk => {
    const messages = (unfinished + chunk).split('\0');
    unfinished = messages.pop();
    for (const message of messages.map(text => JSON.parse(text))) {
      if (message.method === 'Tracing.dataCollected') traced.push(...message.params.value);
      if (message.method === 'Tracing.tracingComplete') traceComplete();
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
    // A trace from here until `stopTrace`, written to `path` in Chrome's
    // JSON trace format, which Perfetto (ui.perfetto.dev) opens.
    startTrace() {
      traced = [];
      return send('Tracing.start', {traceConfig: {includedCategories: TRACED}, transferMode: 'ReportEvents'});
    },
    async stopTrace(path) {
      const complete = new Promise(resolve => { traceComplete = resolve; });
      await send('Tracing.end');
      await complete;
      await writeFile(path, JSON.stringify({traceEvents: traced}));
    },
    close() { commands.end(); browser.kill(); },
  };
}
