// `snail dev` over HTTP, from outside (tests/development-service.mjs): the
// origin boundary, conditional saves, the status snapshot and event stream,
// HTTP answering while the compiler blocks on a FIFO, run controls and
// shutdown on the ordinary signal.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {dead, delay, spawnDevelopment, startDevelopment} from './development-service.mjs';

const root = process.argv[2], project = fs.realpathSync(fs.mkdtempSync(join(tmpdir(), 'snail-project-http-')));
const source = join(project, 'main.sld'), pipe = join(project, 'slow.sld'), notes = join(project, 'notes.txt');
const program = text => `(import (snail core base) (snail core io)) (write-line "${text}")`;
const config = '((build-target main (program (entry "main.sld") (library-roots (".")))) (run-target dev (run main)))';
fs.writeFileSync(join(project, 'project.datum'), config);
fs.writeFileSync(source, program('initial'));
fs.writeFileSync(notes, 'notes\n');
const service = await startDevelopment(root, project), {url} = service;
const read = async (path = 'main.sld') => (await service.get('/api/file?path=' + path)).json();
const save = (revision, text, headers = {}, path = 'main.sld') => fetch(`${url}/api/file?path=${path}`, {
  method: 'PUT', headers: {Origin: url, 'Content-Type': 'text/plain; charset=utf-8', 'If-Match': `"${revision}"`, ...headers}, body: text,
});
const control = (action, target = 'dev') => service.command(`/api/run/${action}?target=${encodeURIComponent(target)}`);
const run = async () => (await service.status()).runs.find(run => run.target === 'dev');
const statuses = stream => stream.seen.filter(event => event.kind === 'status');
const opened = stream => () => stream.seen.some(event => event.kind === 'files');

// A disk change becomes a build request when the observer reconciles: GET
// /api/project awaits a fresh reconciliation, and the debounce then has room.
async function quiet() {
  assert.equal((await service.get('/api/project')).status, 200);
  await delay(500);
}

