// `snail dev` seen from outside, as its editor sees it: the URL it announces,
// HTTP (including GET /api/status and the event stream), the files on disk
// and process ids. Nothing here reaches into the service's JavaScript, so the
// tests written against it can run unchanged against the Snail service that
// replaces it.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import http from 'node:http';
import {join} from 'node:path';

export const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

// One deadline covers every wait. It is a liveness backstop for a wedged
// service, not a bound a working one approaches, even on a loaded machine.
export const liveness = 60_000;

// Whether a process has gone, for a service's application processes.
export const dead = pid => assert.throws(() => process.kill(pid, 0), {code: 'ESRCH'});

// ---- The process ----

// `snail dev --port PORT PROJECT`, with what it prints and how it ended. A
// test that fails leaves no service behind: exit sends the ordinary signal.
export function spawnDevelopment(root, project, port = 0) {
  const child = spawn(join(root, 'snail'), ['dev', '--port', String(port), project], {stdio: ['ignore', 'pipe', 'pipe']});
  const output = {stdout: '', stderr: ''}, orphan = () => child.kill('SIGTERM');
  for (const stream of ['stdout', 'stderr']) child[stream].on('data', bytes => { output[stream] += bytes; });
  process.once('exit', orphan);
  const exited = new Promise(resolve => child.once('exit', (code, signal) => {
    process.removeListener('exit', orphan);
    resolve({code, signal, stderr: output.stderr});
  }));
  return {child, output, exited};
}

// The URL the service prints once it listens, or why it never did.
async function announcement({child, output, exited}) {
  const announced = Promise.withResolvers();
  const listen = () => {
    const url = / at (http:\/\/127\.0\.0\.1:\d+)\/\n/.exec(output.stdout)?.[1];
    if (url) announced.resolve(url);
  };
  const timer = setTimeout(() => announced.reject(new Error('snail dev never announced its URL')), liveness);
  child.stdout.on('data', listen);
  void exited.then(({code, signal, stderr}) => announced.reject(new Error(`snail dev exited (${signal ?? code}) before announcing its URL: ${stderr}`)));
  try { return await announced.promise; }
  finally { clearTimeout(timer); child.stdout.off('data', listen); }
}

// A spawned service and its client. `stop` sends the ordinary signal and
// returns how the process ended.
export async function startDevelopment(root, project) {
  const spawned = spawnDevelopment(root, project), url = await announcement(spawned);
  const {child, exited} = spawned;
  return {...connect(url), pid: child.pid, exited, stop() { child.kill('SIGTERM'); return exited; }};
}

// ---- The client ----

export function connect(url) {
  // A request that never answers fails the test by name: an aborted fetch
  // otherwise raises a DOMException naming neither the request nor the wait.
  async function get(path) {
    const began = Date.now();
    try { return await fetch(url + path, {signal: AbortSignal.timeout(liveness)}); }
    catch (error) {
      if (error.name !== 'TimeoutError') throw error;
      assert.fail(`GET ${path} never answered in ${Date.now() - began} ms`);
    }
  }

  const status = async () => (await get('/api/status')).json();

  // Native HTTP permits deliberately malformed or foreign headers, and a body
  // without a Content-Length, which Node sends chunked.
  function request(path, method, headers = {}, bytes = null) {
    return new Promise((resolve, reject) => {
      const outgoing = http.request(new URL(path, url), {method, headers}, response => {
        const chunks = [];
        response.on('data', chunk => chunks.push(chunk));
        response.on('end', () => resolve({status: response.statusCode, headers: response.headers, text: Buffer.concat(chunks).toString()}));
        response.on('error', reject);
      });
      outgoing.on('error', reject);
      if (bytes) outgoing.write(bytes);
      outgoing.end();
    });
  }

  // A run control or Build, as the editor sends one: same origin, no body.
  const command = path => request(path, 'POST', {Origin: url});

  // The frames one event connection receives, in order, until it ends.
  async function events() {
    const controller = new AbortController(), response = await fetch(url + '/api/events', {signal: controller.signal});
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
    })().catch(() => {}); // Shutdown or backpressure may end a stream abruptly.
    return {seen, done, close: async () => { controller.abort(); await done; }};
  }

  // The first true value `test` returns, asked every few milliseconds. A
  // timeout reports the service's state, since the test can no longer ask.
  async function until(test, what) {
    const deadline = Date.now() + liveness;
    for (;;) {
      const value = await test();
      if (value) return value;
      if (Date.now() > deadline) {
        const state = await status().then(value => JSON.stringify(value).slice(0, 4000), error => error.message);
        assert.fail(`timed out waiting for ${what}; the service reports ${state}`);
      }
      await delay(10);
    }
  }

  // The first status of an attempt after `after` that has reached `phase`.
  const settled = (after, phase = 'succeeded') => until(async () => {
    const current = await status();
    return current.id > after && current.phase === phase && current;
  }, `an attempt after ${after} to reach ${phase}`);

  return {url, get, status, request, command, events, until, settled};
}
