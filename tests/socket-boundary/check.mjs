// Real Wasm, Snail-Core tasks and loopback sockets in both linking modes.
// Native spies place cancellation and failure at the ownership boundaries,
// not in a model. Cancelling closes the run of tasks, as reloading or
// ending a program does: every outstanding operation is aborted.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {setImmediate as turn} from 'node:timers/promises';
import {createWasi, instantiate, linkProgram} from '../../host/browser/load.mjs';
import {programEntry} from '../../host/browser/entry.mjs';
import {createTasks, taskExports} from '../../host/browser/tasks.mjs';
import {createTcp} from '../../host/native/tcp.mjs';
import {createUdp} from '../../host/native/udp.mjs';
import {socketImports} from '../../host/native/socket-imports.mjs';

let program, api, tasks, driving = null, requestOwner = null;
const results = [];
const tcp = createTcp(), udp = createUdp(), reported = [];
// A request waits for its task's answer, or for the trap that ended it.
const requests = new Map();
// The imports outlive each run of tasks, which cancelling replaces.
const current = {start: (...args) => tasks.start(...args), finish: ticket => tasks.finish(ticket)};
const host = {'snail.runtime.native.socket': socketImports(() => program, current, tcp, udp)};
const wasi = createWasi({print: (_, line) => reported.push(line)}), filename = resolve(process.argv[2]);

function releaseRequests() {
  if (requestOwner === null) return;
  const value = requestOwner;
  requestOwner = null;
  api['requests:release-result'](value);
}
function context() {
  if (requestOwner === null) requestOwner = api.requests();
  return requestOwner;
}
function call(name, ...args) {
  const value = api[name](...args), release = api[`${name}:release-result`];
  if (release) results.push(() => release(value));
  return value;
}
function fresh() {
  releaseRequests();
  tasks = createTasks(() => program && taskExports(program), {reportError(error, task) {
    const request = requests.get(task);
    if (!request) return reported.push(error);
    for (const pending of requests.values()) pending.reject(error);
    requests.clear();
  }});
}
function deliver() {
  for (const [id, request] of requests) {
    if (call('answered', context(), BigInt(id))) { requests.delete(id); request.resolve(call('answer', context(), BigInt(id))); }
  }
  return false;
}
// One loop drives each run's turns, and stops once a cancel replaces its
// run. A request dispatched between turns interrupts its rest; one
// dispatched after its last turn, as an answer's awaiter can, before the
// loop has ended, starts it again.
function pump() {
  if (driving) return tasks.interrupt();
  const run = tasks;
  const ended = () => { if (tasks === run) driving = null; };
  driving = run.drive(() => tasks !== run || deliver()).then(() => {
    deliver();
    ended();
    if (tasks === run && requests.size) pump();
  }, error => { reported.push(error); ended(); });
}
function cancel(reason) {
  tasks.close(reason);
  for (const request of requests.values()) request.reject(reason);
  requests.clear();
  driving = null;
  fresh();
}
function invoke(name, ...args) {
  if (tasks.signal.aborted) fresh();
  const id = Number(tasks.call(api[`begin-${name}`], context(), ...args));
  const done = new Promise((resolve, reject) => requests.set(id, {resolve, reject}));
  done.catch(() => {});
  pump();
  return {done, cancel};
}
fresh();
const native = {listen: tcp.listen, connect: tcp.connect, accept: tcp.accept, read: tcp.read, write: tcp.write};
const timeout = setTimeout(() => { throw new Error('socket boundary test timed out'); }, 30_000);

