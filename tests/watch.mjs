// One real disk observer feeds independent subscribers. Test-only builtin
// interception exercises missing hints and failed reads without a provider API.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {watchProject} from '../scripts/watch.mjs';

const parent = fs.mkdtempSync(join(tmpdir(), 'lofi-watcher-'));
const project = join(parent, 'project'), external = join(parent, 'library');
const write = (path, text = 'source') => { fs.mkdirSync(join(path, '..'), {recursive: true}); fs.writeFileSync(path, text); };
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(test) {
  for (let n = 0; n < 100; n++) { if (test()) return; await delay(50); }
  assert.fail('timed out waiting for filesystem observation');
}

const nativeWatch = fs.watch, nativeRead = fsp.readdir, handles = [];
let silence = false, unreadable = null, paused = null, rootReads = 0;
fs.watch = function(path, options, callback) {
  if (!options?.recursive) return nativeWatch(path, options, callback);
  const handle = nativeWatch(path, options, (event, name) => { if (!silence) callback(event, name); });
  handles.push({path, handle, callback});
  return handle;
};
fsp.readdir = async function(path, ...args) {
  if (path === project) rootReads++;
  if (path === unreadable) throw Object.assign(new Error('injected directory read error'), {code: 'EIO'});
  if (paused && path === paused.path) {
    const gate = paused;
    gate.entered.resolve(); await gate.release.promise;
    if (gate.failure) throw gate.failure;
  }
  return nativeRead(path, ...args);
};
syncBuiltinESMExports();

write(join(project, 'main.sld'), 'one');
write(join(project, 'src/build/library.sld'));
write(join(project, 'build/program.wasm'));
write(join(project, 'data/store.db'));
const files = watchProject({roots: [project, join(project, 'src'), project, external], exclude: [join(project, 'build'), join(project, 'data')]});
const compiler = [], editor = [];
const stopCompiler = files.subscribe(event => compiler.push(event));
const stopEditor = files.subscribe(event => editor.push(event));
const changed = path => compiler.some(event => event.kind === 'changed' && event.paths.includes(path));

