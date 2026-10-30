// Real compilation, disk observation and OS children meet at build acceptance,
// observed from outside `snail dev` (tests/development-service.mjs). A
// producer FIFO holds the compiler while controls continue over HTTP.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {dead, startDevelopment} from './development-service.mjs';

const root = process.argv[2], directory = fs.realpathSync(fs.mkdtempSync(join(tmpdir(), 'snail-development-runs-')));
const project = join(directory, 'project'), gate = join(directory, 'gate');
fs.mkdirSync(project);
const write = (name, text) => fs.writeFileSync(join(project, name), text);
const description = (args = 'configured', includeApp = true) => `(
  (build-target main (program (entry "main.sld") (library-roots ("."))))
  (build-target other (program (entry "other.sld")))
  ${includeApp ? `(run-target app (run main (args ("${args}"))))` : ''}
  (run-target side (run other)))`;
const program = message => `(import (snail core base) (snail core io) (snail shell task))
  (write-line "${message}") (for-each write-line (command-line)) (dispatch-local (once (lambda () (sleep 600000))))`;
const slow = `(generate-library (slow)
    (import (snail core base) (snail core io) (snail shell syntax))
    (library-syntax (list "slow") (list "message") (list (list "snail" "core" "base"))
      (list (form ":" (list (SymbolSyntax "message") (SymbolSyntax "String")))
        (form "define" (list (SymbolSyntax "message") (StringSyntax (read-file "${gate}")))))))`;
const slowProgram = '(import (snail core base) (snail core io) (snail shell task) (slow)) (write-line message) (for-each write-line (command-line)) (dispatch-local (once (lambda () (sleep 600000))))';
function pipe() {
  fs.rmSync(gate, {force: true});
  assert.equal(spawnSync('mkfifo', [gate]).status, 0);
}
const main = status => status.published.targets.find(target => target.name === 'main');

// ---- Through the service ----

