// Real loopback sockets exercise resource ownership independently of Wasm.
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {connect, Server, Socket} from 'node:net';
import {setTimeout as delay} from 'node:timers/promises';
import {createTcp} from '../scripts/tcp.mjs';

const signal = new AbortController().signal;
const watchdog = setTimeout(() => { console.error('TCP test did not release its resources'); process.exit(1); }, 20_000);
watchdog.unref();
async function peer(port) {
  const socket = connect({host: '127.0.0.1', port, allowHalfOpen: true});
  socket.on('error', () => {}); // Intentional close/cancellation can reset the peer.
  await once(socket, 'connect');
  return socket;
}
async function receive(socket, length) {
  const chunks = []; let size = 0;
  for await (const chunk of socket.iterator({destroyOnReturn: false})) {
    chunks.push(chunk); size += chunk.length;
    if (size >= length) return Buffer.concat(chunks);
  }
  assert.fail('peer ended before receiving the expected bytes');
}
async function pair(tcp) {
  const listener = await tcp.listen(signal, '127.0.0.1', 0);
  const connecting = tcp.connect(signal, '127.0.0.1', tcp.port(listener));
  const incoming = await tcp.accept(signal, listener), outgoing = await connecting;
  return {listener, incoming, outgoing};
}

async function transfers() {
  const tcp = createTcp(); let client;
  try {
    const listener = await tcp.listen(signal, '127.0.0.1', 0), port = tcp.port(listener);
    assert.ok(port > 0);
    await assert.rejects(tcp.listen(signal, '127.0.0.1', port), {code: 'EADDRINUSE'});
    client = await peer(port);
    const connection = await tcp.accept(signal, listener);
    assert.ok(connection > listener, 'handles are allocated monotonically');
    const reading = tcp.read(signal, connection, 100);
    await assert.rejects(tcp.read(signal, connection, 1), {code: 'EBUSY'});
    const greeting = receive(client, 2), writing = tcp.write(signal, connection, Buffer.from('hi'));
    await assert.rejects(tcp.write(signal, connection, Buffer.from('overlap')), {code: 'EBUSY'});
    assert.equal(await writing, 2);
    assert.equal((await greeting).toString(), 'hi', 'read and write may overlap');
    client.write('ab');
    assert.equal((await reading).toString(), 'ab', 'an available prefix returns while the peer remains open');

    client.write('cdef');
    assert.equal((await tcp.read(signal, connection, 2)).toString(), 'cd');
    assert.equal((await tcp.read(signal, connection, 2)).toString(), 'ef');
    client.end();
    assert.equal(await tcp.read(signal, connection, 10), null);
    assert.equal(await tcp.read(signal, connection, 10), null, 'EOF remains observable');
    const completed = new AbortController(), eof = tcp.read(completed.signal, connection, 1);
    completed.abort(new Error('read already completed'));
    assert.equal(await eof, null);
    assert.equal(await tcp.write(signal, connection, new Uint8Array()), 0, 'completed reads detach cancellation');

    tcp.close(listener); tcp.close(listener);
    assert.throws(() => tcp.port(listener), {code: 'EBADF'});
    const bytes = Buffer.alloc(70_000, 42), delivered = receive(client, 65_536);
    assert.equal(await tcp.write(signal, connection, bytes), 65_536, 'write reports one bounded prefix');
    assert.deepEqual(await delivered, bytes.subarray(0, 65_536), 'listener close and remote EOF leave a handed connection writable');
    assert.equal(await tcp.write(signal, connection, new Uint8Array()), 0);
    await assert.rejects(tcp.read(signal, connection, 0), {code: 'EINVAL'});
    await assert.rejects(tcp.read(signal, connection, 65_537), {code: 'EINVAL'});
    tcp.close(connection);
    await assert.rejects(tcp.write(signal, connection, bytes), {code: 'EBADF'});
    assert.ok(await tcp.listen(signal, '127.0.0.1', 0) > connection);
    await assert.rejects(tcp.read(signal, connection, 1), {code: 'EBADF'}, 'closed handles never name later resources');
  } finally { client?.destroy(); await tcp.shutdown(); }
}

