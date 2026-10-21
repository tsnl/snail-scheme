// The development loop end to end, without a browser:
//
//   node tests/develop.mjs ROOT
//
// `lofi serve` builds a copy of tests/apps/counter and serves it with the
// live reload client. The test plays the page's part: it adds to the
// counter in one module, edits the greeting, takes the rebuilt module that
// the events announce, and restores the first module's save into it, as
// replaceModule in src/app/host.mjs does. A broken edit reports a failed
// build. Then `lofi watch` runs a program again after an edit.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {cp, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';

const PRESS = 9, RESIZE = 8;
const root = process.argv[2];

// ---- Processes ----

// Starts `lofi COMMAND ...` and collects what it prints, so a test can wait
// for a line to appear.
function start(args) {
  const child = spawn('node', ['--no-warnings', join(root, 'scripts/develop.mjs'), root, ...args], {stdio: ['ignore', 'pipe', 'pipe']});
  const process = {child, text: ''};
  child.stdout.on('data', chunk => { process.text += chunk; });
  child.stderr.on('data', chunk => { process.text += chunk; });
  return process;
}

async function waitFor(test, what, seconds = 120) {
  for (let waited = 0; waited < seconds * 10; waited++) {
    const value = test();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`timed out waiting for ${what}`);
}

// ---- Events ----

// Reads the server-sent events into a list, parsing each one's data.
async function listen(url) {
  const events = [];
  const response = await fetch(url);
  const decoder = new TextDecoder();
  let buffer = '';
  (async () => {
    for await (const chunk of response.body) {
      buffer += decoder.decode(chunk, {stream: true});
      const blocks = buffer.split('\n\n');
      buffer = blocks.pop();
      for (const block of blocks) {
        const kind = block.match(/^event: (.*)$/m)?.[1], data = block.match(/^data: (.*)$/m)?.[1];
        if (kind) events.push({kind, data: JSON.parse(data)});
      }
    }
  })().catch(() => {});
  return events;
}

function nextEvent(events, kinds) {
  const from = events.length;
  return waitFor(() => events.slice(from).find(event => kinds.includes(event.kind)), kinds.join(' or '));
}

// ---- Applications ----

// A module with a screen that keeps only the latest HUD's widgets.
async function instantiate(bytes) {
  let exports, widgets = [], widget = null, field = null;
  const fields = ['key', 'icon', 'help', 'badge', 'text', 'caption'];
  const view = () => new DataView(exports.memory.buffer);
  const wasi = {
    fd_write(fd, iovs, count, written) {
      let total = 0;
      for (let i = 0; i < count; i++) total += view().getUint32(iovs + 8 * i + 4, true);
      view().setUint32(written, total, true);
      return 0;
    },
    proc_exit(code) { throw new Error(`exit ${code}`); },
    environ_get: () => 0, environ_sizes_get(a, b) { view().setUint32(a, 0, true); view().setUint32(b, 0, true); return 0; },
    fd_close: () => 0, fd_prestat_get: () => 8, fd_prestat_dir_name: () => 8,
  };
  const screen = {
    'frame-begin'() {}, camera() {}, light() {}, 'batch-begin'() { return 0; }, instance() {}, 'frame-end'() {},
    'hud-begin'() { widgets = []; }, 'panel-begin'() { widget = {}; }, 'hud-end'() {},
    'widget-begin'() { widget = {key: '', text: ''}; widgets.push(widget); },
    field(which) { field = fields[which]; },
    'text-character'(code) { if (field in widget) widget[field] += String.fromCodePoint(code); },
  };
  const {instance} = await WebAssembly.instantiate(bytes, {wasi_snapshot_preview1: wasi, 'snail.screen': screen});
  exports = instance.exports;
  exports._initialize();
  exports.main();
  return {exports, text: key => widgets.find(entry => entry.key === key)?.text};
}

async function fetchModule(base) {
  return instantiate(await (await fetch(new URL('app.wasm', base))).arrayBuffer());
}

function saveBytes({exports}) {
  const length = exports.app_save();
  return Uint8Array.from({length}, (_, index) => exports.app_save_byte(index));
}

function loadBytes({exports}, bytes) {
  exports.app_load_begin(bytes.length);
  bytes.forEach((byte, index) => exports.app_load_byte(index, byte));
  exports.app_load_end();
  exports.app_input(RESIZE, 960, 640, 0, 0);
}

// ---- Serving ----

async function testServe(directory) {
  const app = join(directory, 'counter'), source = join(app, 'main.sld');
  await cp(join(root, 'tests/apps/counter'), app, {recursive: true});
  const server = start(['serve', '--port', '0', app]);
  try {
    const base = await waitFor(() => server.text.match(/at (http:\/\/127\.0\.0\.1:\d+\/)/)?.[1], 'the server', 300);
    const events = await listen(new URL('.lofi/events', base));
    assert.match(await (await fetch(base)).text(), /<script type="module" src="\/\.lofi\/reload\.mjs"><\/script><\/body>/);
    assert.equal((await fetch(new URL('.lofi/reload.mjs', base))).headers.get('content-type'), 'text/javascript');
    assert.equal((await fetch(new URL('app.wasm', base))).headers.get('content-type'), 'application/wasm');

    const first = await fetchModule(base);
    first.exports.app_init(1, 960, 640);
    first.exports.app_input(PRESS, 1, 0, 0, 0);
    first.exports.app_input(PRESS, 1, 0, 0, 0);
    assert.deepEqual([first.text('greeting'), first.text('count')], ['hello', '2']);

    await writeFile(source, (await readFile(source, 'utf8')).replace('"hello"', '"hello again"'));
    const built = await nextEvent(events, ['built', 'failed']);
    assert.equal(built.kind, 'built', built.data.message);
    assert.deepEqual(built.data.changed, ['app.wasm']);
    const second = await fetchModule(base);
    loadBytes(second, saveBytes(first));
    assert.deepEqual([second.text('greeting'), second.text('count')], ['hello again', '2'], 'the new module keeps the count');

    await writeFile(source, (await readFile(source, 'utf8')).replace('"hello again"', '5'));
    const failed = await nextEvent(events, ['built', 'failed']);
    assert.equal(failed.kind, 'failed');
    assert.match(failed.data.message, /main\.sld:\d+:\d+: /);
    const late = await listen(new URL('.lofi/events', base));
    await waitFor(() => late.find(event => event.kind === 'status'), 'the status');
    assert.equal(late[0].data.state, 'failed', 'a page that connects later sees the failure');
  } finally {
    server.child.kill();
  }
}

// ---- Watching ----

async function testWatch(directory) {
  const source = join(directory, 'hello.sld');
  const program = message => `(import (lofi base) (lofi io))\n(write-string "${message}\\n")\n`;
  await writeFile(source, program('first run'));
  const watcher = start(['watch', source]);
  try {
    await waitFor(() => watcher.text.includes('first run\n'), 'the first run', 300);
    await writeFile(source, program('second run'));
    await waitFor(() => watcher.text.includes('second run\n'), 'the second run');
  } finally {
    watcher.child.kill();
  }
}

const directory = await mkdtemp(join(tmpdir(), 'lofi-develop-'));
try {
  await testServe(directory);
  await testWatch(directory);
  console.log('develop: serve and watch passed');
} finally {
  await rm(directory, {recursive: true, force: true});
}
