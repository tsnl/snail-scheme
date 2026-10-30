// Actual disk writes drive `snail dev`'s resident compiler, observed from
// outside (tests/development-service.mjs). A generated library reads a FIFO
// outside the observed roots so the test can hold compilation while the
// service keeps answering, then introduce only a newly configured public-file
// change.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {basename, join} from 'node:path';
import {delay, startDevelopment} from './development-service.mjs';

const root = process.argv[2], parent = fs.realpathSync(fs.mkdtempSync(join(tmpdir(), 'snail-project-attempts-')));
const project = join(parent, 'project'), gate = join(parent, 'gate');
const write = (name, text) => { const path = join(project, name); fs.mkdirSync(join(path, '..'), {recursive: true}); fs.writeFileSync(path, text); };
const description = path => `((build-target server (program (entry "main.sld") (library-roots ("."))))
  (build-target client (browser (entry "client.sld") (public "${path}"))))`;
const program = message => `(import (snail core base) (snail core io)) (write-line "${message}")`;
function execute(directory) {
  const result = spawnSync(process.execPath, ['--no-warnings', join(root, 'host/native/run-snail.mjs'), join(directory, 'modules.json')], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
  return result.stdout;
}
function pipe() {
  fs.rmSync(gate, {force: true});
  assert.equal(spawnSync('mkfifo', [gate]).status, 0);
}
// Everything in the project's build directory: published links, the
// generations they name, and any attempt's private namespace.
const outputs = () => fs.readdirSync(join(project, 'build')).sort();
const server = status => status.published.targets.find(target => target.name === 'server');

// ---- Through the service ----

async function throughTheService() {
  write('project.datum', description('public'));
  write('main.sld', program('first'));
  write('client.sld', '(import (snail core base)) (unit)');
  write('public/index.html', '<!doctype html><title>first</title>');
  const service = await startDevelopment(root, project), stream = await service.events();
  const phases = id => stream.seen.filter(event => event.kind === 'status' && event.data.id === id).map(event => event.data.phase);
  const invalidations = () => stream.seen.filter(event => event.kind === 'files').length;
  let writer = null;

  try {
    const first = await service.settled(0);
    assert.equal(server(first).directory, fs.realpathSync(join(project, 'build/server')));
    assert.equal(execute(server(first).directory), 'first\n');
    const initial = server(first).directory, observed = invalidations();

    write('main.sld', '(import (snail core base)) (first-missing)');
    const failed = await service.settled(first.id, 'failed');
    assert.match(failed.diagnostics[0].message, /first-missing/);
    assert.deepEqual(failed.diagnostics[0].source, {file: join(project, 'main.sld'), line: 1, column: 29});
    assert.equal(fs.realpathSync(join(project, 'build/server')), initial, 'failure preserves accepted output');
    assert.equal(server(failed).directory, initial);
    // Each failed body is reported, in order, with its own source point.
    write('main.sld', '(import (snail core base)) (second-missing) (third-missing)');
    const failedAgain = await service.settled(failed.id, 'failed');
    assert.deepEqual(failedAgain.diagnostics.map(diagnostic => diagnostic.source.column), [29, 46]);
    assert.match(failedAgain.diagnostics[0].message, /second-missing/);
    assert.match(failedAgain.diagnostics[1].message, /third-missing/);
    assert.doesNotMatch(failedAgain.diagnostics[0].message, /first-missing/);
    // An entry an editor deletes fails the build, naming it, and the
    // resident keeps building once it is back.
    fs.rmSync(join(project, 'main.sld'));
    const deleted = await service.settled(failedAgain.id, 'failed');
    assert.equal(deleted.diagnostics[0].message, `${join(project, 'main.sld')}: no such file or directory`);
    assert.equal(deleted.diagnostics[0].source, null);
    assert.equal(server(deleted).directory, initial);
    write('main.sld', program('repaired'));
    let repaired = await service.settled(deleted.id);
    assert.deepEqual(repaired.diagnostics, []);
    assert.ok(stream.seen.filter(event => event.kind === 'status' && event.data.phase === 'building').every(event => event.data.diagnostics.length === 0));
    assert.ok(invalidations() > observed, 'the observer reports the edits to the editor too');

    // Artifact context must not overwrite a failing dependency's real source.
    write('main.sld', '(import (snail core base) (snail shell artifact)) (artifact-bundle "client")');
    write('client.sld', '(import (snail core base)) (child-missing)');
    const childFailure = await service.settled(repaired.id, 'failed');
    assert.match(childFailure.diagnostics[0].message, /child-missing/);
    assert.deepEqual(childFailure.diagnostics[0].source, {file: join(project, 'client.sld'), line: 1, column: 29});

    // A generated producer is checked in its printed scratch source. Report that
    // origin, never invent a point in the importing application or recipe.
    write('bad.sld', '(generate-library (bad) (import (snail core base) (snail shell syntax)) producer-missing)');
    write('client.sld', '(import (snail core base)) (unit)');
    write('main.sld', '(import (snail core base) (bad)) (unit)');
    const producerFailure = await service.settled(childFailure.id, 'failed');
    assert.match(producerFailure.diagnostics[0].message, /producer-missing/);
    assert.ok(producerFailure.diagnostics[0].source.file.startsWith(join(root, 'build/snail-run/')));
    assert.ok(producerFailure.diagnostics[0].source.file.endsWith('.sld'));
    write('main.sld', program('repaired'));
    repaired = await service.settled(producerFailure.id);

    assert.equal((await service.command('/api/build')).status, 202);
    const reused = await service.settled(repaired.id);
    assert.ok(reused.published.targets.every(target => target.compiled === 0), 'manual builds reuse successful sessions');
    write('data/store.sqlite', 'database data');
    write('store.sqlite-wal', 'journal');
    assert.equal((await service.get('/api/project')).status, 200); // A listing awaits a fresh reconciliation.
    await delay(1200);
    assert.equal((await service.status()).id, reused.id, 'data writes and output publication do not schedule builds');

    // Retain successfully parsed inputs on failure: creating a missing public
    // directory must recover without another config/source write or Save event.
    write('project.datum', description('new-public'));
    const missingPublic = await service.settled(reused.id, 'failed');
    assert.equal(missingPublic.diagnostics[0].source, null, 'packaging failures have no source point');
    write('new-public/index.html', '<!doctype html><title>recovered</title>');
    const recovered = await service.settled(missingPublic.id);
    write('project.datum', '(');
    const malformed = await service.settled(recovered.id, 'failed');
    assert.deepEqual(malformed.diagnostics[0].source, {file: join(project, 'project.datum'), line: 1, column: 1});
    write('project.datum', description('new-public'));
    const restored = await service.settled(malformed.id);

    // Nothing the service has accepted knows next-public yet. Hold the actual
    // producer after its descriptor was read, edit only that public file, then
    // finish this build: it is superseded, and its successor is accepted.
    const beforeBlocked = outputs();
    pipe();
    write('slow.sld', `(generate-library (slow)
      (import (snail core base) (snail core io) (snail shell syntax))
      (library-syntax (list "slow") (list "message") (list (list "snail" "core" "base"))
        (list (form ":" (list (SymbolSyntax "message") (SymbolSyntax "String")))
          (form "define" (list (SymbolSyntax "message") (StringSyntax (read-file "${gate}")))))))`);
    write('next-public/index.html', '<!doctype html><title>before</title>');
    write('main.sld', '(import (snail core base) (snail core io) (slow)) (write-line message)');
    write('project.datum', description('next-public'));
    writer = await fsp.open(gate, 'w'); // The producer has reached its blocking read.
    const blocked = await service.status();
    assert.equal(blocked.phase, 'building');
    assert.equal(server(blocked).directory, server(restored).directory);
    write('next-public/index.html', '<!doctype html><title>after</title>');
    assert.equal((await service.get('/api/project')).status, 200, 'the service answers and reconciles disk while compilation is blocked');
    fs.renameSync(gate, join(parent, 'blocked-pipe'));
    fs.writeFileSync(gate, 'next attempt');
    await writer.writeFile('superseded attempt'); await writer.close(); writer = null;
    const accepted = await service.settled(blocked.id);
    assert.ok(phases(blocked.id).includes('superseded'));
    assert.ok(!phases(blocked.id).includes('succeeded'));
    // A published generation stays until the session ends, so the superseded
    // attempt published nothing exactly when the accepted attempt's generations
    // are the only outputs since, and the targets name them.
    assert.deepEqual(outputs().filter(name => !beforeBlocked.includes(name)), accepted.published.targets.map(target => basename(target.directory)).sort());
    assert.equal(fs.realpathSync(join(project, 'build/server')), server(accepted).directory);
    assert.equal(execute(server(accepted).directory), 'next attempt\n');
    assert.match(fs.readFileSync(join(project, 'build/client/index.html'), 'utf8'), /<title>after<\/title>/);

    // Stop while a producer is in flight. The reply cannot publish, and cleanup
    // removes only this attempt's private namespace after the resident exits.
    // The service ends its event streams as it begins to close.
    const beforeStop = outputs();
    const acceptedPath = fs.realpathSync(join(project, 'build/server'));
    pipe(); assert.equal((await service.command('/api/build')).status, 202);
    writer = await fsp.open(gate, 'w');
    const inFlight = await service.status();
    assert.equal(inFlight.phase, 'building');
    const exited = service.stop();
    await stream.done;
    await writer.writeFile('must not publish'); await writer.close(); writer = null;
    const {code, signal, stderr} = await exited;
    assert.deepEqual({code, signal}, {code: 0, signal: null}, stderr);
    assert.deepEqual(phases(inFlight.id), ['building'], 'closing accepts no reply');
    assert.equal(fs.realpathSync(join(project, 'build/server')), acceptedPath);
    assert.deepEqual(outputs(), beforeStop);
    await assert.rejects(fetch(service.url + '/api/project'));
  } finally {
    if (writer) { await writer.writeFile('cleanup'); await writer.close(); }
    await stream.close();
    await service.stop();
  }
}

try {
  await throughTheService();
} finally {
  fs.rmSync(parent, {recursive: true, force: true});
}
console.log('project attempts: fresh diagnostics, disk inputs, supersession, cache reuse and shutdown');