async function cancellation() {
  const tcp = createTcp();
  try {
    const listener = await tcp.listen(signal, '127.0.0.1', 0), port = tcp.port(listener);
    const accepting = new AbortController(), reason = new Error('cancel this accept');
    const pending = tcp.accept(accepting.signal, listener);
    await assert.rejects(tcp.accept(signal, listener), {code: 'EBUSY'});
    accepting.abort(reason);
    await assert.rejects(pending, error => error === reason);
    assert.equal(tcp.port(listener), port, 'cancelling accept preserves its listener');
    const connecting = tcp.connect(signal, '127.0.0.1', port);
    const incoming = await tcp.accept(signal, listener), outgoing = await connecting;
    const reading = new AbortController(), readReason = new Error('cancel this read');
    const read = tcp.read(reading.signal, incoming, 32);
    reading.abort(readReason);
    await assert.rejects(read, error => error === readReason);
    await assert.rejects(tcp.read(signal, incoming, 1), {code: 'EBADF'});
    assert.equal(await tcp.read(signal, outgoing, 1), null, 'cancelled read closes the connection at its peer');
    tcp.close(outgoing);

    const waiting = tcp.accept(signal, listener);
    tcp.close(listener);
    await assert.rejects(waiting, {code: 'EBADF'}, 'logical listener close immediately rejects accept');
  } finally { await tcp.shutdown(); }
}

async function queuedConnections() {
  const tcp = createTcp(), clients = [];
  try {
    const listener = await tcp.listen(signal, '127.0.0.1', 0), port = tcp.port(listener);
    for (let index = 0; index < 65; index++) {
      const socket = await peer(port);
      socket.on('end', () => socket.end()); socket.resume();
      clients.push(socket);
    }
    for (let tries = 0; !clients.some(socket => socket.destroyed) && tries < 100; tries++) await delay(10);
    assert.equal(clients.filter(socket => socket.destroyed).length, 1, 'only 64 unclaimed connections are retained');
    tcp.close(listener);
    for (let tries = 0; clients.some(socket => !socket.destroyed) && tries < 100; tries++) await delay(10);
    assert.ok(clients.every(socket => socket.destroyed), 'listener close releases all unclaimed sockets');
  } finally { for (const client of clients) client.destroy(); await tcp.shutdown(); }
}

async function cancelledWrite() {
  const tcp = createTcp();
  try {
    const {outgoing} = await pair(tcp), controller = new AbortController(), bytes = Buffer.alloc(65_536, 7);
    let pending;
    // The accepted socket stays paused. Fill the OS send window until one
    // bounded write is genuinely pending; no artificial write implementation.
    for (let count = 0; count < 256; count++) {
      const writing = tcp.write(controller.signal, outgoing, bytes);
      if (!await Promise.race([writing.then(() => true), delay(10).then(() => false)])) { pending = writing; break; }
    }
    assert.ok(pending, 'the unread peer eventually applies backpressure');
    const reason = new Error('cancel blocked write');
    controller.abort(reason);
    await assert.rejects(pending, error => error === reason);
    await assert.rejects(tcp.write(signal, outgoing, bytes), {code: 'EBADF'});
  } finally { await tcp.shutdown(); }
}