try {
  assert.equal(handles.length, 1, 'overlapping roots share one native watch before inventory reads');
  await files.reconcile();
  assert.ok(changed(join(project, 'main.sld')));
  assert.ok(changed(join(project, 'src/build/library.sld')), 'only the explicitly excluded build directory is skipped');
  assert.ok(!changed(join(project, 'build/program.wasm')));
  assert.deepEqual(compiler, editor);

  const source = join(project, 'main.sld');
  compiler.length = 0; editor.length = 0;
  write(source, 'two');
  await files.reconcile();
  assert.ok(changed(source));
  assert.deepEqual(compiler, editor, 'a disk save reaches both subscribers');

  compiler.length = 0;
  const replacement = join(project, 'replacement.sld');
  write(replacement, 'new');
  fs.renameSync(replacement, source);
  await files.reconcile();
  assert.ok(changed(source), 'atomic replacement is observed');
  const created = join(project, 'created/child.sld');
  write(created);
  await files.reconcile();
  assert.ok(changed(created));
  compiler.length = 0;
  fs.renameSync(join(project, 'created'), join(project, 'renamed'));
  await files.reconcile();
  assert.ok(changed(created) && changed(join(project, 'renamed/child.sld')));
  compiler.length = 0;
  fs.rmSync(join(project, 'renamed'), {recursive: true});
  await files.reconcile();
  assert.ok(changed(join(project, 'renamed/child.sld')));

  // Reconciliation works without notifications, including a same-size write
  // whose mtime was restored: ordinary local ctime/identity still changes.
  silence = true; compiler.length = 0;
  const before = fs.statSync(source);
  write(source, 'six');
  fs.utimesSync(source, before.atime, before.mtime);
  await files.reconcile();
  assert.ok(changed(source));
  compiler.length = 0;
  write(join(project, 'build/new.wasm'));
  write(join(project, 'data/new.db'));
  await files.reconcile();
  assert.deepEqual(compiler, [], 'excluded children do not invalidate their parent directory');
  silence = false;

  compiler.length = 0;
  handles[0].callback('rename', null);
  assert.ok(compiler.some(event => event.kind === 'uncertain' && event.path === project));
  await files.reconcile();
  const count = handles.length;
  handles[0].handle.emit('error', new Error('injected native watcher failure'));
  await files.reconcile();
  assert.ok(handles.length > count, 'native errors reattach a watch while polling remains available');

  // No existing handle covers this initially absent root. The timer discovers
  // it, installs a watch, and reports the new source.
  write(join(external, 'base.sld'));
  await until(() => changed(join(external, 'base.sld')));
  assert.ok(handles.some(record => record.path === external));
  fs.renameSync(project, join(parent, 'old-project'));
  write(source, 'recreated');
  await files.reconcile();
  assert.ok(handles.filter(record => record.path === project).length >= 3, 'a replaced root gets a new handle');

  // A failed complete scan does not manufacture deletions or publish a partial
  // inventory. Report uncertainty once, then publish the recovered disk state.
  silence = true; compiler.length = 0;
  unreadable = project;
  write(source, 'after read failure');
  await assert.rejects(files.reconcile(), /cannot reconcile/);
  await assert.rejects(files.reconcile(), /cannot reconcile/);
  write(join(external, 'base.sld'), 'also changed during failure');
  unreadable = external;
  await assert.rejects(files.reconcile(), {message: `cannot reconcile ${external}`});
  assert.equal(compiler.filter(event => event.kind === 'uncertain' && event.error).length, 1);
  assert.ok(!compiler.some(event => event.kind === 'changed'));
  unreadable = null;
  await files.reconcile();
  assert.ok(changed(source) && changed(join(external, 'base.sld')));
  assert.deepEqual(compiler.filter(event => event.kind === 'uncertain' && !event.error), [{kind: 'uncertain'}], 'one complete inventory ends the failure episode');
  assert.deepEqual(compiler.at(-1), {kind: 'uncertain'}, 'recovery follows inventory changes');
  const recovered = compiler.length;
  await files.reconcile();
  assert.equal(compiler.length, recovered, 'success does not repeat the recovery');
  silence = false;

  stopEditor();
  const editorCount = editor.length;
  write(source, 'only compiler subscribed');
  await files.reconcile();
  assert.equal(editor.length, editorCount);

  // A caller arriving during a scan gets a following fresh scan, even while
  // unrelated events continue. It need not wait for global quiet.
  silence = true;
  await files.reconcile();
  compiler.length = 0;
  paused = {path: project, entered: Promise.withResolvers(), release: Promise.withResolvers()};
  const first = files.reconcile();
  await paused.entered.promise;
  const reads = rootReads;
  const following = files.reconcile();
  const gate = paused; paused = null;
  write(source, 'during scan');
  const fresh = join(external, 'fresh.sld');
  write(fresh);
  gate.release.resolve();
  await first;
  assert.ok((await following).includes(fresh), 'the returned names belong to the following complete scan');
  assert.ok(rootReads > reads, 'the waiting caller receives another complete scan');
  assert.ok(changed(source));

  paused = {path: project, entered: Promise.withResolvers(), release: Promise.withResolvers()};
  const pending = files.reconcile().then(() => null, error => error);
  await paused.entered.promise;
  const queued = files.reconcile().then(() => null, error => error);
  const seen = compiler.length, closing = files.close();
  paused.failure = new Error('read failed after shutdown');
  paused.release.resolve();
  assert.match((await pending).message, /watcher is closed/);
  await closing;
  assert.match((await queued).message, /watcher is closed/);
  assert.equal(compiler.length, seen, 'close during a scan prevents later emissions');
  await assert.rejects(files.reconcile(), /watcher is closed/);
  stopCompiler();
} finally {
  if (paused) paused.release.resolve();
  await files.close();
  fs.watch = nativeWatch; fsp.readdir = nativeRead; syncBuiltinESMExports();
  fs.rmSync(parent, {recursive: true, force: true});
}
console.log('shared watcher: subscriptions, reconciliation, exclusions, recovery and close');
