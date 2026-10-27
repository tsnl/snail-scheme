// The same project builder keeps successful compiler sessions while candidates
// are accepted, discarded or fail. Only generated directories cross to callers.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createProjectBuilder, discardProject, projectTools, publishProject} from '../host/native/project.mjs';

const root = process.argv[2], project = fs.mkdtempSync(join(tmpdir(), 'snail-project-development-'));
const working = fs.mkdtempSync(join(tmpdir(), 'snail-project-worker-'));
const tools = projectTools(root);
const write = (name, text) => { const path = join(project, name); fs.mkdirSync(join(path, '..'), {recursive: true}); fs.writeFileSync(path, text); };
const output = name => fs.realpathSync(join(project, 'build', name));
const target = (candidate, name) => candidate.targets.find(target => target.name === name);

function execute(directory) {
  const result = spawnSync(process.execPath, ['--no-warnings', join(root, 'host/native/run-snail.mjs'), join(directory, 'modules.json')], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  return result.stdout;
}

fs.cpSync(join(root, 'tests/artifacts/project'), project, {recursive: true});
write('client-public/nested/data.bin', Buffer.from([65, 0, 255]));
write('client-public/index.html', '<!doctype html><title>client</title>');
write('admin-public/admin.bin', Buffer.from([99]));
const source = fs.readFileSync(join(project, 'server.sld'), 'utf8');
const builder = await createProjectBuilder({root, project, tools, directory: working});

try {
  const first = builder.build(builder.describe(), ['server']);
  assert.equal(first.targets.length, 3, 'nested/repeated artifact requests build each target once');
  assert.throws(() => output('server'), {code: 'ENOENT'}, 'a candidate has no public output');
  assert.match(execute(target(first, 'server').directory), /65,0,255,/);
  assert.match(fs.readFileSync(join(target(first, 'client').directory, 'index.html'), 'utf8'), /content="\.\/modules.json"/);
  publishProject(first);
  const initialServer = output('server'), initialClient = output('client');

  const discarded = builder.build(builder.describe(), ['server']);
  assert.ok(discarded.targets.every(target => target.compiled === 0), 'unchanged compilation evidence is reused');
  for (const output of discarded.targets) {
    assert.match(output.digest, /^[0-9a-f]{64}$/);
    assert.equal(output.digest, target(first, output.name).digest, 'identity excludes generation paths');
  }
  discardProject(discarded);
  assert.ok(discarded.targets.every(target => !fs.existsSync(target.directory)));
  assert.equal(output('server'), initialServer);
  const afterDiscard = builder.build(builder.describe(), ['server']);
  assert.ok(afterDiscard.targets.every(target => target.compiled === 0), 'sessions retain no paths into discarded candidates');
  publishProject(afterDiscard);

  fs.renameSync(join(project, 'client-public/nested/data.bin'), join(project, 'client-public/nested/renamed.bin'));
  const renamed = builder.build(builder.describe(), ['client']);
  assert.equal(target(renamed, 'client').compiled, 0, 'public paths do not affect compilation');
  assert.notEqual(target(renamed, 'client').digest, target(first, 'client').digest, 'public paths affect output identity');
  discardProject(renamed);
  fs.renameSync(join(project, 'client-public/nested/renamed.bin'), join(project, 'client-public/nested/data.bin'));

  const beforeFailure = output('server'), beforeDirectories = fs.readdirSync(join(project, 'build')).sort();
  write('client.sld', '(import (snail-core base)) (ann 42 I64)');
  write('client-public/nested/data.bin', Buffer.from([90, 0, 255]));
  write('server.sld', `${source}\n(missing-function)\n`);
  assert.throws(() => builder.build(builder.describe(), ['server']), /missing-function/);
  assert.equal(output('server'), beforeFailure);
  assert.deepEqual(fs.readdirSync(join(project, 'build')).sort(), beforeDirectories, 'failed traversal removes every private generation');

  const remove = fs.rmSync;
  write('server.sld', '(import (snail-core base)) (missing-function)');
  fs.rmSync = function(path, options) {
    if (options?.recursive && String(path).startsWith(join(working, 'compile-'))) throw new Error('injected cleanup failure');
    return remove(path, options);
  };
  syncBuiltinESMExports();
  try { assert.throws(() => builder.build(builder.describe(), ['server']), /missing-function/, 'cleanup preserves the compiler diagnostic'); }
  finally {
    fs.rmSync = remove; syncBuiltinESMExports();
    for (const name of fs.readdirSync(working)) if (name.startsWith('compile-')) fs.rmSync(join(working, name), {recursive: true});
  }
  write('server.sld', source);
  const repaired = builder.build(builder.describe(), ['server']);
  assert.equal(target(repaired, 'client').compiled, 0, 'a successful dependency session survives consumer failure');
  assert.notEqual(target(repaired, 'client').digest, target(first, 'client').digest, 'cached work can differ from accepted output');
  assert.match(execute(target(repaired, 'server').directory), /90,0,255,/);

  // A later rename failure keeps its published prefix and removes only the
  // unpublished suffix. Embedded bundles make the retained program complete.
  const rename = fs.renameSync, failedTarget = repaired.targets[1];
  fs.renameSync = function(from, to) {
    if (to === join(project, 'build', failedTarget.name)) throw new Error('injected publication failure');
    return rename(from, to);
  };
  syncBuiltinESMExports();
  try { assert.throws(() => publishProject(repaired), /injected publication failure/); }
  finally { fs.renameSync = rename; syncBuiltinESMExports(); }
  assert.equal(output(repaired.targets[0].name), repaired.targets[0].directory);
  assert.ok(repaired.targets.slice(1).every(target => !fs.existsSync(target.directory)));
  assert.match(execute(repaired.targets[0].directory), /90,0,255,/);
  assert.match(execute(initialServer), /65,0,255,/, 'old generations remain readable');
  assert.ok(fs.existsSync(initialClient));

  // Library-root changes recreate a target's Session. Public settings do not
  // participate in that decision; the compiler checks artifact bytes itself.
  const description = libraries => `((build-target server (program (entry "main.sld") (library-roots ("${libraries}")))))`;
  write('main.sld', '(import (snail-core base) (snail-core io) (sample message)) (write-line message)');
  const library = value => `(define-library (sample message) (export message) (import (snail-core base)) (begin (: message String) (define message "${value}")))`;
  write('one/sample/message.sld', library('one'));
  write('two/sample/message.sld', library('two'));
  for (const name of ['one', 'two']) {
    write('project.datum', description(name));
    const changed = builder.build(builder.describe());
    assert.equal(execute(changed.targets[0].directory), `${name}\n`);
    discardProject(changed);
  }

  // The recipe is unchanged while a file it reads changes. Conservative
  // producer execution must happen in every logical compilation.
  write('message.txt', 'generated first');
  write('two/sample/message.sld', `(generate-library (sample message)
    (import (snail-core base) (snail-core io) (snail-core syntax))
    (library-syntax (list "sample" "message") (list "message") (list (list "snail-core" "base"))
      (list (form ":" (list (SymbolSyntax "message") (SymbolSyntax "String")))
        (form "define" (list (SymbolSyntax "message") (StringSyntax (read-file "${project}/message.txt")))))))`);
  const generated = builder.build(builder.describe());
  assert.equal(execute(generated.targets[0].directory), 'generated first\n');
  discardProject(generated);
  write('message.txt', 'generated second');
  const regenerated = builder.build(builder.describe());
  assert.equal(execute(regenerated.targets[0].directory), 'generated second\n');
  discardProject(regenerated);

  // The manifest owns library names; content filenames need not repeat them
  // and exceed the filesystem limit for an otherwise valid source filename.
  const longName = 'x'.repeat(200);
  write(`two/${longName}.sld`, `(define-library (${longName}) (export message) (import (snail-core base)) (begin (: message String) (define message "long name")))`);
  write('main.sld', `(import (snail-core base) (snail-core io) (${longName})) (write-line message)`);
  const longLibrary = builder.build(builder.describe());
  assert.equal(execute(longLibrary.targets[0].directory), 'long name\n');
  discardProject(longLibrary);
  assert.deepEqual(fs.readdirSync(working), ['errors'], 'logical compile scratch is removed');
} finally {
  builder.close();
  fs.rmSync(project, {recursive: true, force: true});
  fs.rmSync(working, {recursive: true, force: true});
}
console.log('project development: sessions, discard, failure, partial publication and fresh producers');
