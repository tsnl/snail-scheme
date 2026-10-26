// Real loopback sockets exercise resource ownership independently of Wasm.
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {connect, Server, Socket} from 'node:net';
import {setTimeout as delay} from 'node:timers/promises';
import {createTcp} from '../host/native/tcp.mjs';

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
    await assert.rejects(tcp.finish(signal, outgoing, 1000), {code: 'EBUSY'}, 'finish cannot take a pending write');
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

async function peerConnection(tcp) {
  const listener = await tcp.listen(signal, '127.0.0.1', 0), client = await peer(tcp.port(listener));
  return {listener, client, connection: await tcp.accept(signal, listener)};
}

async function gracefulTransfer() {
  for (const peerEndsFirst of [false, true]) {
    const tcp = createTcp(); let client;
    try {
      const pair = await peerConnection(tcp); client = pair.client;
      const response = Buffer.alloc(130_000, 123), chunks = [], eof = once(client, 'end');
      client.on('data', bytes => chunks.push(bytes));
      client.once('end', () => { if (!client.writableEnded) client.end('final unread bytes'); });
      if (peerEndsFirst) {
        client.end('request');
        while (await tcp.read(signal, pair.connection, 32) !== null) {}
      } else client.write(Buffer.alloc(130_000, 42));
      for (let offset = 0; offset < response.length;)
        offset += await tcp.write(signal, pair.connection, response.subarray(offset));
      const finishing = tcp.finish(signal, pair.connection, 2000);
      await assert.rejects(tcp.read(signal, pair.connection, 1), {code: 'EBADF'});
      await assert.rejects(tcp.write(signal, pair.connection, new Uint8Array()), {code: 'EBADF'});
      await assert.rejects(tcp.finish(signal, pair.connection, 1000), {code: 'EBADF'});
      await finishing; await eof;
      assert.deepEqual(Buffer.concat(chunks), response, 'finish preserves the whole response despite unread input');
    } finally { client?.destroy(); await tcp.shutdown(); }
  }
}

async function gracefulOwnership() {
  const tcp = createTcp(); let client;
  try {
    const pair = await peerConnection(tcp); client = pair.client;
    for (const grace of [-1, 0.5, Infinity, 0x80000000])
      await assert.rejects(tcp.finish(signal, pair.connection, grace), {code: 'EINVAL'});
    const reading = tcp.read(signal, pair.connection, 32);
    await assert.rejects(tcp.finish(signal, pair.connection, 1000), {code: 'EBUSY'});
    client.write('still open'); assert.equal((await reading).toString(), 'still open');
    const cancelled = new AbortController(), reason = new Error('not started');
    cancelled.abort(reason);
    await assert.rejects(tcp.finish(cancelled.signal, pair.connection, 1000), error => error === reason);
    assert.equal(await tcp.write(signal, pair.connection, new Uint8Array()), 0, 'pre-abort leaves ownership unchanged');

    const finishing = assert.rejects(tcp.finish(signal, pair.connection, 1000), {code: 'EBADF'});
    tcp.close(pair.connection); await finishing;
    await assert.rejects(tcp.read(signal, pair.connection, 1), {code: 'EBADF'});
  } finally { client?.destroy(); await tcp.shutdown(); }
}

async function gracefulDeadlineAndAbort() {
  for (const mode of ['timeout', 'zero', 'abort', 'null', 'shutdown']) {
    const tcp = createTcp(), controller = new AbortController(); let client;
    try {
      const pair = await peerConnection(tcp); client = pair.client;
      client.resume(); // Observe FIN without closing our writable side.
      const reason = mode === 'null' ? null : new Error('cancel graceful finish');
      const rejected = assert.rejects(tcp.finish(controller.signal, pair.connection, mode === 'zero' ? 0 : mode === 'timeout' ? 30 : 1000),
        error => mode === 'abort' || mode === 'null' ? error === reason : error.code === (mode === 'shutdown' ? 'EBADF' : 'ETIMEDOUT'));
      if (mode === 'abort' || mode === 'null') controller.abort(reason);
      if (mode === 'zero') controller.abort(new Error('later than zero grace'));
      if (mode === 'shutdown') await tcp.shutdown();
      await rejected;
      await assert.rejects(tcp.write(signal, pair.connection, new Uint8Array()), {code: 'EBADF'});
    } finally { client?.destroy(); await tcp.shutdown(); }
  }
}

async function gracefulCloseOrdering() {
  for (const cause of ['clean', 'error', 'abort']) {
    const tcp = createTcp(), controller = new AbortController(), emit = Socket.prototype.emit;
    const reason = Object.assign(new Error('first terminal cause'), {code: 'ECONNRESET'});
    let client, ownedSocket, nativeClosed = false;
    try {
      const pair = await peerConnection(tcp); client = pair.client;
      const port = tcp.port(pair.listener);
      Socket.prototype.emit = function(event, ...args) {
        if (this.localPort === port) ownedSocket = this;
        if (this === ownedSocket && event === 'finish' && cause === 'error') emit.call(this, 'error', reason);
        if (this === ownedSocket && event === 'finish' && cause === 'abort') controller.abort(reason);
        const result = emit.call(this, event, ...args);
        if (this === ownedSocket && event === 'close') { nativeClosed = true; controller.abort(new Error('after native close')); }
        return result;
      };
      client.end(); client.resume();
      const finishing = tcp.finish(controller.signal, pair.connection, 1000);
      if (cause === 'clean') await finishing;
      else await assert.rejects(finishing, error => error === reason);
      assert.ok(nativeClosed, 'finish waits for physical close and retains its first outcome');
    } finally { Socket.prototype.emit = emit; client?.destroy(); await tcp.shutdown(); }
  }
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
  await gracefulTransfer();
  await gracefulOwnership();
  await gracefulDeadlineAndAbort();
  await gracefulCloseOrdering();
  console.log('TCP: partial transfers, graceful finish, cancellation, queued ownership and shutdown');
} finally { clearTimeout(watchdog); }