async function shutdownAndStartup() {
  const tcp = createTcp();
  await assert.rejects(tcp.listen(signal, 'localhost', 0), {code: 'EINVAL'});
  await assert.rejects(tcp.listen(signal, '127.0.0.1', -1), {code: 'EINVAL'});
  await assert.rejects(tcp.connect(signal, '127.0.0.1', 0), {code: 'ECONNREFUSED'});
  const controller = new AbortController(), reason = new Error('cancel startup');
  const listening = tcp.listen(controller.signal, '127.0.0.1', 0);
  controller.abort(reason);
  await assert.rejects(listening, error => error === reason);
  for (const operation of [
    () => tcp.listen(controller.signal, '127.0.0.1', 0),
    () => tcp.connect(controller.signal, '127.0.0.1', 0),
    () => tcp.accept(controller.signal, -1),
    () => tcp.read(controller.signal, -1, 1),
    () => tcp.write(controller.signal, -1, new Uint8Array()),
  ]) await assert.rejects(operation(), error => error === reason);
  const {listener, incoming, outgoing} = await pair(tcp);
  const read = assert.rejects(tcp.read(signal, incoming, 1), {code: 'EBADF'});
  const accept = assert.rejects(tcp.accept(signal, listener), {code: 'EBADF'});
  await Promise.all([tcp.shutdown(), tcp.shutdown()]);
  await read; await accept;
  await assert.rejects(tcp.write(signal, outgoing, Buffer.from('closed')), {code: 'EBADF'});
  await assert.rejects(tcp.listen(signal, '127.0.0.1', 0), {code: 'EBADF'});
  await tcp.shutdown();

  const starting = createTcp(), pending = starting.listen(signal, '127.0.0.1', 0);
  const rejected = assert.rejects(pending, {code: 'EBADF'});
  await starting.shutdown(); await rejected;
}

// Native completion can resolve a Promise before its async caller continues.
// Keep the real socket operations and inject cancellation into that exact gap.
async function completedCreation() {
  const tcp = createTcp();
  try {
    const listener = await tcp.listen(signal, '127.0.0.1', 0), port = tcp.port(listener);
    for (const [prototype, event, start] of [
      [Server.prototype, 'listening', signal => tcp.listen(signal, '127.0.0.1', 0)],
      [Socket.prototype, 'connect', signal => tcp.connect(signal, '127.0.0.1', port)],
    ]) {
      const controller = new AbortController(), reason = new Error(`cancel after ${event}`), emit = prototype.emit;
      prototype.emit = function(name, ...args) {
        const result = emit.call(this, name, ...args);
        if (name === event) controller.abort(reason);
        return result;
      };
      try { await assert.rejects(start(controller.signal), error => error === reason); }
      finally { prototype.emit = emit; }
    }
  } finally { await tcp.shutdown(); }
}

async function completedWrite() {
  const tcp = createTcp(), controller = new AbortController(), reason = new Error('cancel after native write');
  const write = Socket.prototype.write;
  try {
    const {outgoing} = await pair(tcp);
    Socket.prototype.write = function(bytes, callback) {
      return write.call(this, bytes, error => { callback(error); controller.abort(reason); });
    };
    await assert.rejects(tcp.write(controller.signal, outgoing, Buffer.from('sent')), error => error === reason);
  } finally { Socket.prototype.write = write; await tcp.shutdown(); }
}

async function failedQueuedConnection() {
  const tcp = createTcp(), clients = [], emit = Server.prototype.emit, failed = Promise.withResolvers();
  try {
    const listener = await tcp.listen(signal, '127.0.0.1', 0), port = tcp.port(listener);
    Server.prototype.emit = function(event, ...args) {
      const result = emit.call(this, event, ...args);
      if (event === 'connection') {
        args[0].emit('error', Object.assign(new Error('reset before accept'), {code: 'ECONNRESET'}));
        failed.resolve();
      }
      return result;
    };
    const accepting = tcp.accept(signal, listener);
    clients.push(await peer(port));
    await failed.promise;
    Server.prototype.emit = emit;
    const healthy = await peer(port); clients.push(healthy);
    const connection = await accepting;
    healthy.write('ok');
    assert.equal((await tcp.read(signal, connection, 2)).toString(), 'ok', 'accept skips revoked queued connections');
  } finally { Server.prototype.emit = emit; for (const client of clients) client.destroy(); await tcp.shutdown(); }
}

try {
  await transfers();
  await cancellation();
  await queuedConnections();
  await cancelledWrite();
  await shutdownAndStartup();
  await completedCreation();
  await completedWrite();
  await failedQueuedConnection();
  console.log('TCP: partial transfers, half-close, cancellation, queued ownership and shutdown');
} finally { clearTimeout(watchdog); }
