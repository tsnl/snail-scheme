// Real OS children cover ownership and signal ordering. The fixture runner
// makes termination controllable; one case also executes the shipping runner.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, readFileSync, realpathSync, rmSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {applicationProcess} from '../host/native/application-process.mjs';

const root = process.argv[2], directory = mkdtempSync(join(tmpdir(), 'snail-application-process-'));
const fixture = join(directory, 'fixture'), cwd = join(directory, 'caller'), owners = [];
mkdirSync(join(fixture, 'host/native'), {recursive: true}); mkdirSync(cwd);
writeFileSync(join(fixture, 'host/native/run-snail.mjs'), `
import {existsSync, readFileSync} from 'node:fs';
import {basename} from 'node:path';
const mode = basename(process.argv[2]);
const args = process.argv.slice(3);
if (mode === 'flood') { process.stdout.write('x'.repeat(100000)); process.stderr.write('y'.repeat(100000)); }
else {
  if (mode !== 'exit') {
    setInterval(() => {}, 1000);
    if (mode === 'gate') process.on('SIGTERM', () => {
      console.log('terminating');
      const timer = setInterval(() => { if (existsSync(args[0])) { clearInterval(timer); process.exit(0); } }, 5);
    });
    if (mode === 'ignore') process.on('SIGTERM', () => console.log('ignored'));
  }
  console.log(JSON.stringify({pid:process.pid, cwd:process.cwd(), entry:process.argv[2], args, input:readFileSync(0, 'utf8')}));
}
`);

function owner(options = {}) {
  const app = applicationProcess({root: fixture, target: 'app', cwd, ...options});
  owners.push(app); return app;
}
const launch = (build, mode = 'hold', args = []) => ({build, entry: join(directory, mode), args});
async function until(test) {
  for (let count = 0; count < 1000; count++) { if (test()) return; await delay(10); }
  assert.fail('timed out waiting for application process');
}
const ready = app => until(() => app.status.attempt?.stdout.includes('"input":""'));
const exited = app => until(() => ['exited', 'failed'].includes(app.status.attempt?.phase));
const dead = pid => assert.throws(() => process.kill(pid, 0), {code: 'ESRCH'});

