// `snail dev` keeps successful compiler sessions while its attempts are
// accepted, superseded or fail, observed from outside
// (tests/development-service.mjs): /api/status names each published target's
// generation, its digest and how many libraries it compiled, and the
// generations run from disk. The test asks for each attempt with Build, so
// each reads the disk as the test left it, but for the saves at the end,
// which the watcher alone must notice.
//   node tests/project-development.mjs ROOT
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, join} from 'node:path';
import {startDevelopment} from './development-service.mjs';

const root = process.argv[2], parent = fs.realpathSync(fs.mkdtempSync(join(tmpdir(), 'snail-project-development-')));
const project = join(parent, 'project'), gate = join(parent, 'gate');
const write = (name, text, directory = project) => {
  const path = join(directory, name);
  fs.mkdirSync(join(path, '..'), {recursive: true});
  fs.writeFileSync(path, text);
};
const target = (status, name) => status.published.targets.find(target => target.name === name);
// Everything in the project's build directory: published links, the
// generations they name, and any attempt's private namespace.
const outputs = () => fs.readdirSync(join(project, 'build')).sort();
const since = before => outputs().filter(name => !before.includes(name));
const builtFor = name => {
  const marker = join(project, 'build', name, '.snail-target');
  return fs.existsSync(marker) ? fs.readFileSync(marker, 'utf8') : null;
};

