// Actual disk writes drive a resident worker. A generated library reads a FIFO
// outside the observed roots so tests can hold compilation without blocking the
// parent, then introduce only a newly configured public-file change.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import threads from 'node:worker_threads';
import {developProject} from '../host/native/project-develop.mjs';
import {projectTools} from '../host/native/project.mjs';

const root = process.argv[2], parent = fs.mkdtempSync(join(tmpdir(), 'lofi-project-attempts-'));
const project = join(parent, 'project'), gate = join(parent, 'gate');
const tools = projectTools(root), delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const write = (name, text) => { const path = join(project, name); fs.mkdirSync(join(path, '..'), {recursive: true}); fs.writeFileSync(path, text); };
const description = path => `((build-target server (program (entry "main.sld") (library-roots ("."))))
  (build-target client (browser (entry "client.sld") (public "${path}"))))`;
const program = message => `(import (lofi base) (lofi io)) (write-line "${message}")`;
async function until(test) {
  for (let n = 0; n < 600; n++) { if (test()) return; await delay(50); }
  assert.fail('timed out waiting for project attempt');
}
function execute(directory) {
  const result = spawnSync(process.execPath, ['--no-warnings', join(root, 'host/native/run-lofi.mjs'), join(directory, 'modules.json')], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  return result.stdout;
}
function pipe() {
  fs.rmSync(gate, {force: true});
  assert.equal(spawnSync('mkfifo', [gate]).status, 0);
}

write('project.datum', description('public'));
write('main.sld', program('first'));
write('client.sld', '(import (lofi base)) (unit)');
write('public/index.html', '<!doctype html><title>first</title>');
const dev = developProject({root, project, tools}), events = [], observed = [];
const unsubscribe = dev.subscribe(event => events.push(event));
dev.files.subscribe(event => observed.push(event));
const settled = async (after, phase = 'succeeded') => {
  await until(() => dev.status.id > after && dev.status.phase === phase);
  return dev.status;
};
let writer = null;

try {
  const first = await settled(0);
  assert.equal(execute(first.published.targets.find(target => target.name === 'server').directory), 'first\n');
  const initial = fs.realpathSync(join(project, 'build/server'));

  write('main.sld', '(import (lofi base)) (first-missing)');
  const failed = await settled(first.id, 'failed');
  assert.match(failed.diagnostics[0].message, /first-missing/);
  assert.deepEqual(failed.diagnostics[0].source, {file: join(project, 'main.sld'), line: 1, column: 23});
  assert.equal(fs.realpathSync(join(project, 'build/server')), initial, 'failure preserves accepted output');
  write('main.sld', '(import (lofi base)) (second-missing)');
  const failedAgain = await settled(failed.id, 'failed');
  assert.match(failedAgain.diagnostics[0].message, /second-missing/);
  assert.doesNotMatch(failedAgain.diagnostics[0].message, /first-missing/);
  write('main.sld', program('repaired'));
  let repaired = await settled(failedAgain.id);
  assert.deepEqual(repaired.diagnostics, []);
  assert.ok(events.filter(event => event.phase === 'building').every(event => event.diagnostics.length === 0));
  assert.ok(observed.some(event => event.kind === 'changed' && event.paths.includes(join(project, 'main.sld'))));

  // Artifact context must not overwrite a failing dependency's real source.
  write('main.sld', '(import (lofi base) (lofi artifact)) (artifact-bundle "client")');
  write('client.sld', '(import (lofi base)) (child-missing)');
  const childFailure = await settled(repaired.id, 'failed');
  assert.match(childFailure.diagnostics[0].message, /child-missing/);
  assert.deepEqual(childFailure.diagnostics[0].source, {file: join(project, 'client.sld'), line: 1, column: 23});

  // A generated producer is checked in its printed scratch source. Report that
  // origin, never invent a point in the importing application or recipe.
  write('bad.sld', '(generate-library (bad) (import (lofi base) (lofi syntax)) producer-missing)');
  write('client.sld', '(import (lofi base)) (unit)');
  write('main.sld', '(import (lofi base) (bad)) (unit)');
  const producerFailure = await settled(childFailure.id, 'failed');
  assert.match(producerFailure.diagnostics[0].message, /producer-missing/);
  assert.ok(producerFailure.diagnostics[0].source.file.startsWith(join(root, 'build/lofi-run/')));
  assert.ok(producerFailure.diagnostics[0].source.file.endsWith('.sld'));
  write('main.sld', program('repaired'));
  repaired = await settled(producerFailure.id);

  dev.requestBuild();
  const reused = await settled(repaired.id);
  assert.ok(reused.published.targets.every(target => target.compiled === 0), 'manual builds reuse successful sessions');
  write('data/store.sqlite', 'database data');
  write('store.sqlite-wal', 'journal');
  await dev.files.reconcile();
  await delay(1200);
  assert.equal(dev.status.id, reused.id, 'data writes and output publication do not schedule builds');

  // Retain successfully parsed inputs on failure: creating a missing public
  // directory must recover without another config/source write or Save event.
  write('project.datum', description('new-public'));
  const missingPublic = await settled(reused.id, 'failed');
  assert.equal(missingPublic.diagnostics[0].source, null, 'packaging failures have no source point');
  write('new-public/index.html', '<!doctype html><title>recovered</title>');
  const recovered = await settled(missingPublic.id);
  write('project.datum', '(');
  const malformed = await settled(recovered.id, 'failed');
  assert.deepEqual(malformed.diagnostics[0].source, {file: join(project, 'project.datum'), line: 1, column: 1});
  write('project.datum', description('new-public'));
  const restored = await settled(malformed.id);

  // No parent subscriber knows next-public yet. Hold the actual producer after
  // its descriptor was read, edit only that public file, then finish this build.
  pipe();
  write('slow.sld', `(generate-library (slow)
    (import (lofi base) (lofi io) (lofi syntax))
    (library-syntax (list "slow") (list "message") (list (list "lofi" "base"))
      (list (form ":" (list (SymbolSyntax "message") (SymbolSyntax "String")))
        (form "define" (list (SymbolSyntax "message") (StringSyntax (read-file "${gate}")))))))`);
  write('next-public/index.html', '<!doctype html><title>before</title>');
  write('main.sld', '(import (lofi base) (lofi io) (slow)) (write-line message)');
  write('project.datum', description('next-public'));
  writer = await fsp.open(gate, 'w'); // The producer has reached its blocking read.
  assert.equal(dev.status.phase, 'building');
  const blocked = dev.status.id, beforeBlocked = fs.realpathSync(join(project, 'build/server'));
  let ticked = false;
  setTimeout(() => { ticked = true; }, 0);
  write('next-public/index.html', '<!doctype html><title>after</title>');
  await dev.files.reconcile();
  assert.ok(ticked, 'the parent runs timers and disk reconciliation while compilation is blocked');
  fs.renameSync(gate, join(parent, 'blocked-pipe'));
  fs.writeFileSync(gate, 'next attempt');
  await writer.writeFile('superseded attempt'); await writer.close(); writer = null;
  const accepted = await settled(blocked);
  assert.ok(events.some(event => event.id === blocked && event.phase === 'superseded'));
  assert.ok(!events.some(event => event.id === blocked && event.phase === 'succeeded'));
  assert.ok(events.filter(event => event.id === blocked).every(event => event.published.targets.find(target => target.name === 'server').directory === beforeBlocked));
  assert.equal(execute(accepted.published.targets.find(target => target.name === 'server').directory), 'next attempt\n');
  assert.match(fs.readFileSync(join(project, 'build/client/index.html'), 'utf8'), /<title>after<\/title>/);

  // Stop while a producer is in flight. The reply cannot publish, and cleanup
  // removes only this attempt's private namespace after worker ownership ends.
  const beforeStop = fs.readdirSync(join(project, 'build')).sort();
  const acceptedPath = fs.realpathSync(join(project, 'build/server'));
  pipe(); dev.requestBuild();
  writer = await fsp.open(gate, 'w');
  const count = events.length, closing = dev.close();
  await writer.writeFile('must not publish'); await writer.close(); writer = null;
  await closing;
  assert.equal(events.length, count);
  assert.equal(fs.realpathSync(join(project, 'build/server')), acceptedPath);
  assert.deepEqual(fs.readdirSync(join(project, 'build')).sort(), beforeStop);
  await assert.rejects(dev.files.reconcile(), /closed/);
  assert.throws(() => dev.subscribe(() => {}), /closed/);
  unsubscribe();

  // Status observers can stop synchronously. No build may be queued after the
  // worker's close command, even though both would fit in one parent turn.
  let stoppedOnStart = null;
  const early = developProject({root, project, tools});
  early.subscribe(event => { if (event.phase === 'building') stoppedOnStart = early.close(); });
  await until(() => stoppedOnStart !== null);
  await stoppedOnStart;
  assert.deepEqual(fs.readdirSync(join(project, 'build')).sort(), beforeStop);

  // An initial reconciliation can still be pending when a worker dies. Its
  // cancellation must not replace the terminal worker diagnostic.
  const read = fsp.readdir, NativeWorker = threads.Worker, entered = Promise.withResolvers(), release = Promise.withResolvers();
  let captured = null, dying = null;
  threads.Worker = class extends NativeWorker { constructor(...args) { super(...args); captured = this; } };
  fsp.readdir = async function(path, ...args) {
    if (path === project) { entered.resolve(); await release.promise; }
    return read(path, ...args);
  };
  syncBuiltinESMExports();
  try {
    dying = developProject({root, project, tools});
    await entered.promise;
    await captured.terminate();
    assert.equal(dying.status.phase, 'fatal');
    const diagnostic = dying.status.diagnostics[0].message;
    release.resolve();
    await dying.close();
    assert.equal(dying.status.phase, 'fatal');
    assert.equal(dying.status.diagnostics[0].message, diagnostic);
  } finally {
    release.resolve();
    await dying?.close();
    fsp.readdir = read; threads.Worker = NativeWorker; syncBuiltinESMExports();
  }

  const broken = developProject({root, project, tools: {...tools, compiler: join(parent, 'missing.wasm')}});
  await until(() => broken.status.phase === 'fatal');
  await broken.close();
  assert.match(broken.status.diagnostics[0].message, /missing.wasm/);
} finally {
  if (writer) { await writer.writeFile('cleanup'); await writer.close(); }
  await dev.close();
  fs.rmSync(parent, {recursive: true, force: true});
}
console.log('project attempts: fresh diagnostics, disk inputs, supersession, cache reuse and shutdown');
