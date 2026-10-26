import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {FileConflict, ProjectFileError, projectFiles} from '../scripts/project-files.mjs';
import {watchProject} from '../scripts/watch.mjs';

const parent = fs.mkdtempSync(join(tmpdir(), 'lofi-project-files-')), project = join(parent, 'project');
const write = (name, text) => { const path = join(project, name); fs.mkdirSync(join(path, '..'), {recursive: true}); fs.writeFileSync(path, text); };
write('project.datum', '()');
write('main.sld', '\ufeff(hello 😀)\r\nno final newline');
write('src/build/real.scm', '(source)');
write('build/hidden.sld', '(output)');
write('.git/hidden.sld', '(git)');
write('src/.git/hidden.sld', '(nested git)');
write('back\\slash/hidden.sld', '(unaddressable directory)');
write('binary.sld', Buffer.from([255]));
write('zero.sld', Buffer.from([65, 0, 66]));
write('ignored.bin', '(not listed)');
write('README', 'extensionless');
fs.writeFileSync(join(parent, 'outside.sld'), '(outside)');
fs.symlinkSync(join(parent, 'outside.sld'), join(project, 'linked.sld'));
fs.symlinkSync(parent, join(project, 'linked-directory'));
fs.mkdirSync(join(parent, 'project-other'));
fs.writeFileSync(join(parent, 'project-other/outside.sld'), '(sibling)');
const files = projectFiles(project), path = join(project, 'main.sld');
const observer = watchProject({roots: [project, join(parent, 'project-other')], exclude: [join(project, 'build'), join(project, '.git')]});
const list = async () => files.list(await observer.reconcile());
const events = []; observer.subscribe(event => events.push(event));