try {
  if (filename.endsWith('.json')) {
    program = await linkProgram(file => readFile(resolve(dirname(filename), file)), filename, wasi, host);
  } else {
    const runtime = await instantiate(await WebAssembly.compile(await readFile(filename)), {...wasi.getImportObject(), ...host});
    wasi.initialize(runtime);
    program = {runtime, linked: new Map()};
  }
  api = programEntry(program, 'main').exports;

  const listener = call('listener', await invoke('open').done), port = call('port', listener);
  const client = call('connection', await invoke('dial', port).done);
  let serverId;
  tcp.accept = async (...args) => (serverId = await native.accept(...args));
  const server = call('connection', await invoke('take', listener).done);
  tcp.accept = native.accept;

  // Another effect reuses staging while the first write is suspended.
  const held = Promise.withResolvers(), release = Promise.withResolvers();
  let sent;
  tcp.write = async (signal, id, bytes) => {
    if (!sent) { sent = bytes; held.resolve(); await release.promise; }
    return native.write(signal, id, bytes);
  };
  const sending = invoke('send', client);
  await held.promise;
  assert.equal(call('truth', await invoke('overwrite').done), 1);
  assert.deepEqual([...sent], [0, 255, 128, 1]);
  release.resolve();
  assert.equal(call('written', await sending.done), 4);
  tcp.write = native.write;
  const received = [];
  while (received.length < 4) {
    const chunk = await invoke('receive', server, 2).done, count = call('read-count', chunk);
    assert.ok(count > 0 && count <= 2);
    for (let index = 0; index < count; index++) received.push(call('read-byte', chunk, index));
  }
  assert.deepEqual(received, [0, 255, 128, 1]);

  // Cancelling an installed read closes its connection, and unwinds with
  // the exact reason even when that reason itself has a network error code.
  const reading = Promise.withResolvers();
  tcp.read = (signal, ...args) => { reading.resolve(); return native.read(signal, ...args); };
  const blocked = invoke('receive', server, 1);
  await reading.promise;
  const cancelled = Object.assign(new Error('cancel reading'), {code: 'EIO'});
  blocked.cancel(cancelled);
  await assert.rejects(blocked.done, error => error === cancelled);
  assert.equal(call('bad-read', await invoke('receive', server, 1).done), 1);
  await assert.rejects(native.read(new AbortController().signal, serverId, 1), {code: 'EBADF'});
  tcp.read = native.read;
  assert.equal(call('read-count', await invoke('receive', client, 1).done), -1, 'EOF is a typed None');

  // The native resource exists, but cancellation wins before managed
  // delivery. The cancelled run disposes of the listener when the
  // operation settles, after the rest of its promise chain, so a turn
  // passes before the check.
  let acquired, opening;
  tcp.listen = async (...args) => {
    acquired = await native.listen(...args);
    opening.cancel(cancelled);
    return acquired;
  };
  opening = invoke('open');
  await assert.rejects(opening.done, error => error === cancelled);
  await turn();
  assert.throws(() => tcp.port(acquired), {code: 'EBADF'});
  tcp.listen = native.listen;

  // Uncoded host failures are not converted into recoverable network errors.
  const fault = new WebAssembly.RuntimeError('host failed');
  tcp.read = () => { throw fault; };
  await assert.rejects(invoke('receive', client, 1).done, error => error === fault);
  tcp.read = native.read;
  assert.equal(call('finished', await invoke('finish', client, 1000).done), 1, 'finish after remote EOF returns typed Unit');
  call('stop-listener', listener);

  // Both tasks may finish concurrently; unread bytes are drained.
  const finishingListener = call('listener', await invoke('open').done), finishingPort = call('port', finishingListener);
  const endingClient = call('connection', await invoke('dial', finishingPort).done);
  const endingServer = call('connection', await invoke('take', finishingListener).done);
  await invoke('send', endingClient).done;
  const ending = invoke('finish', endingClient, 1000);
  assert.equal(call('finished', await invoke('finish', endingServer, 1000).done), 1);
  assert.equal(call('finished', await ending.done), 1);

  const stalled = call('connection', await invoke('dial', finishingPort).done);
  const stalledPeer = call('connection', await invoke('take', finishingListener).done);
  assert.equal(call('timed-out', await invoke('finish', stalled, 0).done), 1, 'deadline failure is a typed socket error');
  call('stop-connection', stalledPeer);

  const interrupted = call('connection', await invoke('dial', finishingPort).done);
  const interruptedPeer = call('connection', await invoke('take', finishingListener).done);
  const nativeFinish = tcp.finish, started = Promise.withResolvers();
  tcp.finish = (...args) => { const result = nativeFinish(...args); started.resolve(); return result; };
  const finishing = invoke('finish', interrupted, 1000);
  await started.promise;
  finishing.cancel(cancelled);
  await assert.rejects(finishing.done, error => error === cancelled);
  tcp.finish = nativeFinish;
  assert.equal(call('bad-read', await invoke('receive', interrupted, 1).done), 1, 'cancellation closes aliases and returns the scheduler permit');
  call('stop-connection', interruptedPeer);
  call('stop-listener', finishingListener);

  const first = call('udp-socket', await invoke('open-udp').done);
  const second = call('udp-socket', await invoke('open-udp').done);
  const firstPort = call('udp-port', first), secondPort = call('udp-port', second);
  assert.equal(call('written', await invoke('send-udp', first, secondPort).done), 4);
  const packet = await invoke('receive-udp', second, 4).done;
  assert.equal(call('packet-size', packet), 4);
  assert.equal(call('packet-port', packet), firstPort);
  assert.deepEqual([0, 1, 2, 3].map(index => call('packet-byte', packet, index)), [0, 255, 128, 1]);

  const nativeBind = udp.bind, nativeReceive = udp.receive;
  udp.bind = async (...args) => { acquired = await nativeBind(...args); opening.cancel(cancelled); return acquired; };
  opening = invoke('open-udp');
  await assert.rejects(opening.done, value => value === cancelled);
  await turn();
  assert.throws(() => udp.port(acquired), {code: 'EBADF'});

  udp.bind = nativeBind;

  const waiting = Promise.withResolvers();
  udp.receive = (signal, ...args) => { waiting.resolve(); return nativeReceive(signal, ...args); };
  const pending = invoke('receive-udp', second, 4);
  await waiting.promise;
  pending.cancel(cancelled);
  await assert.rejects(pending.done, value => value === cancelled);
  udp.receive = nativeReceive;
  assert.equal(call('udp-port', second), secondPort);
  await invoke('send-udp', first, secondPort).done;
  assert.equal(call('packet-size', await invoke('receive-udp', second, 4).done), 4, 'cancelled receive preserves UDP socket');
  call('stop-udp', first);
  call('stop-udp', second);
  await turn();
  assert.deepEqual(reported, []);
} finally {
  tasks.close();
  releaseRequests();
  for (const release of results.reverse()) release();
  await tcp.shutdown();
  await udp.shutdown();
  clearTimeout(timeout);
}
console.log('socket boundary: typed TCP/UDP results, staging ownership and cancellation');
