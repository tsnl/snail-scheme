// Actual IPv4 sockets, with native callbacks observed at the ownership races.
import assert from 'node:assert/strict';
import {Socket} from 'node:dgram';
import {getEventListeners, once} from 'node:events';
import {createUdp} from '../host/native/udp.mjs';

const udp = createUdp(), signal = new AbortController().signal, sockets = [], closed = new Set();
const bind = Socket.prototype.bindSync, send = Socket.prototype.send;
Socket.prototype.bindSync = function (...args) {
  sockets.push(this);
  this.once('close', () => closed.add(this));
  return bind.apply(this, args);
};
const timeout = setTimeout(() => { throw new Error('UDP ownership test timed out'); }, 30_000);
const error = code => ({code});

try {
  const first = await udp.bind(signal, '127.0.0.1', 0, 32), firstSocket = sockets.at(-1);
  const second = await udp.bind(signal, '127.0.0.1', 0, 32), secondSocket = sockets.at(-1);
  const firstPort = udp.port(first), secondPort = udp.port(second);
  const transmit = bytes => udp.send(signal, first, '127.0.0.1', secondPort, Uint8Array.from(bytes));
  assert.notEqual(firstPort, secondPort);

  assert.equal(await transmit([]), 0);
  const empty = await udp.receive(signal, second, 0);
  assert.deepEqual([...empty.bytes], []);
  assert.equal(empty.address, '127.0.0.1');
  assert.equal(empty.port, firstPort);
  await transmit([0, 255, 128, 1]);
  assert.deepEqual([...(await udp.receive(signal, second, 4)).bytes], [0, 255, 128, 1]);

  await transmit([1, 2, 3]);
  await assert.rejects(udp.receive(signal, second, 2), error('EMSGSIZE'));
  await transmit([4]);
  assert.deepEqual([...(await udp.receive(signal, second, 1)).bytes], [4], 'oversized packet was consumed completely');

  const maximum = new Uint8Array(65507).fill(173);
  assert.equal(await udp.send(signal, first, '127.0.0.1', secondPort, maximum), maximum.length);
  assert.deepEqual((await udp.receive(signal, second, maximum.length)).bytes, Buffer.from(maximum));

  // Duplicate operations do not queue more work.
  const controller = new AbortController(), reason = Object.assign(new Error('cancel receive'), {code: 'EIO'});
  const receiving = udp.receive(controller.signal, second, 1);
  await assert.rejects(udp.receive(signal, second, 1), error('EBUSY'));
  controller.abort(reason);
  await assert.rejects(receiving, value => value === reason);
  const sending = transmit([5]);
  await assert.rejects(transmit([6]), error('EBUSY'));
  assert.equal(await sending, 1);
  assert.deepEqual([...(await udp.receive(signal, second, 1)).bytes], [5]);

  // Repeated cancellation removes event registrations and preserves the socket.
  for (let index = 0; index < 12; index++) {
    const controller = new AbortController(), waiting = udp.receive(controller.signal, second, 1);
    controller.abort(reason);
    await assert.rejects(waiting, value => value === reason);
  }
  assert.equal(getEventListeners(secondSocket, 'message').length, 1);
  assert.equal(getEventListeners(secondSocket, 'error').length, 1);

  // Observe arrival rather than guessing when the OS has serviced the queue.
  for (let index = 0; index < 40; index++) {
    const arrived = once(secondSocket, 'message');
    await transmit([index]);
    await arrived;
  }
  for (let index = 0; index < 32; index++) {
    assert.deepEqual([...(await udp.receive(signal, second, 1)).bytes], [index]);
  }
  await transmit([90]);
  assert.deepEqual([...(await udp.receive(signal, second, 1)).bytes], [90], 'overflow dropped the newest packets');

  await assert.rejects(udp.send(signal, first, '127.0.0.1', secondPort, []), error('EINVAL'));
  const aborted = AbortSignal.abort(reason), before = sockets.length;
  await assert.rejects(udp.bind(aborted, '127.0.0.1', 0, 32), value => value === reason);
  await assert.rejects(udp.receive(aborted, second, 1), value => value === reason);
  await assert.rejects(udp.send(aborted, first, '127.0.0.1', secondPort, new Uint8Array()), value => value === reason);
  assert.equal(sockets.length, before, 'pre-cancelled bind allocates nothing');
  await assert.rejects(udp.bind(signal, '127.0.0.1', firstPort, 32), error('EADDRINUSE'));
  assert.ok(closed.has(sockets.at(-1)), 'failed bind awaits native cleanup');

  // Cancellation alone waits for a real callback, then preserves the socket.
  const cancelling = new AbortController(), transmitted = once(secondSocket, 'message');
  const cancelledSend = udp.send(cancelling.signal, first, '127.0.0.1', secondPort, Uint8Array.of(7));
  cancelling.abort(reason);
  await assert.rejects(cancelledSend, value => value === reason);
  await transmitted;
  assert.equal(udp.port(first), firstPort);
  assert.deepEqual([...(await udp.receive(signal, second, 1)).bytes], [7], 'cancellation cannot retract an issued datagram');

  // A callback failure is local to that datagram. Keep using the same socket.
  Socket.prototype.send = function (...args) {
    queueMicrotask(() => args.at(-1)(Object.assign(new Error('native send failed'), {code: 'EMSGSIZE'})));
  };
  await assert.rejects(transmit([8]), error('EMSGSIZE'));
  assert.equal(udp.port(first), firstPort);
  Socket.prototype.send = send;
  await transmit([9]);
  assert.deepEqual([...(await udp.receive(signal, second, 1)).bytes], [9]);

  // Close during native lookup/send. The callback must settle before close,
  // including with Node's --test-udp-no-try-send forcing its asynchronous path.
  const closing = await udp.bind(signal, '127.0.0.1', 0, 32), closingSocket = sockets.at(-1), order = [];
  closingSocket.on('close', () => order.push('close'));
  Socket.prototype.send = function (...args) {
    const callback = args.pop();
    return send.call(this, ...args, (...result) => { order.push('send'); callback(...result); });
  };
  const pendingSend = udp.send(signal, closing, '127.0.0.1', secondPort, new Uint8Array());
  const rejected = assert.rejects(pendingSend, error('EBADF'));
  udp.close(closing);
  udp.close(closing);
  assert.throws(() => udp.port(closing), error('EBADF'));
  await rejected;
  if (!closed.has(closingSocket)) await once(closingSocket, 'close');
  assert.deepEqual(order, ['send', 'close']);
  Socket.prototype.send = send;

  const failed = await udp.bind(signal, '127.0.0.1', 0, 32), failedSocket = sockets.at(-1);
  const broken = udp.receive(signal, failed, 1), failure = Object.assign(new Error('socket failed'), {code: 'EIO'});
  failedSocket.emit('error', failure);
  await assert.rejects(broken, value => value === failure);
  assert.throws(() => udp.port(failed), error('EBADF'));

  // Shutdown interrupts overlapping receive/send, retaining ownership until
  // the send callback and subsequent native close have both happened.
  const shutdownOrder = [];
  firstSocket.once('close', () => shutdownOrder.push('close'));
  Socket.prototype.send = function (...args) {
    const callback = args.pop();
    return send.call(this, ...args, (...result) => { shutdownOrder.push('send'); callback(...result); });
  };
  const blocked = udp.receive(signal, first, 1), rejection = assert.rejects(blocked, error('EBADF'));
  const outgoing = transmit([10]), outgoingRejection = assert.rejects(outgoing, error('EBADF'));
  const shutdown = udp.shutdown().then(() => shutdownOrder.push('shutdown'));
  await Promise.all([shutdown, udp.shutdown(), rejection, outgoingRejection]);
  assert.deepEqual(shutdownOrder, ['send', 'close', 'shutdown']);
  assert.equal(closed.size, sockets.length);
  assert.ok(closed.has(firstSocket));
  await assert.rejects(udp.bind(signal, '127.0.0.1', 0, 32), error('EBADF'));
  assert.throws(() => udp.port(second), error('EBADF'));
  udp.close(second);
} finally {
  Socket.prototype.bindSync = bind;
  Socket.prototype.send = send;
  await udp.shutdown();
  clearTimeout(timeout);
}
console.log('UDP: datagrams, bounded queue, cancellation, late send completion and shutdown');