function execute(directory) {
  const result = spawnSync(process.execPath, ['--no-warnings', join(root, 'host/native/run-snail.mjs'), join(directory, 'modules.json')], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
  return result.stdout;
}

// The artifact fixture: server embeds client and admin, through macros, a
// producer and the producer's output.
function artifactProject(directory) {
  fs.cpSync(join(root, 'tests/artifacts/project'), directory, {recursive: true});
  write('client-public/nested/data.bin', Buffer.from([65, 0, 255]), directory);
  write('client-public/index.html', '<!doctype html><title>client</title>', directory);
  write('admin-public/admin.bin', Buffer.from([99]), directory);
}

// The fixture's producer runs once client is built. Here it also reads a gate
// outside the observed roots, so a FIFO there holds an attempt that has made
// a generation and published nothing; a regular file lets attempts through.
function gateProducer() {
  const path = join(project, 'src/generated/assets.sld');
  let text = fs.readFileSync(path, 'utf8');
  for (const [from, to] of [['(snail shell syntax))', '(snail shell syntax)\n (snail core io))'],
    ['(let ((client (artifact-bundle "client")))', `(let ((client (artifact-bundle "client"))\n (held (read-file "${gate}")))`]]) {
    assert.ok(text.includes(from), `the fixture's producer has ${from}`);
    text = text.replace(from, to);
  }
  fs.writeFileSync(path, text);
  fs.writeFileSync(gate, 'open');
}

async function throughTheService() {
  artifactProject(project);
  write('client-public/nested/notes.txt', 'notes');
  gateProducer();
  const source = fs.readFileSync(join(project, 'server.sld'), 'utf8');
  const service = await startDevelopment(root, project), stream = await service.events();
  const phases = id => stream.seen.filter(event => event.kind === 'status' && event.data.id === id).map(event => event.data.phase);
  let held = null;

  try {
    // One attempt builds every target once, however often the program, its
    // producer and that producer's output request them, and publishes each.
    const first = await service.settled(0);
    assert.deepEqual(first.published.targets.map(output => output.name).sort(), ['admin', 'client', 'server']);
    assert.deepEqual(outputs(), [...first.published.targets.map(output => basename(output.directory)), 'admin', 'client', 'server'].sort(),
      'nested/repeated artifact requests build each target once');
    for (const output of first.published.targets) assert.equal(fs.realpathSync(join(project, 'build', output.name)), output.directory);
    assert.match(execute(target(first, 'server').directory), /65,0,255,/);
    assert.match(fs.readFileSync(join(target(first, 'client').directory, 'index.html'), 'utf8'), /content="\.\/modules.json"/);

    // Build again and hold the attempt in its producer: client's generation
    // exists, but build/client still names the first. Rewriting a source
    // unchanged supersedes the attempt, which removes what it made; the
    // attempt after it reuses every session, with no path into those
    // generations, and only its generation paths differ from the first's.
    const beforeHold = outputs();
    fs.rmSync(gate);
    assert.equal(spawnSync('mkfifo', [gate]).status, 0);
    const requested = await service.command('/api/build');
    assert.equal(requested.status, 202);
    held = await service.until(() => {
      try { return fs.openSync(gate, fs.constants.O_WRONLY | fs.constants.O_NONBLOCK); }
      catch (error) { if (error.code === 'ENXIO') return null; throw error; }
    }, 'the producer to read the gate'); // A missing reader fails on the deadline rather than hanging.
    const blocked = await service.status();
    assert.equal(blocked.phase, 'building');
    assert.ok(since(beforeHold).some(name => builtFor(name) === 'client'), 'the attempt built client before its producer ran');
    assert.equal(fs.realpathSync(join(project, 'build/client')), target(first, 'client').directory, 'a candidate has no public output');
    assert.equal(blocked.published.id, first.id);
    write('server.sld', source);
    fs.renameSync(gate, join(parent, 'held'));
    fs.writeFileSync(gate, 'open');
    fs.writeFileSync(held, 'held'); fs.closeSync(held); held = null;
    const reused = await service.settled(blocked.id);
    assert.ok(phases(blocked.id).includes('superseded'));
    assert.deepEqual(since(beforeHold), reused.published.targets.map(output => basename(output.directory)).sort(),
      'the superseded attempt published nothing and kept nothing');
    assert.equal(fs.realpathSync(join(project, 'build/server')), target(reused, 'server').directory);
    for (const output of reused.published.targets) {
      const earlier = target(first, output.name);
      assert.equal(output.compiled, 0, 'unchanged compilation evidence is reused');
      assert.match(output.digest, /^[0-9a-f]{64}$/);
      assert.equal(output.digest, earlier.digest, 'identity excludes generation paths');
      assert.notEqual(output.directory, earlier.directory);
    }

    // A public file's path is packaged, not compiled.
    fs.renameSync(join(project, 'client-public/nested/notes.txt'), join(project, 'client-public/nested/renamed.txt'));
    const renamed = await service.rebuilt();
    assert.equal(target(renamed, 'client').compiled, 0, 'public paths do not affect compilation');
    assert.notEqual(target(renamed, 'client').digest, target(first, 'client').digest, 'public paths affect output identity');

    // The consumer fails after client compiled. Nothing is published, and the
    // attempt removes every generation it created.
    const beforeFailure = outputs(), accepted = fs.realpathSync(join(project, 'build/server'));
    write('server.sld', `${source}\n(missing-function)\n`);
    write('client.sld', '(import (snail core base)) (ann 42 I64)');
    write('client-public/nested/data.bin', Buffer.from([90, 0, 255]));
    const failed = await service.rebuilt('failed');
    assert.match(failed.diagnostics[0].message, /missing-function/);
    assert.equal(fs.realpathSync(join(project, 'build/server')), accepted);
    assert.deepEqual(outputs(), beforeFailure, 'failed traversal removes every private generation');
    write('server.sld', source);
    const repaired = await service.rebuilt();
    assert.equal(target(repaired, 'client').compiled, 0, 'a successful dependency session survives consumer failure');
    assert.notEqual(target(repaired, 'client').digest, target(first, 'client').digest, 'cached work can differ from accepted output');
    assert.match(execute(target(repaired, 'server').directory), /90,0,255,/);
    // The publication before the latest stays readable; older ones no run
    // runs from are reclaimed.
    assert.match(execute(target(renamed, 'server').directory), /65,0,255,/, 'the publication before stays readable');
    for (const output of [...first.published.targets, ...reused.published.targets]) {
      assert.equal(fs.existsSync(output.directory), false, `${basename(output.directory)} is reclaimed`);
    }

    // Library-root changes recreate a target's Session. Public settings do not
    // participate in that decision; the compiler checks artifact bytes itself.
    const description = libraries => `((build-target server (program (entry "main.sld") (library-roots ("${libraries}")))))`;
    const library = value => `(define-library (sample message) (export message) (import (snail core base)) (begin (: message String) (define message "${value}")))`;
    write('main.sld', '(import (snail core base) (snail core io) (sample message)) (write-line message)');
    write('one/sample/message.sld', library('one'));
    write('two/sample/message.sld', library('two'));
    for (const name of ['one', 'two']) {
      write('project.datum', description(name));
      assert.equal(execute(target(await service.rebuilt(), 'server').directory), `${name}\n`);
    }

    // The recipe is unchanged while a file it reads changes, a file no build
    // watches. Build must run the producer again in every logical compilation.
    write('message.txt', 'generated first');
    write('two/sample/message.sld', `(generate-library (sample message)
      (import (snail core base) (snail core io) (snail shell syntax))
      (library-syntax (list "sample" "message") (list "message") (list (list "snail" "core" "base"))
        (list (form ":" (list (SymbolSyntax "message") (SymbolSyntax "String")))
          (form "define" (list (SymbolSyntax "message") (StringSyntax (read-file "${project}/message.txt")))))))`);
    assert.equal(execute(target(await service.rebuilt(), 'server').directory), 'generated first\n');
    write('message.txt', 'generated second');
    assert.equal(execute(target(await service.rebuilt(), 'server').directory), 'generated second\n');

    // The manifest owns library names; content filenames need not repeat them
    // and exceed the filesystem limit for an otherwise valid source filename.
    const longName = 'x'.repeat(200);
    write(`two/${longName}.sld`, `(define-library (${longName}) (export message) (import (snail core base)) (begin (: message String) (define message "long name")))`);
    write('main.sld', `(import (snail core base) (snail core io) (${longName})) (write-line message)`);
    assert.equal(execute(target(await service.rebuilt(), 'server').directory), 'long name\n');

    // A save that renames a new file over the source, as `sed -i` and many
    // editors make, is an edit, and so is the next: the file the first
    // replaced is gone, so a watch of the file alone would miss it (#547).
    // The new file is written outside the project, so only the rename
    // touches it.
    for (const name of ['renamed once', 'renamed twice']) {
      const before = (await service.status()).id;
      write('next.sld', `(import (snail core base) (snail core io)) (write-line "${name}")`, parent);
      fs.renameSync(join(parent, 'next.sld'), join(project, 'main.sld'));
      assert.equal(execute(target(await service.settled(before), 'server').directory), `${name}\n`);
    }

    const {code, signal, stderr} = await service.stop();
    assert.deepEqual({code, signal}, {code: 0, signal: null}, stderr);
  } finally {
    if (held !== null) { fs.writeFileSync(held, 'cleanup'); fs.closeSync(held); }
    await stream.close();
    await service.stop();
  }
}

try {
  await throughTheService();
} finally {
  fs.rmSync(parent, {recursive: true, force: true});
}
console.log('project development: sessions, supersession, failure, fresh producers and saves by rename');