try {
  assert.deepEqual(await list(), ['binary.sld', 'main.sld', 'project.datum', 'src/build/real.scm', 'zero.sld']);
  events.length = 0;
  write('fresh.txt', 'external creation');
  assert.ok((await list()).includes('fresh.txt'), 'listing reconciles a fresh inventory');
  fs.unlinkSync(join(project, 'fresh.txt'));
  assert.ok(!(await list()).includes('fresh.txt'));
  const nativeRead = fsp.readdir;
  fsp.readdir = async target => { if (target === project) throw new Error('injected listing failure'); return nativeRead(target); };
  syncBuiltinESMExports();
  try { await assert.rejects(list(), /cannot reconcile/, 'a failed listing cannot return earlier names'); }
  finally { fsp.readdir = nativeRead; syncBuiltinESMExports(); }
  for (const invalid of ['', '/main.sld', '../outside.sld', 'src/../main.sld', './main.sld', 'src//file.sld', 'src\\file.sld', '\ud800.sld', '.git/hidden.sld', 'build/hidden.sld', 'ignored.bin', 'README']) {
    assert.throws(() => files.read(invalid), ProjectFileError);
  }
  assert.throws(() => files.read('linked.sld'), {code: 'ELOOP'});
  assert.throws(() => files.read('linked-directory/outside.sld'), ProjectFileError);
  assert.throws(() => files.read('binary.sld'), /UTF-8/);
  assert.throws(() => files.read('zero.sld'), /NUL/);
  assert.equal(spawnSync('mkfifo', [join(project, 'pipe.sld')]).status, 0);
  assert.ok(!(await list()).includes('pipe.sld'), 'inventory classification excludes pipes without opening them');
  assert.throws(() => files.read('pipe.sld'), /regular project file/, 'a pipe cannot block the native event loop');
  write('large.txt', Buffer.alloc(8 * 1024 * 1024 + 1, 65));
  assert.throws(() => files.read('large.txt'), /8 MiB/);

  const original = fs.readFileSync(path), before = files.read('main.sld');
  fs.chmodSync(path, 0o751);
  const saved = files.save('main.sld', before.revision, before.text);
  assert.deepEqual(fs.readFileSync(path), original, 'unchanged text preserves BOM, CRLF and missing final newline');
  assert.equal(fs.statSync(path).mode & 0o777, 0o751);
  assert.notEqual(saved.revision, before.revision, 'atomic replacement has a new identity');
  assert.deepEqual(files.read('main.sld'), saved);
  assert.throws(() => files.save('main.sld', before.revision, 'stale second client'), FileConflict);
  assert.throws(() => files.save('main.sld', saved.revision, '\ud800'), /well-formed/);
  assert.throws(() => files.save('main.sld', saved.revision, 'a\0b'), /NUL/);
  await observer.reconcile();
  assert.ok(events.some(event => event.kind === 'changed' && event.paths.includes(path)), 'the existing observer sees the committed save');
  assert.ok(events.every(event => event.kind !== 'changed' || event.paths.every(path => !path.includes('.lofi-edit-'))));
  assert.deepEqual(fs.readdirSync(join(project, 'build')), ['hidden.sld']);

  // Replacing identical bytes still changes the file the buffer was based on.
  const replacement = join(parent, 'replacement');
  fs.writeFileSync(replacement, original); fs.renameSync(replacement, path);
  assert.throws(() => files.save('main.sld', saved.revision, 'stale replacement'), FileConflict);
  const deleted = files.read('main.sld'); fs.unlinkSync(path);
  assert.throws(() => files.save('main.sld', deleted.revision, 'must not recreate'), FileConflict);
  write('main.sld', 'current');

  const textBeforeBinary = files.read('main.sld');
  for (const bytes of [Buffer.from([255]), Buffer.from([0]), Buffer.alloc(8 * 1024 * 1024 + 1, 65)]) {
    write('main.sld', bytes);
    assert.throws(() => files.save('main.sld', textBeforeBinary.revision, 'must not replace binary'), FileConflict);
    assert.deepEqual(fs.readFileSync(path), bytes);
  }
  write('main.sld', 'current');

  const nativeWrite = fs.writeFileSync, nativeRename = fs.renameSync;
  const current = files.read('main.sld');
  fs.writeFileSync = function(target, ...args) {
    nativeWrite(target, ...args);
    if (typeof target === 'number') nativeWrite(path, 'external edit while staging');
  };
  syncBuiltinESMExports();
  try { assert.throws(() => files.save('main.sld', current.revision, 'must not overwrite'), FileConflict); }
  finally { fs.writeFileSync = nativeWrite; syncBuiltinESMExports(); }
  assert.equal(fs.readFileSync(path, 'utf8'), 'external edit while staging');
  assert.deepEqual(fs.readdirSync(join(project, 'build')), ['hidden.sld']);

  const latest = files.read('main.sld');
  fs.writeFileSync = function(target, ...args) {
    if (typeof target === 'number') { nativeWrite(target, 'partial staging'); throw new Error('injected write failure'); }
    return nativeWrite(target, ...args);
  };
  syncBuiltinESMExports();
  try { assert.throws(() => files.save('main.sld', latest.revision, 'failed write'), /injected write failure/); }
  finally { fs.writeFileSync = nativeWrite; syncBuiltinESMExports(); }
  assert.deepEqual(files.read('main.sld'), latest);
  assert.deepEqual(fs.readdirSync(join(project, 'build')), ['hidden.sld']);

  fs.renameSync = () => { throw Object.assign(new Error('injected cross-device rename'), {code: 'EXDEV'}); };
  syncBuiltinESMExports();
  try { assert.throws(() => files.save('main.sld', latest.revision, 'failed rename'), {code: 'EXDEV'}); }
  finally { fs.renameSync = nativeRename; syncBuiltinESMExports(); }
  assert.deepEqual(files.read('main.sld'), latest);
  assert.deepEqual(fs.readdirSync(join(project, 'build')), ['hidden.sld']);

  // Returned evidence belongs to what this save published, even if another
  // writer immediately changes the destination before the caller sees it.
  fs.renameSync = function(from, to) { nativeRename(from, to); nativeWrite(to, 'a later external edit'); };
  syncBuiltinESMExports();
  let raced;
  try { raced = files.save('main.sld', latest.revision, 'submitted'); }
  finally { fs.renameSync = nativeRename; syncBuiltinESMExports(); }
  assert.equal(raced.text, 'submitted');
  assert.notEqual(raced.revision, files.read('main.sld').revision);
  assert.throws(() => files.save('main.sld', raced.revision, 'stale'), FileConflict);

  fs.renameSync(join(project, 'build'), join(parent, 'owned-build'));
  fs.symlinkSync(join(parent, 'owned-build'), join(project, 'build'));
  assert.throws(() => files.save('main.sld', files.read('main.sld').revision, 'unsafe staging'), /directory, not a link/);
  fs.unlinkSync(join(project, 'build'));
  fs.renameSync(join(parent, 'owned-build'), join(project, 'build'));
} finally {
  await observer.close();
  fs.rmSync(parent, {recursive: true, force: true});
}
console.log('project files: bounded UTF-8, path boundaries, conflict evidence and atomic saves');