const stream = await service.events();
let writer = null;
try {
  await service.until(opened(stream), 'the first event frames');
  assert.equal(stream.seen[0].kind, 'status');
  assert.equal(stream.seen[1].kind, 'runs');
  const first = await service.settled(0);

  // One snapshot of the session: the attempt, the generation each published
  // target names on disk, the compiler's identity and the runs the stream sends.
  assert.deepEqual(Object.keys(first).sort(), ['compiler', 'diagnostics', 'id', 'phase', 'published', 'runs']);
  assert.equal(first.published.id, first.id);
  const [main] = first.published.targets;
  assert.deepEqual(Object.keys(main).sort(), ['compiled', 'digest', 'directory', 'name']);
  assert.equal(main.name, 'main');
  assert.equal(main.directory, fs.realpathSync(join(project, 'build/main')));
  assert.match(main.digest, /^[0-9a-f]{64}$/);
  assert.ok(main.compiled > 0);
  assert.ok(Number.isInteger(first.compiler.worker));
  assert.deepEqual(first.runs.map(run => [run.target, run.available, run.wanted, run.attempt]), [['dev', true, false, null]]);

  const projectReply = await (await service.get('/api/project')).json();
  assert.deepEqual(projectReply.files, ['main.sld', 'notes.txt', 'project.datum']);
  assert.equal(projectReply.name, project.split('/').at(-1));
  const page = await service.request('/', 'GET', {'Sec-Fetch-Site': 'cross-site', 'Sec-Fetch-Mode': 'navigate', 'Sec-Fetch-Dest': 'document'});
  assert.equal(page.status, 200);
  assert.equal(page.headers['x-frame-options'], 'DENY');
  assert.match(page.headers['content-security-policy'], /frame-ancestors 'none'/);
  assert.match(page.text, /src="\.\/ide\.mjs"/, 'the page starts the editor');
  const editor = await service.get('/ide.wasm');
  assert.equal(editor.status, 200, "the editor's program is an asset");
  assert.equal(editor.headers.get('content-type'), 'application/wasm');
  assert.equal((await service.request('/', 'GET', {'Sec-Fetch-Site': 'cross-site', 'Sec-Fetch-Mode': 'navigate', 'Sec-Fetch-Dest': 'iframe'})).status, 403);
  assert.equal((await service.get('/main.sld')).status, 404, 'no arbitrary project files on the editor origin');
  assert.equal((await service.get('/host/ide/ide.mjs')).status, 404, 'asset lookup is an allowlist');

  // HTTP Save writes disk and requests nothing: saving a file that is no
  // build input starts no attempt, so only the observer schedules compilation.
  const note = await read('notes.txt');
  assert.equal((await save(note.revision, 'saved notes\n', {}, 'notes.txt')).status, 200);
  assert.equal(fs.readFileSync(notes, 'utf8'), 'saved notes\n');
  await quiet();
  assert.equal((await service.status()).id, first.id, 'Save starts no attempt');
  const initial = await read();
  const response = await save(initial.revision, program('saved'));
  assert.equal(response.status, 200);
  assert.equal(fs.readFileSync(source, 'utf8'), program('saved'));
  const saved = await response.json();
  assert.equal((await save(initial.revision, program('stale'))).status, 409);
  await service.settled(first.id);
  assert.ok(stream.seen.filter(event => event.kind === 'files').length >= 2);

  // Build is the request that asks for an attempt, and exactly one follows.
  const built = await service.command('/api/build');
  assert.equal(built.status, 202);
  const buildStatus = JSON.parse(built.text);
  assert.deepEqual(Object.keys(buildStatus).sort(), ['diagnostics', 'id', 'phase']);
  assert.equal((await service.settled(buildStatus.id)).id, buildStatus.id + 1);
  await quiet();
  assert.equal((await service.status()).id, buildStatus.id + 1, 'one Build, one attempt');

  for (const headers of [{Host: 'unrelated.example'}, {Origin: 'https://unrelated.example'}, {Origin: 'null'}, {'Sec-Fetch-Site': 'cross-site'}]) {
    for (const path of ['/api/project', '/api/status']) {
      const denied = await service.request(path, 'GET', headers);
      assert.equal(denied.status, 403);
      assert.ok(!denied.headers['access-control-allow-origin']);
      assert.ok(!denied.text.includes('main.sld') && !denied.text.includes(project));
    }
  }
  assert.equal((await service.request('/api/file?path=main.sld', 'PUT')).status, 403);
  assert.equal((await service.get('/api/file?path=../outside.sld')).status, 400);
  assert.equal((await service.get('/api/file?path=missing.sld')).status, 404);
  assert.equal((await save(saved.revision, 'text', {'If-Match': '*'})).status, 400);
  assert.equal((await save(saved.revision, 'text', {'Content-Type': 'application/json'})).status, 415);
  assert.equal((await save(saved.revision, Buffer.from([255]))).status, 400);
  assert.equal(fs.readFileSync(source, 'utf8'), program('saved'));
  const put = {Origin: url, 'Content-Type': 'text/plain', 'If-Match': `"${saved.revision}"`};
  assert.equal((await service.request('/api/file?path=main.sld', 'PUT', {...put, 'Content-Length': 8 * 1024 * 1024 + 1})).status, 413);

  // Content-Length is the only body framing: a request naming a
  // Transfer-Encoding is refused before any of its body is read, whatever its
  // method or path, so an oversized chunked body cannot reach the save.
  assert.equal((await service.request('/api/file?path=main.sld', 'PUT', put, program('chunked'))).status, 411);
  assert.equal((await service.request('/api/build', 'POST', {Origin: url}, 'chunked')).status, 411);
  assert.equal((await service.request('/api/status', 'GET', {'Transfer-Encoding': 'chunked'})).status, 411);
  assert.equal(fs.readFileSync(source, 'utf8'), program('saved'));

  // Reconnection needs no event IDs or archive: both current status and a file
  // invalidation arrive even if no files changed while the stream was absent.
  const beforeReconnect = (await service.status()).id;
  const reconnected = await service.events();
  await service.until(opened(reconnected), 'the frames of a reconnection');
  assert.deepEqual(Object.keys(reconnected.seen[0].data).sort(), ['diagnostics', 'id', 'phase']);
  assert.ok(reconnected.seen[0].data.id >= beforeReconnect && reconnected.seen[0].data.id <= (await service.status()).id);
  await reconnected.close();

  // A first status larger than the writable high-water mark must still arrive:
  // its one diagnostic names a 200,000-character identifier.
  const long = 'x'.repeat(200_000);
  let before = (await service.status()).id;
  fs.writeFileSync(source, `(import (snail core base))\n(${long})\n`);
  await service.settled(before, 'failed');
  const large = await service.events();
  await service.until(opened(large), 'a large first status');
  assert.ok(large.seen[0].data.diagnostics[0].message.includes(long));
  await large.close();
  before = (await service.status()).id;
  fs.writeFileSync(source, program('saved'));
  await service.settled(before);

  // A second service cannot take the port, and the first keeps answering.
  const second = await spawnDevelopment(root, project, Number(new URL(url).port)).exited;
  assert.equal(second.code, 1, second.stderr);
  assert.match(second.stderr, /EADDRINUSE/);
  assert.equal((await service.get('/api/project')).status, 200);

  // These requests run while the compiler blocks reading the fifo below, and
  // that build only completes once this test writes to it. A service that
  // answered from the compiler's thread would therefore deadlock here rather
  // than answer late, so the deadline distinguishes wedged from slow.
  assert.equal(spawnSync('mkfifo', [pipe]).status, 0);
  fs.writeFileSync(source, '(import (snail core base) (snail core io) (slow)) (write-line message)');
  await service.until(() => {
    try { writer = fs.openSync(pipe, fs.constants.O_WRONLY | fs.constants.O_NONBLOCK); return true; }
    catch (error) { if (error.code === 'ENXIO') return false; throw error; }
  }, 'the compiler to open the FIFO'); // A missing reader fails on the deadline rather than hanging.
  const blocked = await service.status();
  assert.equal(blocked.phase, 'building');
  assert.equal((await service.get('/api/project')).status, 200);
  assert.equal((await service.get('/api/file?path=slow.sld')).status, 400);
  const during = await read();
  assert.equal((await save(during.revision, program('edited during compilation'))).status, 200);
  fs.writeFileSync(writer, '(define-library (slow) (export message) (import (snail core base)) (begin (: message String) (define message "blocked")))');
  fs.closeSync(writer); writer = null;
  const [unblocked] = (await service.settled(blocked.id)).published.targets;
  assert.equal(unblocked.directory, fs.realpathSync(join(project, 'build/main')));
  const executed = spawnSync(process.execPath, ['--no-warnings', join(root, 'host/native/run-snail.mjs'), join(unblocked.directory, 'modules.json')], {encoding: 'utf8'});
  assert.equal(executed.status, 0, executed.stderr);
  assert.equal(executed.stdout, 'edited during compilation\n');

  for (const action of ['start', 'stop', 'restart']) {
    assert.equal((await service.request(`/api/run/${action}?target=dev`, 'POST')).status, 403);
    assert.equal((await service.request(`/api/run/${action}?target=dev`, 'POST', {Origin: 'https://unrelated.example'})).status, 403);
    assert.equal((await control(action, 'missing')).status, 404);
  }
  assert.equal((await service.request('/api/run/start?target=dev', 'POST', {Origin: url, 'Content-Length': 4}, 'body')).status, 400);
  assert.equal((await control('unknown')).status, 404);
  const current = (await service.status()).id;
  await service.until(() => statuses(stream).some(event => event.data.id === current && event.data.phase === 'succeeded'), 'the current status on the stream');
  const compilerCount = statuses(stream).length;
  const started = await control('start'); assert.equal(started.status, 204); assert.equal(started.text, '');
  const exited = await service.until(async () => { const dev = await run(); return dev.attempt?.phase === 'exited' && dev; }, 'the run to exit');
  const firstPid = exited.attempt.pid;
  assert.equal(exited.attempt.stdout, 'edited during compilation\n');
  assert.equal((await control('start')).status, 204);
  await delay(50); assert.equal((await run()).attempt.pid, firstPid);
  assert.equal((await control('restart')).status, 204);
  const rerun = await service.until(async () => { const dev = await run(); return dev.attempt?.pid !== firstPid && dev.attempt?.phase === 'exited' && dev; }, 'a restarted run to exit');
  await service.until(() => stream.seen.some(event => event.kind === 'runs' && event.data[0]?.attempt?.pid === rerun.attempt.pid && event.data[0].attempt.phase === 'exited'), 'the restarted run on the stream');
  assert.equal(statuses(stream).length, compilerCount, 'run updates do not replay compiler evidence');
  assert.equal((await control('stop')).status, 204);

  before = (await service.status()).id;
  fs.writeFileSync(join(project, 'project.datum'), '((build-target main (program (entry "main.sld"))))');
  await service.settled(before);
  assert.equal((await control('start')).status, 404); assert.equal((await control('restart')).status, 404);
  assert.equal((await control('stop')).status, 204);
  before = (await service.status()).id;
  fs.writeFileSync(join(project, 'project.datum'), config);
  fs.writeFileSync(source, '(import (snail core base) (snail core io) (snail shell task)) (write-line "running") (dispatch-local (once (lambda () (sleep 600000))))');
  await service.settled(before);
  assert.equal((await run()).wanted, false);
  assert.equal((await control('start')).status, 204);
  const livePid = (await service.until(async () => { const dev = await run(); return dev.attempt?.stdout === 'running\n' && dev; }, 'a running application')).attempt.pid;
  await stream.close();
  await delay(50); process.kill(livePid, 0); // Disconnect owns no application process.
  const runReconnect = await service.events();
  await service.until(opened(runReconnect), 'the frames of a reconnection');
  assert.equal(runReconnect.seen.find(event => event.kind === 'runs').data[0].attempt.pid, livePid);
  await runReconnect.close();

  before = (await service.status()).id;
  fs.writeFileSync(source, '(import (snail core base)) (missing)');
  await service.settled(before, 'failed');
  assert.equal((await run()).attempt.pid, livePid);
  assert.equal((await control('restart')).status, 204, 'a compiler failure does not disable accepted controls');
  const finalPid = (await service.until(async () => {
    const dev = await run();
    return dev.attempt.pid !== livePid && dev.attempt.stdout === 'running\n' && dev;
  }, 'a restarted application')).attempt.pid;

  // The ordinary signal closes the service with an undecoded body pending,
  // which then never saves, and closes its event streams and application.
  const final = await read(), closing = await service.events();
  await service.until(opened(closing), 'an event stream open at shutdown');
  const pending = http.request(new URL('/api/file?path=main.sld', url), {method: 'PUT', headers: {...put, 'If-Match': `"${final.revision}"`, 'Content-Length': 64}});
  pending.on('error', () => {}); pending.write('unfinished');
  await delay(50);
  const {code, signal, stderr} = await service.stop();
  assert.deepEqual({code, signal}, {code: 0, signal: null}, stderr);
  dead(finalPid);
  pending.destroy();
  await closing.done;
  for (const event of [...statuses(stream), ...statuses(closing)]) {
    assert.deepEqual(Object.keys(event.data).sort(), ['diagnostics', 'id', 'phase']);
  }
  assert.equal(fs.readFileSync(source, 'utf8'), final.text);
  await assert.rejects(fetch(url + '/api/project'));
} finally {
  if (writer !== null) { fs.writeFileSync(writer, '(define-library (slow) (export) (import (snail core base)) (begin))'); fs.closeSync(writer); }
  await stream.close();
  await service.stop();
  fs.rmSync(project, {recursive: true, force: true});
}

console.log('project HTTP: origin boundary, conditional saves, status, SSE, responsive compilation, runs and shutdown');
