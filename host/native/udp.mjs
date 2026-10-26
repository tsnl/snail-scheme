// Concrete IPv4 datagrams. Records retain native ownership through close;
// a stopped record immediately rejects every alias of its public handle.
import {createSocket} from 'node:dgram';
import {once} from 'node:events';
import {isIPv4} from 'node:net';

const datagramLimit = 65507, queueLimit = 32;
const fault = (code, message) => Object.assign(new Error(message), {code});
const closedError = () => fault('EBADF', 'UDP socket is closed');

function endpoint(address, port, zero) {
  if (typeof address !== 'string' || !isIPv4(address)) throw fault('EINVAL', 'UDP requires a numeric IPv4 address');
  if (!Number.isInteger(port) || port < (zero ? 0 : 1) || port > 65535) throw fault('EINVAL', 'UDP port is outside its range');
}

export function createUdp() {
  const resources = new Map();
  let next = 1, stopped = false;

  function own() {
    if (next > 0x7fffffff) throw fault('EMFILE', 'UDP handle space exhausted');
    const resource = {id: next++, io: createSocket('udp4'), stop: new AbortController(), done: Promise.withResolvers(),
                      queue: [], receiving: false, sending: false};
    resources.set(resource.id, resource);
    resource.io.on('error', error => closeResource(resource, error));
    resource.io.on('message', (bytes, peer) => {
      if (!resource.stop.signal.aborted && resource.queue.length < queueLimit) resource.queue.push({bytes, address: peer.address, port: peer.port});
    });
    resource.io.once('close', () => { resources.delete(resource.id); resource.done.resolve(); });
    return resource;
  }

  function get(id) {
    const resource = resources.get(id);
    if (!resource || resource.stop.signal.aborted) throw closedError();
    return resource;
  }

  function closeResource(resource, reason = closedError()) {
    if (resource.stop.signal.aborted) return;
    resource.stop.abort(reason);
    resource.queue.length = 0;
    // Node's send still does async lookup for numeric addresses. Closing its
    // socket during lookup can suppress the send callback. Defer native close
    // until that callback releases the borrowed bytes; aliases are revoked now.
    if (!resource.sending) resource.io.close();
  }

  async function bind(signal, address, port) {
    signal.throwIfAborted(); endpoint(address, port, true);
    if (stopped) throw closedError();
    const resource = own();
    try {
      // Node >=26.4 binds numeric addresses with a nonblocking local syscall.
      // There is no asynchronous opening registration or DNS resolution.
      resource.io.bindSync({address, port});
      return resource.id;
    } catch (error) {
      closeResource(resource, error); await resource.done.promise;
      signal.throwIfAborted(); throw error;
    }
  }

  async function receive(signal, id, maximum) {
    signal.throwIfAborted();
    if (!Number.isInteger(maximum) || maximum < 0 || maximum > datagramLimit) throw fault('EINVAL', 'UDP receive limit must be 0..65507');
    const resource = get(id);
    if (resource.receiving) throw fault('EBUSY', 'UDP receive is already pending');
    resource.receiving = true;
    try {
      const wake = AbortSignal.any([signal, resource.stop.signal]);
      for (;;) {
        wake.throwIfAborted();
        const datagram = resource.queue.shift();
        if (!datagram) { await once(resource.io, 'message', {signal: wake}); continue; }
        if (datagram.bytes.length > maximum) throw fault('EMSGSIZE', 'UDP datagram exceeds the receive limit');
        return datagram;
      }
    } catch (error) {
      throw signal.aborted ? signal.reason : resource.stop.signal.aborted ? resource.stop.signal.reason : error;
    } finally { resource.receiving = false; }
  }

  // Borrow immutable bytes through native completion. Cancellation cannot
  // retract a send, so it waits for the callback and leaves the socket usable.
  async function send(signal, id, address, port, bytes) {
    signal.throwIfAborted(); endpoint(address, port, false);
    if (!(bytes instanceof Uint8Array)) throw fault('EINVAL', 'UDP send requires bytes');
    if (bytes.length > datagramLimit) throw fault('EMSGSIZE', 'UDP datagram exceeds 65507 bytes');
    const resource = get(id), count = bytes.length;
    if (resource.sending) throw fault('EBUSY', 'UDP send is already pending');
    resource.sending = true;
    try {
      await new Promise((resolve, reject) => resource.io.send(bytes, port, address, error => error ? reject(error) : resolve()));
    } catch (error) {
      throw signal.aborted ? signal.reason : resource.stop.signal.aborted ? resource.stop.signal.reason : error;
    } finally {
      resource.sending = false;
      if (resource.stop.signal.aborted) resource.io.close();
    }
    signal.throwIfAborted(); resource.stop.signal.throwIfAborted();
    return count;
  }

  async function shutdown() {
    stopped = true;
    const pending = [...resources.values()];
    for (const resource of pending) closeResource(resource);
    await Promise.all(pending.map(resource => resource.done.promise));
  }

  return {bind, receive, send,
    port: id => get(id).io.address().port,
    close(id) { const resource = resources.get(id); if (resource) closeResource(resource); },
    shutdown};
}
