import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {serveProject} from '../scripts/project-http.mjs';
import {projectTools} from '../scripts/project.mjs';

const root = process.argv[2], project = fs.mkdtempSync(join(tmpdir(), 'lofi-project-http-'));
const source = join(project, 'main.sld'), pipe = join(project, 'slow.sld');
const program = text => `(import (lofi base) (lofi io)) (write-line "${text}")`;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(test) {
  for (let n = 0; n < 600; n++) { if (test()) return; await delay(50); }
  assert.fail('timed out waiting for project HTTP state');
}
fs.writeFileSync(join(project, 'project.datum'), '((build-target main (program (entry "main.sld") (library-roots (".")))))');
fs.writeFileSync(source, program('initial'));
const tools = projectTools(root), service = await serveProject({root, project, tools});
const get = path => fetch(service.url + path, {signal: AbortSignal.timeout(3000)});
const read = async () => (await get('/api/file?path=main.sld')).json();
const save = (revision, text, headers = {}) => fetch(service.url + '/api/file?path=main.sld', {
  method: 'PUT', headers: {Origin: service.url, 'Content-Type': 'text/plain; charset=utf-8', 'If-Match': `"${revision}"`, ...headers}, body: text,
});

// Native HTTP permits deliberately malformed/foreign headers and chunked bodies.
function request(path, method, headers = {}, bytes = null) {
  return new Promise((resolve, reject) => {
    const incoming = http.request(new URL(path, service.url), {method, headers}, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('end', () => resolve({status: response.statusCode, headers: response.headers, text: Buffer.concat(chunks).toString()}));
      response.on('error', reject);
    });
    incoming.on('error', reject);
    if (bytes) incoming.write(bytes);
    incoming.end();
  });
}

async function events() {
  const controller = new AbortController(), response = await fetch(service.url + '/api/events', {signal: controller.signal});
  assert.equal(response.status, 200);
  const seen = [], reader = response.body.getReader(), decoder = new TextDecoder();
  const done = (async () => {
    let text = '';
    for (;;) {
      const {value, done} = await reader.read();
      if (done) return;
      text += decoder.decode(value, {stream: true});
      let end;
      while ((end = text.indexOf('\n\n')) >= 0) {
        const record = text.slice(0, end); text = text.slice(end + 2);
        const match = /^event: (\w+)\ndata: ([\s\S]*)$/.exec(record);
        if (match) seen.push({kind: match[1], data: JSON.parse(match[2])});
      }
    }
  })().catch(() => {}); // Server shutdown/backpressure may end a stream abruptly.
  return {seen, done, close: async () => { controller.abort(); await done; }};
}

