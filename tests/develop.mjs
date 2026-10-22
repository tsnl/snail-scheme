// The development loop end to end, without a browser:
//
//   node tests/develop.mjs ROOT
//
// `lofi serve` builds a copy of tests/apps/counter, one module per library,
// and serves it with the reload client. The test plays the page's part: it
// links the modules (src/app/load.mjs), adds to the counter, edits the
// greeting, sees from the event that only the program's own module was
// compiled again, relinks from it and hands over the state as host.mjs
// does. A broken edit reports a failed build that keeps the last good
// manifest. Then `lofi watch` runs a program again after an edit.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {cp, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {instantiateRuntime, linkModules, loadManifest, runModules} from '../src/app/load.mjs';

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
    const value = await test();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error(`timed out waiting for ${what}`);
}

// ---- Events ----

// Reads the server-sent events into a list of their texts.
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
        const lines = block.split('\n').filter(line => line.startsWith('data: ')).map(line => line.slice(6));
        if (lines.length) events.push(lines.join('\n'));
      }
    }
  })().catch(() => {});
  return events;
}

function nextEvent(events, kinds) {
  const from = events.length;
  return waitFor(() => events.slice(from).find(event => kinds.some(kind => event.startsWith(`(${kind}`))), kinds.join(' or '));
}

// ---- The page ----

// The program's modules, linked in Node with a screen that keeps only the
// latest HUD's widgets, as a page links them.
async function linkPage(base) {
  const page = {widgets: [], runtime: null, linked: null};
  const read = async file => new Uint8Array(await (await fetch(new URL(file, base))).arrayBuffer());
  const loaded = await loadManifest(read, '/modules.json');
  page.runtime = await instantiateRuntime(loaded.runtime, {wasi_snapshot_preview1: {}});
  page.runtime.exports._initialize();
  page.host = {'snail.screen': screen(page)};
  page.linked = await linkModules(page.runtime, loaded.modules, page.host);
  runModules(page.linked, loaded.modules.map(entry => entry.name));
  page.modules = loaded.modules.map(({name, file}) => ({name, file}));
  page.exports = page.linked.get('main').exports;
  return page;
}

function screen(page) {
  let widget = null, field = null;
  const fields = ['key', 'icon', 'help', 'badge', 'text', 'caption'];
  return {
    'frame-begin'() {}, camera() {}, light() {}, 'batch-begin'() { return 0; }, instance() {}, 'frame-end'() {}, 'hud-end'() {},
    'hud-begin'() { page.widgets = []; },
    'panel-begin'() { widget = {}; },
    'widget-begin'() { widget = {key: '', text: ''}; page.widgets.push(widget); },
    field(which) { field = fields[which]; },
    'text-character'(code) { if (field in widget) widget[field] += String.fromCodePoint(code); },
  };
}

const text = (page, key) => page.widgets.find(entry => entry.key === key)?.text;

// Relinks from the first module whose file changed, keeping the instances
// before it, and hands the state over, as relinkModules in host.mjs does.
async function relink(page, base) {
  const {modules} = JSON.parse(await (await fetch(new URL('/modules.json', base))).text());
  const start = modules.findIndex((entry, index) => entry.file !== page.modules[index]?.file);
  const kept = new Map(modules.slice(0, start).map(entry => [entry.name, page.linked.get(entry.name)]));
  const fresh = await Promise.all(modules.slice(start).map(async entry => (
    {...entry, module: await WebAssembly.compile(await (await fetch(new URL(entry.file, base))).arrayBuffer())})));
  const linked = await linkModules(page.runtime, fresh, page.host, kept);
  runModules(linked, fresh.map(entry => entry.name));
  const next = linked.get('main').exports;
  next.app_adopt(page.exports.app_state());
  next.app_input(RESIZE, 960, 640, 0, 0);
  return {...page, linked, exports: next, modules: modules.map(({name, file}) => ({name, file})), relinkedFrom: modules[start].name};
}

// ---- Serving ----

async function testServe(directory) {
  const app = join(directory, 'counter'), source = join(app, 'main.sld');
  await cp(join(root, 'tests/apps/counter'), app, {recursive: true});
  const server = start(['serve', '--port', '0', app]);
  try {
    const base = await waitFor(() => server.text.match(/at (http:\/\/127\.0\.0\.1:\d+\/)/)?.[1], 'the server', 300);
    const events = await listen(new URL('.lofi/events', base));
    const html = await (await fetch(base)).text();
    assert.match(html, /<script type="module" src="\/\.lofi\/reload\.mjs"><\/script>/);
    assert.match(html, /<meta name="lofi-modules" content="\/modules\.json">/);
    assert.match(html, /id="lofi-manifest">\(files .*\(modules .*\("main" "\/modules\/main-\d+\.wasm"\)\)<\/script>/);
    assert.equal((await fetch(new URL('.lofi/reload.wasm', base))).headers.get('content-type'), 'application/wasm');

    let page = await linkPage(base);
    page.exports.app_init(1, 960, 640);
    page.exports.app_input(PRESS, 1, 0, 0, 0);
    page.exports.app_input(PRESS, 1, 0, 0, 0);
    assert.deepEqual([text(page, 'greeting'), text(page, 'count')], ['hello', '2']);

    await writeFile(source, (await readFile(source, 'utf8')).replace('"hello"', '"hello again"'));
    const built = await nextEvent(events, ['built', 'failed']);
    assert.match(built, /^\(built \d+ /, built);
    assert.match(server.text, /1 of 5 modules compiled/, 'only the program\'s module is compiled again');
    page = await relink(page, base);
    assert.equal(page.relinkedFrom, 'main', 'the libraries\' modules stay linked');
    assert.deepEqual([text(page, 'greeting'), text(page, 'count')], ['hello again', '2'], 'the new program keeps the state');

    await writeFile(source, (await readFile(source, 'utf8')).replace('"hello again"', '5'));
    const failed = await nextEvent(events, ['built', 'failed']);
    assert.match(failed, /^\(failed "[^"]*main\.sld:\d+:\d+: /);
    assert.ok(failed.endsWith(built.slice(built.indexOf('(files'))), 'a failed build keeps the last good manifest');
    const late = await listen(new URL('.lofi/events', base));
    await waitFor(() => late.length, 'the latest event');
    assert.ok(late[0].startsWith('(failed'), 'a page that connects later sees the failure');
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
