// The development loop end to end, without a browser:
//
//   node tests/develop.mjs ROOT
//
// `lofi serve` builds a copy of tests/apps/counter, one module per library,
// and serves it with the reload client. The test plays the page's part with
// the browser host's own code: it links the modules (src/app/load.mjs),
// adds to the counter, edits the greeting, sees from the event that only
// the program's own module was compiled again, relinks from it and hands
// over the state as a page does (src/app/host.mjs). A broken edit reports a
// failed build that keeps the last good manifest. Then `lofi watch` runs a
// program again after an edit.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {cp, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {screenImports, takeState} from '../src/app/host.mjs';
import {createWasi, linkProgram, programExports, readEvent, readManifest, relinkProgram, runProgram} from '../src/app/load.mjs';
import {until} from './browser/chromium.mjs';

const PRESS = 9;
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

// The next event that ends a build, read.
function nextBuild(events) {
  const from = events.length;
  return until(() => events.slice(from).map(readEvent).find(event => event.kind === 'built' || event.kind === 'failed'), 'a build', 120);
}

// ---- The page ----

// The program's modules, linked in Node as a page links them, with the
// browser host's screen: a renderer and a picture store that draw nothing,
// and a HUD that keeps the latest widgets. `manifest` is the page's.
async function linkPage(base, manifest) {
  const page = {manifest, program: null, widgets: []};
  const screen = screenImports({hasBatch: () => false, draw() {}}, {has: () => true},
                               {update: panels => { page.widgets = panels.flatMap(panel => panel.widgets); }});
  const read = async file => new Uint8Array(await (await fetch(new URL(file, base))).arrayBuffer());
  page.program = await linkProgram(read, '/modules.json', createWasi({print: (fd, line) => console.log(line)}), {'snail.screen': screen});
  runProgram(page.program);
  return page;
}

const text = (page, key) => page.widgets.find(entry => entry.key === key)?.text;

// Relinks the page from the first module, in program order, whose file the
// build changed, as the reload client finds it, and hands the state over.
// Returns the module and how the state passed.
async function relink(page, manifest) {
  const [from] = manifest.modules.find(([name, file], index) => String(page.manifest.modules[index]) !== String([name, file]));
  const program = await relinkProgram(page.program, from);
  const passed = takeState(programExports(program), programExports(page.program), {clientWidth: 960, clientHeight: 640}, false);
  Object.assign(page, {manifest, program});
  return {from, passed};
}

// ---- Serving ----

async function testServe(directory) {
  const app = join(directory, 'counter'), source = join(app, 'main.sld');
  await cp(join(root, 'tests/apps/counter'), app, {recursive: true});
  const server = start(['serve', '--port', '0', app]);
  try {
    const base = await until(() => server.text.match(/at (http:\/\/127\.0\.0\.1:\d+\/)/)?.[1], 'the server', 300);
    const events = await listen(new URL('.lofi/events', base));
    const html = await (await fetch(base)).text();
    assert.match(html, /<script type="module" src="\/\.lofi\/reload\.mjs"><\/script>/);
    assert.match(html, /<meta name="lofi-modules" content="\/modules\.json">/);
    const manifest = readManifest(html.match(/id="lofi-manifest">([^<]*)<\/script>/)[1]);
    assert.match(manifest.modules.at(-1).join(' '), /^main \/modules\/main-\d+\.wasm$/);
    assert.equal((await fetch(new URL('.lofi/reload.wasm', base))).headers.get('content-type'), 'application/wasm');

    const page = await linkPage(base, manifest);
    programExports(page.program).app_init(1, 960, 640);
    programExports(page.program).app_input(PRESS, 1, 0, 0, 0);
    programExports(page.program).app_input(PRESS, 1, 0, 0, 0);
    assert.deepEqual([text(page, 'greeting'), text(page, 'count')], ['hello', '2']);

    await writeFile(source, (await readFile(source, 'utf8')).replace('"hello"', '"hello again"'));
    const built = await nextBuild(events);
    assert.equal(built.kind, 'built', built.message);
    assert.match(server.text, /1 of 5 modules compiled/, 'only the program\'s module is compiled again');
    assert.deepEqual(await relink(page, built.manifest), {from: 'main', passed: 'adopted'}, 'the libraries\' modules stay linked');
    assert.deepEqual([text(page, 'greeting'), text(page, 'count')], ['hello again', '2'], 'the new program keeps the state');

    await writeFile(source, (await readFile(source, 'utf8')).replace('"hello again"', '5'));
    const failed = await nextBuild(events);
    assert.equal(failed.kind, 'failed');
    assert.match(failed.message, /main\.sld:\d+:\d+: /);
    assert.deepEqual(failed.manifest, built.manifest, 'a failed build keeps the last good manifest');
    const late = await listen(new URL('.lofi/events', base));
    await until(() => late.length, 'the latest event');
    assert.equal(readEvent(late[0]).kind, 'failed', 'a page that connects later sees the failure');
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
    await until(() => watcher.text.includes('first run\n'), 'the first run', 300);
    await writeFile(source, program('second run'));
    await until(() => watcher.text.includes('second run\n'), 'the second run', 120);
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