const stream = await events();
let writer = null;
try {
  await until(() => stream.seen.some(event => event.kind === 'files'));
  assert.equal(stream.seen[0].kind, 'status');
  await until(() => service.development.status.phase === 'succeeded');
  const projectReply = await (await get('/api/project')).json();
  assert.deepEqual(projectReply.files, ['main.sld', 'project.datum']);
  assert.equal(projectReply.name, project.split('/').at(-1));
  const page = await request('/', 'GET', {'Sec-Fetch-Site': 'cross-site', 'Sec-Fetch-Mode': 'navigate', 'Sec-Fetch-Dest': 'document'});
  assert.equal(page.status, 200);
  assert.equal(page.headers['x-frame-options'], 'DENY');
  assert.match(page.headers['content-security-policy'], /frame-ancestors 'none'/);
  assert.match(page.text, /id="save"/);
  assert.equal((await request('/', 'GET', {'Sec-Fetch-Site': 'cross-site', 'Sec-Fetch-Mode': 'navigate', 'Sec-Fetch-Dest': 'iframe'})).status, 403);
  assert.equal((await get('/main.sld')).status, 404, 'no arbitrary project files on the editor origin');
  assert.equal((await get('/src/ide/ide.mjs')).status, 404, 'asset lookup is an allowlist');
  const initial = await read(), first = service.development.status.id;

  // HTTP Save writes disk; only the independent observer schedules compilation.
  const build = service.development.requestBuild;
  let manualBuilds = 0;
  service.development.requestBuild = () => { manualBuilds++; build(); };
  const response = await save(initial.revision, program('saved'));
  assert.equal(response.status, 200);
  assert.equal(fs.readFileSync(source, 'utf8'), program('saved'));
  assert.equal(manualBuilds, 0);
  const saved = await response.json();
  assert.equal((await save(initial.revision, program('stale'))).status, 409);
  await until(() => service.development.status.id > first && service.development.status.phase === 'succeeded');
  assert.ok(stream.seen.filter(event => event.kind === 'files').length >= 2);
  const built = await request('/api/build', 'POST', {Origin: service.url});
  assert.equal(built.status, 202);
  const buildStatus = JSON.parse(built.text);
  assert.deepEqual(Object.keys(buildStatus).sort(), ['diagnostics', 'id', 'phase']);
  assert.equal(manualBuilds, 1);
  await until(() => service.development.status.id > buildStatus.id && service.development.status.phase === 'succeeded');

  for (const headers of [{Host: 'unrelated.example'}, {Origin: 'https://unrelated.example'}, {Origin: 'null'}, {'Sec-Fetch-Site': 'cross-site'}]) {
    const denied = await request('/api/project', 'GET', headers);
    assert.equal(denied.status, 403);
    assert.ok(!denied.headers['access-control-allow-origin']);
    assert.ok(!denied.text.includes('main.sld'));
  }
  assert.equal((await request('/api/file?path=main.sld', 'PUT')).status, 403);
  assert.equal((await get('/api/file?path=../outside.sld')).status, 400);
  assert.equal((await get('/api/file?path=missing.sld')).status, 404);
  assert.equal((await save(saved.revision, 'text', {'If-Match': '*'})).status, 400);
  assert.equal((await save(saved.revision, 'text', {'Content-Type': 'application/json'})).status, 415);
  assert.equal((await save(saved.revision, Buffer.from([255]))).status, 400);
  assert.equal(fs.readFileSync(source, 'utf8'), program('saved'));
  const put = {Origin: service.url, 'Content-Type': 'text/plain', 'If-Match': `"${saved.revision}"`};
  assert.equal((await request('/api/file?path=main.sld', 'PUT', {...put, 'Content-Length': 8 * 1024 * 1024 + 1})).status, 413);
  assert.equal((await request('/api/file?path=main.sld', 'PUT', put, Buffer.alloc(8 * 1024 * 1024 + 1, 65))).status, 413);
  assert.equal(fs.readFileSync(source, 'utf8'), program('saved'));

  // Reconnection needs no event IDs or archive: both current status and a file
  // invalidation arrive even if no files changed while the stream was absent.
  const beforeReconnect = service.development.status.id;
  const reconnected = await events();
  await until(() => reconnected.seen.some(event => event.kind === 'files'));
  assert.deepEqual(Object.keys(reconnected.seen[0].data).sort(), ['diagnostics', 'id', 'phase']);
  assert.ok(reconnected.seen[0].data.id >= beforeReconnect && reconnected.seen[0].data.id <= service.development.status.id);
  await reconnected.close();

  // A first status larger than the writable high-water mark must still arrive.
  const largeMessage = 'diagnostic '.repeat(20_000);
  const {diagnostics} = service.development.status;
  diagnostics.push({severity: 'error', message: largeMessage});
  const large = await events();
  await until(() => large.seen.some(event => event.kind === 'files'));
  assert.equal(large.seen[0].data.diagnostics[0].message, largeMessage);
  await large.close();
  diagnostics.pop();
  await assert.rejects(serveProject({root, project, tools, port: Number(new URL(service.url).port)}), {code: 'EADDRINUSE'});
  assert.equal((await get('/api/project')).status, 200);

  await until(() => service.development.status.phase === 'succeeded');
  assert.equal(spawnSync('mkfifo', [pipe]).status, 0);
  fs.writeFileSync(source, '(import (lofi base) (lofi io) (slow)) (write-line message)');
  // A missing reader must fail on a deadline rather than hang the suite.
  await until(() => {
    try { writer = fs.openSync(pipe, fs.constants.O_WRONLY | fs.constants.O_NONBLOCK); return true; }
    catch (error) { if (error.code === 'ENXIO') return false; throw error; }
  }); // The real compiler has opened the pipe.
  assert.equal(service.development.status.phase, 'building');
  const blocked = service.development.status.id;
  assert.equal((await get('/api/project')).status, 200);
  assert.equal((await get('/api/file?path=slow.sld')).status, 400);
  const during = await read();
  assert.equal((await save(during.revision, program('edited during compilation'))).status, 200);
  fs.writeFileSync(writer, '(define-library (slow) (export message) (import (lofi base)) (begin (: message String) (define message "blocked")))');
  fs.closeSync(writer); writer = null;
  await until(() => service.development.status.id > blocked && service.development.status.phase === 'succeeded');
  const manifest = join(service.development.status.published.targets[0].directory, 'modules.json');
  const executed = spawnSync(process.execPath, ['--no-warnings', join(root, 'scripts/run-lofi.mjs'), manifest], {encoding: 'utf8'});
  assert.equal(executed.status, 0, executed.stderr);
  assert.equal(executed.stdout, 'edited during compilation\n');

  // Closing with an undecoded body prevents its later save, and closes active
  // SSE and keepalive connections along with the development session.
  const final = await read();
  const pending = http.request(new URL('/api/file?path=main.sld', service.url), {method: 'PUT', headers: {...put, 'If-Match': `"${final.revision}"`}});
  pending.on('error', () => {}); pending.write('unfinished');
  await delay(50);
  await service.close();
  pending.destroy();
  await stream.done;
  for (const event of stream.seen.filter(event => event.kind === 'status')) {
    assert.deepEqual(Object.keys(event.data).sort(), ['diagnostics', 'id', 'phase']);
  }
  assert.equal(fs.readFileSync(source, 'utf8'), final.text);
  await service.closed;
  await assert.rejects(get('/api/project'));
} finally {
  if (writer !== null) { fs.writeFileSync(writer, '(define-library (slow) (export) (import (lofi base)) (begin))'); fs.closeSync(writer); }
  await stream.close();
  await service.close();
  fs.rmSync(project, {recursive: true, force: true});
}
console.log('project HTTP: origin boundary, conditional saves, SSE, responsive compilation and close');
