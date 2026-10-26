// Real compilation, disk observation and OS children meet at build acceptance.
// A producer FIFO holds the compiler while controls continue in the parent.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {developProject, UnknownRunTarget} from '../scripts/project-develop.mjs';
import {projectTools} from '../scripts/project.mjs';

const root = process.argv[2], directory = fs.mkdtempSync(join(tmpdir(), 'lofi-development-runs-'));
const project = join(directory, 'project'), gate = join(directory, 'gate');
fs.mkdirSync(project);
const write = (name, text) => fs.writeFileSync(join(project, name), text);
const description = (args = 'configured', includeApp = true) => `(
  (build-target main (program (entry "main.sld") (library-roots ("."))))
  (build-target other (program (entry "other.sld")))
  ${includeApp ? `(run-target app (run main (args ("${args}"))))` : ''}
  (run-target side (run other)))`;
const program = message => `(import (lofi base) (lofi io) (lofi task))
  (write-line "${message}") (for-each write-line (command-line)) (sleep 600000)`;
async function until(test) {
  for (let count = 0; count < 1000; count++) { if (test()) return; await delay(20); }
  assert.fail(`timed out waiting for development run: ${JSON.stringify({phase: dev.status.phase, id: dev.status.id, diagnostics: dev.status.diagnostics, runs: dev.status.runs})}`);
}
const dead = pid => assert.throws(() => process.kill(pid, 0), {code: 'ESRCH'});
function pipe() {
  fs.rmSync(gate, {force: true});
  assert.equal(spawnSync('mkfifo', [gate]).status, 0);
}

write('project.datum', description()); write('main.sld', program('first')); write('other.sld', program('side'));
const dev = developProject({root, project, tools: projectTools(root)}), events = [];
dev.subscribe(status => events.push(status));
const run = name => dev.status.runs.find(run => run.target === name);
const app = () => run('app'), side = () => run('side');
const ready = (name, text) => until(() => run(name)?.attempt?.stdout.includes(text));
const stopped = name => until(() => ['exited', 'failed'].includes(run(name)?.attempt?.phase));
async function settled(after, phase = 'succeeded') {
  await until(() => dev.status.id > after && dev.status.phase === phase);
  return dev.status;
}
let writer = null;

