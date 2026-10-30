// Concrete Node TCP ownership. Scalar handles never retain managed wrappers.
// Close invalidates aliases now; shutdown waits for the remaining native close.
import {on, once} from 'node:events';
import {Server, Socket} from 'node:net';

const chunkSize = 64 * 1024, queueLimit = 64;
const fault = (code, message) => Object.assign(new Error(message), {code});
const closedError = () => fault('EBADF', 'TCP resource is closed');

// Node's event helpers wrap abort reasons. Preserve the task's exact reason so
// ordinary cancellation is not reported as a detached task failure.
function failure(resource, signal, error) {
  return signal.aborted ? signal.reason : resource.stop.signal.aborted ? resource.stop.signal.reason : error;
}

export function createTcp() {
  // Native ownership lasts through close. Public handles exist only between
  // successful publication and revocation; queued sockets need no handle.
  const owned = new Set(), handles = new Map();
  let next = 1, stopped = false;

  function own(io, kind) {
    const resource = {id: 0, io, kind, stop: new AbortController(), done: Promise.withResolvers()};
    if (kind === 'listener') { resource.queue = new Set(); resource.accepting = false; }
    else { resource.reading = false; resource.writing = false; }
    owned.add(resource);
    io.on('error', error => closeResource(resource, error));
    if (kind === 'connection') io.once('close', () => {
      // Snapshot the terminal cause before ordinary revocation supplies EBADF.
      // The wrapper distinguishes success from a null cancellation reason.
      const outcome = resource.stop.signal.aborted ? {error: resource.stop.signal.reason}
        : io.readableEnded && io.writableFinished ? null : {error: closedError()};
      closeResource(resource); finish(resource, outcome);
    });
    return resource;
  }

  function finish(resource, outcome) {
    owned.delete(resource);
    resource.done.resolve(outcome);
  }

  function publish(resource) {
    resource.stop.signal.throwIfAborted();
    if (next > 0x7fffffff) throw fault('EMFILE', 'TCP handle space exhausted');
    const id = next++;
    handles.set(id, resource);
    resource.id = id;
    return id;
  }

  function get(id, kind) {
    const resource = handles.get(id);
    if (!resource || resource.io.writableEnded) throw closedError();
    if (resource.kind !== kind) throw fault('EINVAL', `TCP operation requires a ${kind}`);
    return resource;
  }

  function closeResource(resource, reason = closedError()) {
    if (resource.stop.signal.aborted) return;
    handles.delete(resource.id);
    resource.stop.abort(reason); // Also wakes a pending accept before server.close can finish.
    if (resource.kind === 'listener') {
      for (const connection of resource.queue) closeResource(connection);
      resource.queue.clear();
      // The callback also runs for failed startup (ERR_SERVER_NOT_RUNNING).
      // A listening server waits for handed connections; ordinary close must not.
      resource.io.close(() => finish(resource));
    } else resource.io.destroy();
  }

  function incoming(listener, socket) {
    const connection = own(socket, 'connection');
    if (stopped || listener.stop.signal.aborted || listener.queue.size >= queueLimit) { closeResource(connection); return; }
    listener.queue.add(connection);
    socket.once('close', () => listener.queue.delete(connection));
  }

  // The address and port come from an Endpoint, (snail shell socket)'s
  // parsed IPv4 address and port.
  async function listen(signal, address, port) {
    signal.throwIfAborted();
    if (stopped) throw closedError();
    const listener = own(new Server({pauseOnConnect: true, allowHalfOpen: true}), 'listener');
    listener.io.on('connection', socket => incoming(listener, socket));
    const abort = () => closeResource(listener, signal.reason);
    signal.addEventListener('abort', abort, {once: true});
    try {
      listener.io.listen({host: address, port}); // Listening and bind errors are asynchronous.
      await once(listener.io, 'listening', {signal: listener.stop.signal});
      return publish(listener);
    } catch (error) {
      closeResource(listener, error); await listener.done.promise;
      throw failure(listener, signal, error);
    } finally { signal.removeEventListener('abort', abort); }
  }

  async function connect(signal, address, port) {
    signal.throwIfAborted();
    if (stopped) throw closedError();
    const connection = own(new Socket({allowHalfOpen: true}), 'connection');
    const abort = () => closeResource(connection, signal.reason);
    signal.addEventListener('abort', abort, {once: true});
    try {
      connection.io.connect({host: address, port});
      await once(connection.io, 'connect', {signal: connection.stop.signal});
      return publish(connection);
    } catch (error) {
      closeResource(connection, error); await connection.done.promise;
      throw failure(connection, signal, error);
    } finally { signal.removeEventListener('abort', abort); }
  }

  async function accept(signal, id) {
    signal.throwIfAborted();
    const listener = get(id, 'listener');
    if (listener.accepting) throw fault('EBUSY', 'TCP accept is already pending');
    listener.accepting = true;
    const wake = AbortSignal.any([signal, listener.stop.signal]);
    try {
      for (;;) {
        wake.throwIfAborted();
        const connection = listener.queue.values().next().value;
        if (!connection) { await once(listener.io, 'connection', {signal: wake}); continue; }
        if (connection.stop.signal.aborted) { listener.queue.delete(connection); continue; }
        const handle = publish(connection); // Failure leaves it listener-owned.
        listener.queue.delete(connection);
        return handle;
      }
    } catch (error) { throw failure(listener, signal, error); }
    finally { listener.accepting = false; }
  }

  async function read(signal, id, maximum) {
    signal.throwIfAborted();
    if (!Number.isInteger(maximum) || maximum <= 0 || maximum > chunkSize) throw fault('EINVAL', 'TCP read limit must be 1..65536');
    const connection = get(id, 'connection'), socket = connection.io;
    if (connection.reading) throw fault('EBUSY', 'TCP read is already pending');
    connection.reading = true;
    const abort = () => closeResource(connection, signal.reason);
    signal.addEventListener('abort', abort, {once: true});
    const wake = AbortSignal.any([signal, connection.stop.signal]);
    const notices = on(socket, 'readable', {signal: wake, close: ['end', 'close']});
    try {
      for (;;) {
        wake.throwIfAborted();
        socket.read(0); // Advance EOF even when the peer sent no bytes.
        if (socket.readableLength) return socket.read(Math.min(maximum, socket.readableLength));
        if (socket.readableEnded) return null;
        await notices.next();
      }
    } catch (error) { throw failure(connection, signal, error); }
    // Node detaches iterator listeners synchronously. An extra await here
    // would leave cancellation installed after the read already completed.
    finally { notices.return(); signal.removeEventListener('abort', abort); connection.reading = false; }
  }

  // Borrow immutable bytes until settlement; the caller must neither mutate
  // nor detach this storage. The Wasm adapter must snapshot its staging memory.
  // Node's write Boolean is backpressure, not a byte count or remote acknowledgement.
  async function write(signal, id, bytes) {
    signal.throwIfAborted();
    if (!(bytes instanceof Uint8Array)) throw fault('EINVAL', 'TCP write requires bytes');
    const connection = get(id, 'connection');
    if (connection.writing) throw fault('EBUSY', 'TCP write is already pending');
    if (!bytes.length) return 0;
    connection.writing = true;
    const abort = () => closeResource(connection, signal.reason), count = Math.min(bytes.length, chunkSize);
    signal.addEventListener('abort', abort, {once: true});
    try {
      await new Promise((resolve, reject) => connection.io.write(bytes.subarray(0, count), error => error ? reject(error) : resolve()));
      connection.stop.signal.throwIfAborted();
      return count;
    } catch (error) { throw failure(connection, signal, error); }
    finally { signal.removeEventListener('abort', abort); connection.writing = false; }
  }

  // Completion owns both directions until native close. Aliases may still
  // force close, but cannot begin more I/O. No discarded input is retained.
  async function finishConnection(signal, id, grace) {
    signal.throwIfAborted();
    if (!Number.isInteger(grace) || grace < 0 || grace > 0x7fffffff) throw fault('EINVAL', 'TCP finish grace must be 0..2147483647 ms');
    const connection = get(id, 'connection');
    if (connection.reading || connection.writing) throw fault('EBUSY', 'TCP I/O is still pending');
    const abort = () => closeResource(connection, signal.reason);
    const expire = () => closeResource(connection, fault('ETIMEDOUT', 'TCP finish grace expired'));
    let timer;
    try {
      signal.addEventListener('abort', abort, {once: true});
      if (!grace) expire();
      else { timer = setTimeout(expire, grace); connection.io.end(); connection.io.resume(); }
    } catch (error) { closeResource(connection, error); }
    try {
      const outcome = await connection.done.promise;
      if (outcome) throw outcome.error;
    } finally { clearTimeout(timer); signal.removeEventListener('abort', abort); }
  }

  async function shutdown() {
    stopped = true;
    // A late connection callback may still acquire a resource while its listener
    // closes. Incoming connections join this same owner and close immediately.
    while (owned.size) {
      const pending = [...owned];
      for (const resource of pending) closeResource(resource);
      await Promise.all(pending.map(resource => resource.done.promise));
    }
  }

  return {listen, connect, accept, read, write, finish: finishConnection,
    port: id => get(id, 'listener').io.address().port,
    close(id) { const resource = handles.get(id); if (resource) closeResource(resource); },
    shutdown};
}