async function throughTheService() {
  // The first attempt waits at the gate, so controls meet a service that has
  // accepted no build yet.
  pipe();
  write('project.datum', description()); write('slow.sld', slow); write('main.sld', slowProgram); write('other.sld', program('side'));
  const service = await startDevelopment(root, project), stream = await service.events();
  const run = async name => (await service.status()).runs.find(run => run.target === name);
  const control = (action, name) => service.command(`/api/run/${action}?target=${name}`);
  const ready = (name, text) => service.until(async () => (await run(name))?.attempt?.stdout.includes(text), `${name} to print ${JSON.stringify(text)}`);
  const stopped = name => service.until(async () => ['exited', 'failed'].includes((await run(name))?.attempt?.phase), `${name} to stop`);
  const pid = async name => (await run(name)).attempt.pid;
  const frames = kind => stream.seen.filter(event => event.kind === kind).map(event => event.data);
  let writer = null;

  try {
    writer = await fsp.open(gate, 'w');
    assert.equal((await service.status()).published, null);
    for (const action of ['start', 'stop', 'restart']) assert.equal((await control(action, 'app')).status, 404, 'no accepted build names app yet');
    fs.renameSync(gate, join(directory, 'first-pipe')); fs.writeFileSync(gate, 'first');
    await writer.writeFile('first'); await writer.close(); writer = null;
    const first = await service.settled(0);
    assert.ok(first.runs.every(run => !run.wanted && !run.attempt && run.available));
    for (const action of ['start', 'stop', 'restart']) assert.equal((await control(action, 'missing')).status, 404);

    assert.equal((await control('start', 'app')).status, 204); assert.equal((await control('start', 'side')).status, 204);
    await ready('app', 'configured\n'); await ready('side', 'side\n');
    let firstPid = await pid('app');
    const firstSide = await pid('side');
    assert.match((await run('app')).attempt.stdout, new RegExp(main(first).directory + '/modules.json'));
    assert.equal((await control('start', 'app')).status, 204); assert.equal((await service.command('/api/build')).status, 202);
    let accepted = await service.settled(first.id);
    assert.ok(accepted.published.targets.every(target => target.compiled === 0));
    assert.equal(await pid('app'), firstPid); assert.equal(await pid('side'), firstSide);
    assert.equal((await run('app')).attempt.build, first.id, 'an unchanged child retains its actual accepted build');
    assert.equal((await control('restart', 'app')).status, 204);
    await service.until(async () => await pid('app') !== firstPid, 'a restarted app'); await ready('app', 'configured\n');
    dead(firstPid); firstPid = await pid('app');
    assert.equal((await run('app')).attempt.build, accepted.id, 'Restart uses the newest equivalent generation');

    write('other.sld', program('side changed'));
    accepted = await service.settled(accepted.id); await ready('side', 'side changed\n');
    assert.notEqual(await pid('side'), firstSide); dead(firstSide);
    assert.equal(await pid('app'), firstPid, 'an independent target change leaves this child running');
    const stableSide = await pid('side');

    write('project.datum', description('new arguments')); write('main.sld', '(import (snail core base)) (missing)');
    const failed = await service.settled(accepted.id, 'failed');
    assert.equal(await pid('app'), firstPid); assert.equal(await pid('side'), stableSide);
    assert.equal((await control('stop', 'app')).status, 204); await stopped('app'); dead(firstPid);
    assert.equal((await control('start', 'app')).status, 204);
    await service.until(async () => await pid('app') !== firstPid, 'a new app'); await ready('app', 'configured\n');
    assert.equal((await run('app')).attempt.build, accepted.published.id, 'failed parsed metadata cannot change a launch');
    write('main.sld', program('repaired'));
    accepted = await service.settled(failed.id); await ready('app', 'new arguments\n');
    assert.match((await run('app')).attempt.stdout, /^repaired\n/); assert.equal(await pid('side'), stableSide);

    // Stop while compilation is blocked. The successful reply must use current
    // intent, not the wanted value when this attempt began.
    pipe();
    write('main.sld', slowProgram);
    writer = await fsp.open(gate, 'w');
    const blocked = await service.status(), beforeStop = await pid('app');
    assert.equal(blocked.phase, 'building');
    assert.equal((await control('stop', 'app')).status, 204); await stopped('app'); dead(beforeStop);
    fs.renameSync(gate, join(directory, 'stopped-pipe')); fs.writeFileSync(gate, 'stopped build');
    await writer.writeFile('stopped build'); await writer.close(); writer = null;
    await service.until(async () => { const current = await service.status(); return current.id >= blocked.id && current.phase === 'succeeded'; }, 'the stopped build');
    const app = await run('app');
    assert.equal(app.wanted, false); assert.equal(app.desired, null); assert.equal(app.attempt.pid, beforeStop);
    assert.equal(await pid('side'), stableSide);
    assert.equal((await control('start', 'app')).status, 204); await ready('app', 'stopped build\n');
    const beforeSuperseded = await pid('app');

    // A discarded build warms the compiler cache. The following accepted build
    // still replaces the older running output, even with zero compiled modules.
    pipe(); assert.equal((await service.command('/api/build')).status, 202); writer = await fsp.open(gate, 'w');
    const superseded = (await service.status()).id;
    assert.equal((await service.command('/api/build')).status, 202);
    fs.renameSync(gate, join(directory, 'superseded-pipe')); fs.writeFileSync(gate, 'newest');
    await writer.writeFile('newest'); await writer.close(); writer = null;
    accepted = await service.settled(superseded); await ready('app', 'newest\n');
    assert.equal(main(accepted).compiled, 0);
    assert.notEqual(await pid('app'), beforeSuperseded); dead(beforeSuperseded);
    assert.ok(frames('status').some(status => status.id === superseded && status.phase === 'superseded'));
    assert.ok(!frames('runs').some(runs => runs.some(run => run.attempt?.build === superseded)));

    // Removing and reintroducing a name reuses its owner, but not its old intent.
    const removedPid = await pid('app');
    write('project.datum', description('new arguments', false));
    accepted = await service.settled(accepted.id); await stopped('app'); dead(removedPid);
    assert.equal((await run('app')).available, false); assert.equal((await run('app')).wanted, false);
    assert.equal((await control('start', 'app')).status, 404);
    assert.equal((await control('restart', 'app')).status, 404);
    assert.equal((await control('stop', 'app')).status, 204);
    write('project.datum', description('new arguments'));
    accepted = await service.settled(accepted.id);
    const reintroduced = await run('app');
    assert.equal(reintroduced.available, true); assert.equal(reintroduced.wanted, false); assert.equal(reintroduced.attempt.pid, removedPid);
    assert.equal((await control('start', 'app')).status, 204);
    await service.until(async () => await pid('app') !== removedPid, 'a reintroduced app'); await ready('app', 'newest\n');
    const restartPid = await pid('app');
    assert.equal((await control('restart', 'app')).status, 204);
    await service.until(async () => await pid('app') !== restartPid, 'a restarted app'); await ready('app', 'newest\n'); dead(restartPid);
    assert.equal((await run('app')).attempt.build, accepted.published.id);

    write('main.sld', '(import (snail core base) (snail core io)) (write-line "done")');
    accepted = await service.settled(accepted.id); await ready('app', 'done\n'); await stopped('app');
    const exitedPid = await pid('app');
    assert.equal((await control('start', 'app')).status, 204); await delay(50);
    assert.equal(await pid('app'), exitedPid, 'Start is idempotent until Stop; Restart explicitly reruns');
    assert.equal((await control('restart', 'app')).status, 204);
    await service.until(async () => await pid('app') !== exitedPid, 'a rerun app'); await stopped('app');

    // The ordinary signal stops every application process with the service.
    assert.equal((await service.command('/api/run/start?target=app')).status, 204);
    write('main.sld', program('running at shutdown'));
    accepted = await service.settled(accepted.id); await ready('app', 'running at shutdown\n');
    const running = [await pid('app'), await pid('side')];
    const {code, signal, stderr} = await service.stop();
    assert.deepEqual({code, signal}, {code: 0, signal: null}, stderr);
    for (const child of running) dead(child);
    await assert.rejects(fetch(service.url + '/api/status'));
  } finally {
    if (writer) { await writer.writeFile('cleanup'); await writer.close(); }
    await stream.close();
    await service.stop();
  }
}

try {
  await throughTheService();
} finally {
  fs.rmSync(directory, {recursive: true, force: true});
}
console.log('development runs: accepted content, current intent, independent children, supersession and shutdown');