try {
  assert.throws(() => dev.startRun('app'), UnknownRunTarget);
  const first = await settled(0);
  assert.ok(first.runs.every(run => !run.wanted && !run.attempt && run.available));
  for (const command of [dev.startRun, dev.stopRun, dev.restartRun]) assert.throws(() => command('missing'), UnknownRunTarget);

  let veto = true;
  const unveto = dev.subscribe(() => { if (veto && app().wanted) { veto = false; dev.stopRun('app'); } });
  dev.startRun('app'); await delay(30);
  assert.equal(app().attempt, null, 'a reentrant Stop overrides Start before spawning'); unveto();
  dev.startRun('app'); dev.startRun('side'); await ready('app', 'configured\n'); await ready('side', 'side\n');
  let firstPid = app().attempt.pid;
  const firstSide = side().attempt.pid;
  assert.match(app().attempt.stdout, new RegExp(first.published.targets.find(t => t.name === 'main').directory + '/modules.json'));
  dev.startRun('app'); dev.requestBuild();
  let accepted = await settled(first.id);
  assert.ok(accepted.published.targets.every(target => target.compiled === 0));
  assert.equal(app().attempt.pid, firstPid); assert.equal(side().attempt.pid, firstSide);
  assert.equal(app().attempt.build, first.id, 'an unchanged child retains its actual accepted build');
  dev.restartRun('app'); await until(() => app().attempt.pid !== firstPid); await ready('app', 'configured\n');
  dead(firstPid); firstPid = app().attempt.pid;
  assert.equal(app().attempt.build, accepted.id, 'Restart uses the newest equivalent generation');

  write('other.sld', program('side changed'));
  accepted = await settled(accepted.id); await ready('side', 'side changed\n');
  assert.notEqual(side().attempt.pid, firstSide); dead(firstSide);
  assert.equal(app().attempt.pid, firstPid, 'an independent target change leaves this child running');
  let stableSide = side().attempt.pid;

  write('project.datum', description('new arguments')); write('main.sld', '(import (lofi base)) (missing)');
  const failed = await settled(accepted.id, 'failed');
  assert.equal(app().attempt.pid, firstPid); assert.equal(side().attempt.pid, stableSide);
  dev.stopRun('app'); await stopped('app'); dead(firstPid);
  dev.startRun('app'); await until(() => app().attempt.pid !== firstPid); await ready('app', 'configured\n');
  assert.equal(app().attempt.build, accepted.published.id, 'failed parsed metadata cannot change a launch');
  write('main.sld', program('repaired'));
  accepted = await settled(failed.id); await ready('app', 'new arguments\n');
  assert.match(app().attempt.stdout, /^repaired\n/); assert.equal(side().attempt.pid, stableSide);

  // Reconciliation of one target can invoke controls for a later target.
  let stoppedSibling = false;
  const beforeSibling = accepted.id;
  const unsibling = dev.subscribe(status => {
    if (!stoppedSibling && status.published?.id > beforeSibling && app().desired?.build === status.published.id) {
      stoppedSibling = true; dev.stopRun('side');
    }
  });
  write('main.sld', program('reentrant')); write('other.sld', program('side latest'));
  accepted = await settled(accepted.id); await ready('app', 'reentrant\n'); await stopped('side'); unsibling();
  assert.equal(side().wanted, false); assert.notEqual(side().attempt.build, accepted.id); dead(stableSide);
  dev.startRun('side'); await ready('side', 'side latest\n'); stableSide = side().attempt.pid;

  // Stop while compilation is blocked. The successful reply must use current
  // intent, not the wanted value when this attempt began.
  pipe();
  write('slow.sld', `(generate-library (slow)
    (import (lofi base) (lofi io) (lofi syntax))
    (library-syntax (list "slow") (list "message") (list (list "lofi" "base"))
      (list (form ":" (list (SymbolSyntax "message") (SymbolSyntax "String")))
        (form "define" (list (SymbolSyntax "message") (StringSyntax (read-file "${gate}")))))))`);
  write('main.sld', '(import (lofi base) (lofi io) (lofi task) (slow)) (write-line message) (sleep 600000)');
  writer = await fsp.open(gate, 'w');
  const stoppedBuild = dev.status.id, beforeStop = app().attempt.pid;
  assert.equal(dev.status.phase, 'building'); dev.stopRun('app'); await stopped('app'); dead(beforeStop);
  fs.renameSync(gate, join(directory, 'stopped-pipe')); fs.writeFileSync(gate, 'stopped build');
  await writer.writeFile('stopped build'); await writer.close(); writer = null;
  await until(() => dev.status.id >= stoppedBuild && dev.status.phase === 'succeeded');
  assert.equal(app().wanted, false); assert.equal(app().desired, null); assert.equal(app().attempt.pid, beforeStop);
  assert.equal(side().attempt.pid, stableSide);
  dev.startRun('app'); await ready('app', 'stopped build\n');
  const beforeSuperseded = app().attempt.pid;

  // A discarded build warms the compiler cache. The following accepted build
  // still replaces the older running output, even with zero compiled modules.
  pipe(); dev.requestBuild(); writer = await fsp.open(gate, 'w');
  const superseded = dev.status.id;
  dev.requestBuild();
  fs.renameSync(gate, join(directory, 'superseded-pipe')); fs.writeFileSync(gate, 'newest');
  await writer.writeFile('newest'); await writer.close(); writer = null;
  accepted = await settled(superseded); await ready('app', 'newest\n');
  assert.equal(accepted.published.targets.find(target => target.name === 'main').compiled, 0);
  assert.notEqual(app().attempt.pid, beforeSuperseded); dead(beforeSuperseded);
  assert.ok(events.some(status => status.id === superseded && status.phase === 'superseded'));
  assert.ok(!events.some(status => status.runs.some(run => run.attempt?.build === superseded)));

  // Removing and reintroducing a name reuses its owner, but not its old intent.
  const removedPid = app().attempt.pid;
  write('project.datum', description('new arguments', false));
  accepted = await settled(accepted.id); await stopped('app'); dead(removedPid);
  assert.equal(app().available, false); assert.equal(app().wanted, false);
  assert.throws(() => dev.startRun('app'), UnknownRunTarget);
  assert.throws(() => dev.restartRun('app'), UnknownRunTarget);
  assert.doesNotThrow(() => dev.stopRun('app'));
  write('project.datum', description('new arguments'));
  accepted = await settled(accepted.id);
  assert.equal(app().available, true); assert.equal(app().wanted, false); assert.equal(app().attempt.pid, removedPid);
  dev.startRun('app'); await until(() => app().attempt.pid !== removedPid); await ready('app', 'newest\n');
  const restartPid = app().attempt.pid;
  dev.restartRun('app'); await until(() => app().attempt.pid !== restartPid); await ready('app', 'newest\n'); dead(restartPid);
  assert.equal(app().attempt.build, accepted.published.id);

  write('main.sld', '(import (lofi base) (lofi io)) (write-line "done")');
  accepted = await settled(accepted.id); await ready('app', 'done\n'); await stopped('app');
  const exitedPid = app().attempt.pid;
  dev.startRun('app'); await delay(50);
  assert.equal(app().attempt.pid, exitedPid, 'Start is idempotent until Stop; Restart explicitly reruns');
  dev.restartRun('app'); await until(() => app().attempt.pid !== exitedPid); await stopped('app');

  // An acceptance observer may close the service before queued launches run.
  let closing = null;
  dev.subscribe(status => { if (status.published?.id > accepted.id && !closing) closing = dev.close(); });
  write('main.sld', program('must not launch'));
  await until(() => closing); await closing;
  assert.equal(dev.close(), closing); dead(stableSide);
  assert.ok(dev.status.runs.every(run => ['exited', 'failed'].includes(run.attempt.phase)));
  assert.ok(!events.some(status => status.runs.some(run => run.attempt?.stdout.includes('must not launch'))));
  assert.throws(() => dev.startRun('app'), /closed/);
} finally {
  if (writer) { await writer.writeFile('cleanup'); await writer.close(); }
  await dev.close();
  fs.rmSync(directory, {recursive: true, force: true});
}
console.log('development runs: accepted content, current intent, independent children, supersession and shutdown');
