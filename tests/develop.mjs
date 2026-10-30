// The development loop end to end, without a browser:
//
//   node tests/develop.mjs ROOT
//
// `./scripts/snail-tool serve` builds a copy of tests/apps/counter, one module per library,
// and serves it with the reload client. The test plays the page's part with
// the browser host's own code: it links the modules (host/browser/load.mjs),
// adds to the counter, edits the greeting, sees from the event that only
// the program's own module was compiled again, relinks from it and hands
// over the state as a page does (host/browser/host.mjs). Only the modules of the
// last two builds stay. A broken edit reports a failed build that keeps the
// last good manifest. An application with a `generate-library` builds, its
// producer running in every build. An application that links a file reads
// it, and reads it again after an edit, which compiles nothing, and so it
// does when that file and a public file are symbolic links. Then
// `./scripts/snail-tool watch` runs a program again after an edit, and after
// each of two saves that rename a new file over it, as `sed -i` does, the
// second of which Node's watch alone misses (#547).
import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import {once} from 'node:events';
import {createHash} from 'node:crypto';
import {constants} from 'node:fs';
import {cp, mkdir, mkdtemp, open, readFile, readdir, rename, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {basename, join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {screenImports} from '../host/browser/host.mjs';
import {createRuntime, applicationEntry} from '../host/browser/runtime.mjs';
import {createWasi, linkProgram, readEvent, readManifest, relinkProgram, runProgram} from '../host/browser/load.mjs';
import {until} from './browser/chromium.mjs';

const PRESS = 9;
const root = process.argv[2];

// ---- Processes ----

// Starts `snail COMMAND ...` and collects what it prints, so a test can wait
// for a line to appear.
function start(args, env = process.env) {
  const child = spawn('node', ['--no-warnings', join(root, 'host/native/develop.mjs'), root, ...args], {env, stdio: ['ignore', 'pipe', 'pipe']});
  const process = {child, text: ''};
  child.stdout.on('data', chunk => { process.text += chunk; });
  child.stderr.on('data', chunk => { process.text += chunk; });
  return process;
}

async function stop(process) {
  const {child} = process;
  if (child.exitCode !== null || child.signalCode !== null) return;
  const exited = once(child, 'exit');
  child.kill();
  const timer = setTimeout(() => child.kill('SIGKILL'), 10_000);
  const [, signal] = await exited;
  clearTimeout(timer);
  assert.notEqual(signal, 'SIGKILL', 'the host closes its worker, watchers, server and child');
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
function nextBuild(events, from = events.length) {
  return until(() => events.slice(from).map(readEvent).find(event => event.kind === 'built' || event.kind === 'failed'), 'a build', 120);
}

// ---- The page ----

// The program's modules, linked in Node as a page links them, with the
// browser host's screen: a renderer and a picture store that draw nothing,
// and a HUD that keeps the latest widgets. `manifest` is the page's.
async function linkPage(base, manifest) {
  const page = {manifest, program: null, widgets: [], runtime: createRuntime()};
  const screen = screenImports({hasBatch: () => false, draw() {}}, {has: () => true},
                               {update: panels => { page.widgets = panels.flatMap(panel => panel.widgets); }});
  const read = async file => new Uint8Array(await (await fetch(new URL(file, base))).arrayBuffer());
  page.program = await linkProgram(read, '/modules.json', createWasi({print: (fd, line) => console.log(line)}), {...page.runtime.imports, 'snail.runtime.browser.screen': screen});
  runProgram(page.program);
  await page.runtime.start(applicationEntry(page.program)).ready.promise;
  return page;
}

const text = (page, key) => page.widgets.find(entry => entry.key === key)?.text;

// Relinks the page from the first module, in program order, whose file the
// build changed, as the reload client finds it, and hands the state over.
// Returns the module and how the state passed.
async function relink(page, manifest) {
  const [from] = manifest.modules.find((entry, index) => entry.join(' ') !== page.manifest.modules[index]?.join(' '));
  const {state, saved} = await page.runtime.stop();
  const program = await relinkProgram(page.program, from);
  const boot = await page.runtime.start(applicationEntry(program), state, {restore: saved}).ready.promise;
  const passed = ['adopted', 'saved', 'fresh'][boot];
  Object.assign(page, {manifest, program});
  return {from, passed};
}

// ---- Serving ----

async function testServe(directory) {
  const app = join(directory, 'counter'), source = join(app, 'main.sld');
  await cp(join(root, 'tests/apps/counter'), app, {recursive: true});
  const gate = join(directory, 'publication');
  const preload = pathToFileURL(join(root, 'tests/compiler-inputs/publication-gate.mjs')).href;
  const server = start(['serve', '--port', '0', app], {...process.env, SNAIL_TEST_PUBLICATION_GATE: gate,
    SNAIL_TEST_PUBLICATION_PATH: join(root, 'build/serve/counter/modules.json'),
    NODE_OPTIONS: [process.env.NODE_OPTIONS, `--import=${preload}`].filter(Boolean).join(' ')});
  try {
    const base = await until(() => server.text.match(/at (http:\/\/127\.0\.0\.1:\d+\/)/)?.[1], 'the server', 300);
    const events = await listen(new URL('.snail/events', base));
    const initial = await nextBuild(events, 0);
    assert.equal(initial.kind, 'built', initial.message);
    const html = await (await fetch(base)).text();
    assert.match(html, /<script type="module" src="\/\.snail\/reload\.mjs"><\/script>/);
    assert.match(html, /<meta name="snail-modules" content="\/modules\.json">/);
    const manifest = readManifest(html.match(/id="snail-manifest">([^<]*)<\/script>/)[1]);
    assert.match(manifest.modules.at(-1).join(' '), /^main \/modules\/main-\d+\.wasm$/);
    assert.equal((await fetch(new URL('.snail/reload.wasm', base))).headers.get('content-type'), 'application/wasm');

    const page = await linkPage(base, manifest);
    page.runtime.send(PRESS, 1);
    page.runtime.send(PRESS, 1);
    await new Promise(setImmediate);
    assert.deepEqual([text(page, 'greeting'), text(page, 'count')], ['hello', '2']);

    const before = await (await fetch(new URL('modules.json', base))).text();
    const from = events.length;
    await writeFile(`${gate}.armed`, 'armed');
    await writeFile(source, (await readFile(source, 'utf8')).replace('"hello"', '"hello again"'));
    await until(() => readFile(`${gate}.entered`, 'utf8').catch(() => false), 'publication ready');
    assert.equal(await (await fetch(new URL('modules.json', base), {signal: AbortSignal.timeout(2000)})).text(), before,
      'the old complete manifest remains visible while its replacement is staged');
    assert.equal(await (await fetch(base, {signal: AbortSignal.timeout(2000)})).text(), html,
      'the old complete page remains visible');
    await writeFile(`${gate}.released`, 'released');
    const built = await nextBuild(events, from);
    assert.equal(built.kind, 'built', built.message);
    await until(() => new RegExp(`1 of ${manifest.modules.length} modules compiled`).test(server.text), 'only the program module compiles again');
    assert.deepEqual(await relink(page, built.manifest), {from: 'main', passed: 'adopted'}, 'the libraries\' modules stay linked');
    assert.deepEqual([text(page, 'greeting'), text(page, 'count')], ['hello again', '2'], 'the new program keeps the state');
    const kept = new Set([...manifest.modules, ...built.manifest.modules].map(([, file]) => basename(file)));
    assert.deepEqual((await readdir(join(root, 'build/serve/counter/modules'))).sort(), [...kept].sort(), 'the last two builds\' modules stay');

    await writeFile(source, (await readFile(source, 'utf8')).replace('"hello again"', '5'));
    const failed = await nextBuild(events);
    assert.equal(failed.kind, 'failed');
    assert.match(failed.message, /main\.sld:\d+:\d+: /);
    assert.deepEqual(failed.manifest, built.manifest, 'a failed build keeps the last good manifest');
    const late = await listen(new URL('.snail/events', base));
    await until(() => late.length, 'the latest event');
    assert.equal(readEvent(late[0]).kind, 'failed', 'a page that connects later sees the failure');
    await writeFile(source, (await readFile(source, 'utf8')).replace('(define greeting 5)', '(define greeting "repaired")'));
    const repaired = await nextBuild(events);
    assert.equal(repaired.kind, 'built', repaired.message);
    await relink(page, repaired.manifest);
    assert.deepEqual([text(page, 'greeting'), text(page, 'count')], ['repaired', '2'], 'compiler panic recovery keeps the session and application state');
    await page.runtime.stop();
  } finally {
    await writeFile(`${gate}.released`, 'released');
    await stop(server);
  }
}

// ---- Generated libraries ----

// The counter's greeting comes from a `generate-library` recipe whose
// producer reads a file of the application. The plan runs the producer
// before the program is compiled; editing the file builds again, and the
// producer runs again with it.
async function testGenerated(directory) {
  const app = join(directory, 'generated'), source = join(app, 'main.sld'), message = join(app, 'greeting.txt');
  await cp(join(root, 'tests/apps/counter'), app, {recursive: true});
  await mkdir(join(app, 'src/sample'), {recursive: true});
  await writeFile(message, 'generated');
  await writeFile(join(app, 'src/sample/greeting.sld'), `(generate-library (sample greeting)
    (import (snail core base) (snail core io) (snail shell syntax))
    (library-syntax (list "sample" "greeting") (list "greeting") (list (list "snail" "core" "base"))
      (list (form ":" (list (SymbolSyntax "greeting") (SymbolSyntax "String")))
            (form "define" (list (SymbolSyntax "greeting") (StringSyntax (read-file "${message}")))))))`);
  const program = (await readFile(source, 'utf8')).replace('(snail shell app))', '(snail shell app)\n (sample greeting))');
  await writeFile(source, program.replace('(: greeting String)\n(define greeting "hello")\n', ''));
  const server = start(['serve', '--port', '0', app]);
  try {
    const base = await until(() => server.text.match(/at (http:\/\/127\.0\.0\.1:\d+\/)/)?.[1], 'the server', 300);
    const events = await listen(new URL('.snail/events', base));
    const built = await nextBuild(events, 0);
    assert.equal(built.kind, 'built', built.message);
    const page = await linkPage(base, built.manifest);
    assert.equal(text(page, 'greeting'), 'generated');
    const from = events.length;
    await writeFile(message, 'generated again');
    const rebuilt = await nextBuild(events, from);
    assert.equal(rebuilt.kind, 'built', rebuilt.message);
    assert.equal((await relink(page, rebuilt.manifest)).from, 'sample.greeting');
    assert.equal(text(page, 'greeting'), 'generated again', 'the producer runs again in every build');
    await page.runtime.stop();
  } finally {
    await stop(server);
  }
}

// ---- Linked files ----

// The counter, its greeting the text of the file (sample banner) links:
// src/sample/banner.txt, which the caller makes.
async function linkedCounter(app) {
  const source = join(app, 'main.sld');
  await cp(join(root, 'tests/apps/counter'), app, {recursive: true});
  await mkdir(join(app, 'src/sample'), {recursive: true});
  await writeFile(join(app, 'src/sample/banner.sld'), `(define-library (sample banner) (export banner)
    (import (snail core base) (snail shell resource))
    (begin (: banner Resource) (define banner (link-bytes "banner.txt"))))`);
  const program = (await readFile(source, 'utf8')).replace('(snail shell app))', '(snail shell app)\n (snail shell resource)\n (sample banner))');
  await writeFile(source, program.replace('(define greeting "hello")',
    '(define greeting (list->string (map (lambda (byte) (i32->char (u8->i32 byte))) (vector->list (read-resource banner)))))'));
}

// The counter's greeting is the text of a file a library links. The page
// reads it before the program starts; editing the file compiles nothing,
// yet renames the linking library's module, so the page relinks from it
// and reads the new bytes.
async function testLinked(directory) {
  const app = join(directory, 'linked'), banner = join(app, 'src/sample/banner.txt');
  await linkedCounter(app);
  await writeFile(banner, 'linked');
  const server = start(['serve', '--port', '0', app]);
  try {
    const base = await until(() => server.text.match(/at (http:\/\/127\.0\.0\.1:\d+\/)/)?.[1], 'the server', 300);
    const events = await listen(new URL('.snail/events', base));
    const built = await nextBuild(events, 0);
    assert.equal(built.kind, 'built', built.message);
    assert.equal(await (await fetch(new URL('resources/sample.banner/banner.txt', base))).text(), 'linked', 'the server serves the linked file');
    const page = await linkPage(base, built.manifest);
    page.runtime.send(PRESS, 1);
    await new Promise(setImmediate);
    assert.deepEqual([text(page, 'greeting'), text(page, 'count')], ['linked', '1']);
    const from = events.length;
    await writeFile(banner, 'linked again');
    const rebuilt = await nextBuild(events, from);
    assert.equal(rebuilt.kind, 'built', rebuilt.message);
    await until(() => new RegExp(`0 of ${built.manifest.modules.length} modules compiled`).test(server.text), 'nothing compiles again');
    assert.deepEqual(await relink(page, rebuilt.manifest), {from: 'sample.banner', passed: 'adopted'});
    assert.deepEqual([text(page, 'greeting'), text(page, 'count')], ['linked again', '1'], 'the relinked module reads the file again');
    await page.runtime.stop();
  } finally {
    await stop(server);
  }
}

// ---- Symbolic links ----

// The linked file and a public file are symbolic links to files elsewhere
// in the application. Reads follow a link, and so do digests: editing the
// file the linked link names relinks the page from the linking library's
// module, and editing the one the public link names changes its digest in
// the page's manifest, which the reload client compares. An editor's lock,
// a link to nothing, is no page file; any other link to nothing fails the
// build, naming the link.
async function testSymlinked(directory) {
  const app = join(directory, 'symlinked'), files = join(app, 'files');
  const banner = join(files, 'banner.txt'), notes = join(files, 'notes.txt');
  const sha256 = text => createHash('sha256').update(text).digest('hex');
  const digestOf = (manifest, name) => manifest.files.find(([file]) => file === name)?.[1];
  await linkedCounter(app);
  await mkdir(files);
  await writeFile(banner, 'linked');
  await writeFile(notes, 'first notes');
  await symlink('../../files/banner.txt', join(app, 'src/sample/banner.txt'));
  await symlink('../files/notes.txt', join(app, 'public/notes.txt'));
  await symlink('someone@host.1:1', join(app, 'public/.#notes.txt'));
  const server = start(['serve', '--port', '0', app]);
  try {
    const base = await until(() => server.text.match(/at (http:\/\/127\.0\.0\.1:\d+\/)/)?.[1], 'the server', 300);
    const events = await listen(new URL('.snail/events', base));
    const built = await nextBuild(events, 0);
    assert.equal(built.kind, 'built', built.message);
    assert.equal(digestOf(built.manifest, 'notes.txt'), sha256('first notes'), 'a public link is digested as the file it names');
    assert.equal(digestOf(built.manifest, '.#notes.txt'), undefined, 'an editor\'s lock is no page file');
    const page = await linkPage(base, built.manifest);
    assert.equal(text(page, 'greeting'), 'linked');

    let from = events.length;
    await writeFile(banner, 'linked again');
    const relinked = await nextBuild(events, from);
    assert.equal(relinked.kind, 'built', relinked.message);
    assert.notDeepEqual(relinked.manifest.modules, built.manifest.modules, 'editing what a linked link names renames the module that links it');
    assert.deepEqual(await relink(page, relinked.manifest), {from: 'sample.banner', passed: 'adopted'});
    assert.equal(text(page, 'greeting'), 'linked again', 'the relinked module reads the new bytes through the link');

    from = events.length;
    await writeFile(notes, 'second notes');
    const edited = await nextBuild(events, from);
    assert.equal(edited.kind, 'built', edited.message);
    assert.equal(digestOf(edited.manifest, 'notes.txt'), sha256('second notes'), 'editing what a public link names changes its digest');
    assert.deepEqual(edited.manifest.modules, relinked.manifest.modules, 'and nothing else');
    assert.equal(await (await fetch(new URL('notes.txt', base))).text(), 'second notes');

    from = events.length;
    await rm(notes);
    const dangling = await nextBuild(events, from);
    assert.equal(dangling.kind, 'failed');
    assert.match(dangling.message, /cannot read \S*\/public\/notes\.txt: no such file or directory/);
    assert.deepEqual(dangling.manifest, edited.manifest, 'a link to nothing keeps the last good manifest');
    from = events.length;
    await writeFile(notes, 'notes again');
    assert.equal((await nextBuild(events, from)).kind, 'built');
    from = events.length;
    await rm(banner);
    const unlinked = await nextBuild(events, from);
    assert.equal(unlinked.kind, 'failed');
    assert.match(unlinked.message, /links banner\.txt, but there is no file at \S*\/src\/sample\/banner\.txt/);
    await page.runtime.stop();
  } finally {
    await stop(server);
  }
}

// ---- Watching ----

async function testWatch(directory) {
  const source = join(directory, 'hello.sld');
  const program = message => `(import (snail core base) (snail core io) (snail shell task))\n(write-string "${message}\\n")\n(dispatch-local (once (lambda () (sleep 60000))))\n`;
  await writeFile(source, program('first run'));
  const watcher = start(['watch', source]);
  let child;
  try {
    await until(() => watcher.text.includes('first run\n'), 'the first run', 300);
    child = applicationChild(watcher.child.pid);
    const first = child;
    await writeFile(source, program('second run'));
    await until(() => watcher.text.includes('second run\n'), 'the second run', 120);
    child = applicationChild(watcher.child.pid);
    assert.notEqual(child, first, 'a live predecessor exits before its replacement starts');
    assert.throws(() => process.kill(first, 0), {code: 'ESRCH'});
    for (const message of ['third run', 'fourth run']) {
      await writeFile(`${source}.next`, program(message));
      await rename(`${source}.next`, source);
      await until(() => watcher.text.includes(`${message}\n`), `the ${message} after a save by rename`, 120);
    }
    child = applicationChild(watcher.child.pid);
    await stop(watcher);
    assert.throws(() => process.kill(child, 0), {code: 'ESRCH'}, 'stopping the host stops its application subprocess');
    child = null;
  } finally {
    try { await stop(watcher); }
    finally { if (child) { try { process.kill(child, 'SIGKILL'); } catch (error) { if (error.code !== 'ESRCH') throw error; } } }
  }
}

function applicationChild(parent) {
  const processes = execFileSync('ps', ['-e', '-o', 'pid=', '-o', 'ppid='], {encoding: 'utf8'});
  const children = processes.trim().split('\n').map(line => line.trim().split(/\s+/).map(Number)).filter(([, pid]) => pid === parent);
  assert.equal(children.length, 1, 'the compiler worker is a thread; the application is the only child process');
  return children[0][0];
}

// ---- Compiler isolation ----

// A source FIFO holds the real compiler inside a synchronous read. Opening
// its write end proves the compiler reached it; no guessed compile duration
// or production test hook is involved. Release the gate before shutdown.
async function testBusyCompiler(directory) {
  const app = join(directory, 'blocked'), source = join(app, 'main.sld');
  await cp(join(root, 'tests/apps/counter'), app, {recursive: true});
  const original = await readFile(source, 'utf8');
  await rm(source);
  execFileSync('mkfifo', [source]);
  const server = start(['serve', '--port', '0', app]);
  let gate;
  try {
    gate = await until(async () => {
      try { return await open(source, constants.O_WRONLY | constants.O_NONBLOCK); }
      catch (error) { if (error.code === 'ENXIO') return false; throw error; }
    }, 'the compiler reading its source', 300);
    const base = await until(() => server.text.match(/at (http:\/\/127\.0\.0\.1:\d+\/)/)?.[1], 'serving while the compiler is busy', 2);
    const response = await fetch(base, {signal: AbortSignal.timeout(2000)});
    assert.equal(response.status, 200);
    assert.match(await response.text(), /Building/);
    const events = await listen(new URL('.snail/events', base));
    await until(() => events.some(event => readEvent(event).kind === 'building'), 'build notification while the compiler is busy', 2);
    await rm(source);
    await writeFile(source, original.replace('"hello"', '"edited while compiling"'));
    await gate.writeFile(original);
    await gate.close();
    gate = null;
    await until(() => events.filter(event => readEvent(event).kind === 'built').length >= 2, 'the follow-up build after an external edit', 120);
    const built = events.map(readEvent).filter(event => event.kind === 'built').at(-1);
    const page = await linkPage(base, built.manifest);
    assert.equal(text(page, 'greeting'), 'edited while compiling');
    await page.runtime.stop();
  } finally {
    await gate?.close();
    await stop(server);
  }
}

const directory = await mkdtemp(join(tmpdir(), 'snail-develop-'));
try {
  await testServe(directory);
  await testGenerated(directory);
  await testLinked(directory);
  await testSymlinked(directory);
  await testWatch(directory);
  await testBusyCompiler(directory);
  console.log('develop: worker, serve, generated libraries, linked files, symbolic links and watch passed');
} finally {
  await rm(directory, {recursive: true, force: true});
}