try {
  const ordinary = owner(), args = ['space value', '', 'λ', '$(not a shell)'];
  ordinary.request(launch(1, 'exit', args)); args[0] = 'changed after request';
  await exited(ordinary);
  const first = ordinary.status.attempt, details = JSON.parse(first.stdout);
  assert.deepEqual(details.args, ['space value', '', 'λ', '$(not a shell)']);
  assert.equal(details.cwd, cwd); assert.equal(details.input, ''); assert.equal(first.code, 0);
  await delay(30); assert.equal(ordinary.status.attempt.pid, first.pid, 'natural exit is not retried');
  ordinary.request(launch(1, 'exit')); await until(() => ordinary.status.attempt.pid !== first.pid); await exited(ordinary);
  await ordinary.close();

  const failed = owner({cwd: join(directory, 'absent')});
  failed.request(launch(1)); await exited(failed);
  assert.equal(failed.status.attempt.phase, 'failed');
  assert.match(failed.status.attempt.error, /ENOENT/);
  assert.equal(failed.status.attempt.pid, null);
  await failed.close();

  const invalid = owner(); invalid.request(launch(1, 'hold', ['\0'])); await exited(invalid);
  assert.equal(invalid.status.attempt.phase, 'failed');
  assert.match(invalid.status.attempt.error, /null bytes/);
  assert.equal(invalid.status.attempt.pid, null);
  await invalid.close();

  const flooded = owner(); flooded.request(launch(1, 'flood')); await exited(flooded);
  assert.equal(flooded.status.attempt.stdout, 'x'.repeat(65536));
  assert.equal(flooded.status.attempt.stderr, 'y'.repeat(65536));
  await flooded.close();

  for (const stopInstead of [false, true]) {
    const app = owner(), gate = join(directory, stopInstead ? 'stop-gate' : 'replace-gate');
    app.request(launch(1, 'gate', [gate])); await ready(app);
    const pid = app.status.attempt.pid;
    app.request(launch(2));
    await until(() => app.status.attempt.stdout.includes('terminating'));
    app.request(stopInstead ? null : launch(3));
    assert.equal(app.status.attempt.pid, pid, 'replacement cannot overlap the old child');
    writeFileSync(gate, 'release');
    if (stopInstead) {
      await exited(app); assert.equal(app.status.desired, null); assert.equal(app.status.attempt.build, 1);
    } else {
      await until(() => app.status.attempt.build === 3); await ready(app);
      assert.equal(app.status.desired.build, 3);
    }
    dead(pid); await app.close();
  }

  const ignored = owner(); ignored.request(launch(1, 'ignore')); await ready(ignored);
  const ignoredPid = ignored.status.attempt.pid;
  const closing = ignored.close();
  assert.equal(ignored.close(), closing, 'close has one cleanup promise');
  assert.throws(() => ignored.request(launch(2)), /closed/);
  await closing; assert.equal(ignored.status.attempt.signal, 'SIGKILL'); dead(ignoredPid);

  // Observers can change intent inside notifications. Later observers must
  // never receive stale intent after a nested notification has replaced it.
  const nested = owner(), seen = []; let redirected = false;
  nested.subscribe(status => {
    if (!redirected && status.desired?.build === 1) { redirected = true; nested.request(launch(2, 'exit')); }
  });
  nested.subscribe(status => seen.push(status.desired?.build ?? null));
  nested.request(launch(1)); await exited(nested);
  assert.equal(nested.status.attempt.build, 2); assert.ok(!seen.includes(1));
  await nested.close();

  const interrupted = owner(); let closingFromReport;
  interrupted.subscribe(status => {
    if (status.attempt?.phase === 'running' && !closingFromReport) closingFromReport = interrupted.close();
  });
  interrupted.request(launch(1)); await until(() => closingFromReport);
  await closingFromReport; dead(interrupted.status.attempt.pid);

  const lastTurn = owner(); let requested = false;
  lastTurn.subscribe(status => {
    if (status.attempt?.build === 1 && status.attempt.phase === 'running' && !requested) {
      requested = true; queueMicrotask(() => lastTurn.request(launch(2, 'exit')));
    }
  });
  lastTurn.request(launch(1)); await until(() => lastTurn.status.attempt?.build === 2); await exited(lastTurn);
  await lastTurn.close();

  const closingTurn = owner(), fullyClosed = Promise.withResolvers(); let closeQueued = false;
  closingTurn.subscribe(status => {
    if (status.attempt?.phase === 'running' && !closeQueued) {
      closeQueued = true;
      queueMicrotask(() => fullyClosed.resolve(closingTurn.close()));
    }
  });
  closingTurn.request(launch(1));
  await fullyClosed.promise; // No polling delay that could hide early completion.
  assert.equal(closingTurn.status.attempt.phase, 'exited');
  dead(closingTurn.status.attempt.pid);

  const project = join(directory, 'project'); mkdirSync(project);
  writeFileSync(join(project, 'project.datum'), '((build-target app (program (entry "main.sld"))))');
  writeFileSync(join(project, 'main.sld'), '(import (snail-core base) (snail-core io)) (for-each write-line (command-line)) (write-file "application-cwd.txt" "saved")');
  execFileSync(join(root, 'snail'), ['build', project, 'app'], {stdio: 'pipe'});
  const native = owner({root}), entry = join(realpathSync(join(project, 'build/app')), 'program.wasm');
  native.request({build: 1, entry, args: ['ordinary argument']}); await exited(native);
  assert.equal(native.status.attempt.code, 0, native.status.attempt.stderr);
  assert.equal(native.status.attempt.stdout, entry + '\nordinary argument\n');
  assert.equal(readFileSync(join(cwd, 'application-cwd.txt'), 'utf8'), 'saved');
  await native.close();
} finally {
  await Promise.all(owners.map(app => app.close()));
  rmSync(directory, {recursive: true, force: true});
}
console.log('application processes: latest intent, bounded output, reentrant observers, signals and shipping runner');
