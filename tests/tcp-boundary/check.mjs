// Real Wasm, JSPI and loopback sockets in both linking modes. Native spies
// place cancellation and failure at the ownership boundaries, not in a model.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {setImmediate as turn} from 'node:timers/promises';
import {createWasi, instantiate, linkProgram} from '../../src/app/load.mjs';
import {programEntry} from '../../src/app/entry.mjs';
import {createScheduler} from '../../src/app/tasks.mjs';
import {createTcp} from '../../scripts/tcp.mjs';
import {tcpImports} from '../../scripts/tcp-imports.mjs';

let program, api;
const tcp = createTcp(), reported = [];
const scheduler = createScheduler({handlerGlobals: () => program ? programEntry(program, 'main').handlers : [],
                                  reportError: error => reported.push(error)});
const host = {'snail.tcp': tcpImports(() => program, scheduler, tcp)};
const wasi = createWasi({print: (_, line) => reported.push(line)}), filename = resolve(process.argv[2]);
const invoke = (name, ...args) => scheduler.start(() => WebAssembly.promising(api[name])(...args));
const helpers = () => program.names ? program.linked.get('lofi.tcp').exports : program.runtime.exports;
const native = {listen: tcp.listen, connect: tcp.connect, read: tcp.read, write: tcp.write};
const timeout = setTimeout(() => { throw new Error('TCP boundary test timed out'); }, 30_000);

try {
  if (filename.endsWith('.json')) {
    program = await linkProgram(file => readFile(resolve(dirname(filename), file)), filename, wasi, host);
  } else {
    const runtime = await instantiate(await WebAssembly.compile(await readFile(filename)), {...wasi.getImportObject(), ...host});
    wasi.initialize(runtime);
    program = {runtime, linked: new Map()};
  }
  api = programEntry(program, 'main').exports;
  const modules = program.names ? program.names.map(name => program.linked.get(name)) : [program.runtime];
  for (const module of modules) await scheduler.start(() => WebAssembly.promising(module.exports.main)()).done;

  const listener = api.listener(await invoke('open').done), port = api.port(listener);
  const client = api.connection(await invoke('dial', port).done);
  const server = api.connection(await invoke('take', listener).done);
  const serverId = helpers()['tcp:connection-handle'](server);

  // Another effect reuses staging while the first write is suspended.
  const held = Promise.withResolvers(), release = Promise.withResolvers();
  let sent;
  tcp.write = async (signal, id, bytes) => {
    if (!sent) { sent = bytes; held.resolve(); await release.promise; }
    return native.write(signal, id, bytes);
  };
  const sending = invoke('send', client);
  await held.promise;
  assert.equal(await invoke('overwrite').done, 1);
  assert.deepEqual([...sent], [0, 255, 128, 1]);
  release.resolve();
  assert.equal(api.written(await sending.done), 4);
  tcp.write = native.write;
  const received = [];
  while (received.length < 4) {
    const chunk = await invoke('receive', server, 2).done, count = api['read-count'](chunk);
    assert.ok(count > 0 && count <= 2);
    for (let index = 0; index < count; index++) received.push(api['read-byte'](chunk, index));
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
  assert.equal(api['bad-read'](await invoke('receive', server, 1).done), 1);
  await assert.rejects(native.read(new AbortController().signal, serverId, 1), {code: 'EBADF'});
  tcp.read = native.read;
  assert.equal(api['read-count'](await invoke('receive', client, 1).done), -1, 'EOF is a typed None');

  // The native resource exists, but cancellation wins before managed delivery.
  let acquired, opening;
  tcp.listen = async (...args) => {
    acquired = await native.listen(...args);
    opening.cancel(cancelled);
    return acquired;
  };
  opening = invoke('open');
  await assert.rejects(opening.done, error => error === cancelled);
  assert.throws(() => tcp.port(acquired), {code: 'EBADF'});
  tcp.listen = native.listen;

  // A constructor trap after successful delivery still owns native cleanup.
  const original = program, fault = new WebAssembly.RuntimeError('constructor failed');
  const replacement = {exports: {...helpers(), 'tcp:connected': () => { throw fault; }}};
  if (program.names) program = {...program, linked: new Map(program.linked).set('lofi.tcp', replacement)};
  else program = {...program, runtime: replacement};
  tcp.connect = async (...args) => { acquired = await native.connect(...args); return acquired; };
  await assert.rejects(invoke('dial', port).done, error => error === fault);
  await assert.rejects(native.read(new AbortController().signal, acquired, 1), {code: 'EBADF'});
  program = original;
  tcp.connect = native.connect;

  // Uncoded host failures are not converted into recoverable network errors.
  tcp.read = () => { throw fault; };
  await assert.rejects(invoke('receive', client, 1).done, error => error === fault);
  tcp.read = native.read;
  await invoke('stop-connection', client).done;
  await invoke('stop-listener', listener).done;
  await turn();
  assert.deepEqual(reported, []);
} finally {
  await scheduler.close();
  await tcp.shutdown();
  clearTimeout(timeout);
}
console.log('TCP boundary: typed results, staging ownership, cancellation and constructor failure');
