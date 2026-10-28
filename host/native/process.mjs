// Concrete Node child-process ownership, and the termination signals the
// main thread forwards. Scalar handles never retain managed wrappers.
import {spawn as startChild} from 'node:child_process';
import {on, once} from 'node:events';

const chunkSize = 64 * 1024;
const fault = (code, message) => Object.assign(new Error(message), {code});
const closedError = () => fault('EBADF', 'process handle is closed');
// The numbers (snail shell process) gives Terminate, Kill and Interrupt.
const signalNames = new Map([[15, 'SIGTERM'], [9, 'SIGKILL'], [2, 'SIGINT']]);

// Node's event helpers wrap abort reasons. Preserve the task's exact reason so
// ordinary cancellation is not reported as a detached task failure.
function failure(resource, signal, error) {
  return signal.aborted ? signal.reason : resource.stop.signal.aborted ? resource.stop.signal.reason : error;
}

function settled(promise, signal) {
  signal.throwIfAborted();
  return new Promise((resolve, reject) => {
    const abort = () => reject(signal.reason);
    signal.addEventListener('abort', abort, {once: true});
    promise.then(value => { signal.removeEventListener('abort', abort); resolve(value); });
  });
}

// ---- Children ----

// Close revokes aliases and kills a running child now; shutdown waits for every exit.
export function createProcesses() {
  // Native ownership lasts from spawn until the child has exited and its
  // pipes have closed. A public handle exists only between a successful
  // spawn and close, which kills a child that is still running.
  const owned = new Set(), handles = new Map();
  let next = 1, stopped = false;

  function own(child) {
    const resource = {id: 0, child, stop: new AbortController(), exit: Promise.withResolvers(),
                      done: Promise.withResolvers(), reading: new Set(), writing: false};
    owned.add(resource);
    // A pipe's failure belongs to the operation that meets it; none may crash the host.
    for (const stream of [child, child.stdin, child.stdout, child.stderr]) stream.on('error', () => {});
    // When a child exits, Node discards output that no 'readable' listener
    // is waiting for. Listening keeps it paused in the pipe for `read`.
    for (const stream of [child.stdout, child.stderr]) stream.on('readable', () => {});
    child.once('exit', (code, signal) => resource.exit.resolve(signal ? {signal} : {code}));
    child.once('close', () => { owned.delete(resource); resource.done.resolve(); });
    return resource;
  }

  function publish(resource) {
    resource.stop.signal.throwIfAborted();
    if (next > 0x7fffffff) throw fault('EMFILE', 'process handle space exhausted');
    const id = next++;
    handles.set(id, resource);
    resource.id = id;
    return id;
  }

  function get(id) {
    const resource = handles.get(id);
    if (!resource) throw closedError();
    return resource;
  }

  function running(child) {
    return child.exitCode === null && child.signalCode === null;
  }

  function closeResource(resource, reason = closedError()) {
    if (resource.stop.signal.aborted) return;
    handles.delete(resource.id);
    resource.stop.abort(reason); // Wakes pending reads and waits with EBADF.
    if (running(resource.child)) resource.child.kill('SIGKILL');
    for (const stream of [resource.child.stdin, resource.child.stdout, resource.child.stderr]) stream.destroy();
  }

  // Node reports a missing executable or directory asynchronously, as an
  // error instead of `spawn`; an argument it cannot pass at all is EINVAL.
  async function spawn(signal, directory, program, args) {
    signal.throwIfAborted();
    if (stopped) throw closedError();
    let child;
    try { child = startChild(program, args, {cwd: directory, stdio: 'pipe'}); }
    catch (error) { throw String(error.code).startsWith('ERR_') ? fault('EINVAL', error.message) : error; }
    const resource = own(child), abort = () => closeResource(resource, signal.reason);
    signal.addEventListener('abort', abort, {once: true});
    try {
      await once(child, 'spawn', {signal: resource.stop.signal});
      return {handle: publish(resource), pid: child.pid};
    } catch (error) {
      closeResource(resource, error); await resource.done.promise;
      throw failure(resource, signal, error);
    } finally { signal.removeEventListener('abort', abort); }
  }

  // One pending read per stream; stdout and stderr may be read at once.
  // Cancelling a read consumes nothing, so it leaves the process usable.
  async function read(signal, id, descriptor, maximum) {
    signal.throwIfAborted();
    if (!Number.isInteger(maximum) || maximum <= 0 || maximum > chunkSize) throw fault('EINVAL', 'process read limit must be 1..65536');
    const resource = get(id), stream = [null, resource.child.stdout, resource.child.stderr][descriptor];
    if (!stream) throw fault('EINVAL', 'process output is stdout or stderr');
    if (resource.reading.has(descriptor)) throw fault('EBUSY', 'process read is already pending');
    resource.reading.add(descriptor);
    const wake = AbortSignal.any([signal, resource.stop.signal]);
    const notices = on(stream, 'readable', {signal: wake, close: ['end', 'close']});
    try {
      for (;;) {
        wake.throwIfAborted();
        stream.read(0); // Advance EOF even when the child wrote nothing.
        if (stream.readableLength) return stream.read(Math.min(maximum, stream.readableLength));
        if (stream.readableEnded) return null;
        if (stream.destroyed) throw closedError();
        await notices.next();
      }
    } catch (error) { throw failure(resource, signal, error); }
    finally { notices.return(); resource.reading.delete(descriptor); }
  }

  // Borrow immutable bytes until settlement; the Wasm adapter snapshots staging.
  // A write waits until the pipe takes the bytes, so a child that does not
  // read holds it; cancelling it closes the child's input.
  async function write(signal, id, bytes) {
    signal.throwIfAborted();
    if (!(bytes instanceof Uint8Array)) throw fault('EINVAL', 'process write requires bytes');
    const resource = get(id), input = resource.child.stdin;
    if (input.writableEnded || input.destroyed) throw fault('EPIPE', 'process input is closed');
    if (resource.writing) throw fault('EBUSY', 'process write is already pending');
    if (!bytes.length) return 0;
    resource.writing = true;
    const abort = () => input.destroy(signal.reason), count = Math.min(bytes.length, chunkSize);
    signal.addEventListener('abort', abort, {once: true});
    try {
      await new Promise((resolve, reject) => input.write(bytes.subarray(0, count), error => error ? reject(error) : resolve()));
      resource.stop.signal.throwIfAborted();
      return count;
    } catch (error) { throw failure(resource, signal, error); }
    finally { signal.removeEventListener('abort', abort); resource.writing = false; }
  }

  // Ending input lets written bytes drain, then gives the child EOF.
  function closeInput(id) {
    get(id).child.stdin.end();
  }

  function kill(id, number) {
    const resource = get(id), name = signalNames.get(number);
    if (!name) throw fault('EINVAL', 'process signal must be SIGTERM, SIGKILL or SIGINT');
    if (!running(resource.child) || !resource.child.kill(name)) throw fault('ESRCH', 'process has exited');
  }

  // Exit is an observation: any number of waits may be pending, and each
  // sees {code} or {signal}. Output may remain to be read after it.
  async function wait(signal, id) {
    const resource = get(id);
    try { return await settled(resource.exit.promise, AbortSignal.any([signal, resource.stop.signal])); }
    catch (error) { throw failure(resource, signal, error); }
  }

  async function shutdown() {
    stopped = true;
    while (owned.size) {
      const pending = [...owned];
      for (const resource of pending) closeResource(resource);
      await Promise.all(pending.map(resource => resource.done.promise));
    }
  }

  return {spawn, read, write, closeInput, kill, wait, shutdown,
    close(id) { const resource = handles.get(id); if (resource) closeResource(resource); }};
}

// ---- Termination ----

// SIGINT and SIGTERM, for the tasks waiting for them. The main thread owns
// the signal handlers (host/native/run-snail.mjs); when a signal arrives it
// reads `waiting`, shared memory holding the number of waiters, and forwards
// the signal here only if a task waits. The number is written before a wait
// suspends, so no signal can arrive in between and miss it. The second slot
// counts the deliveries that ended waits, and the main thread stamps each
// signal it forwards with the count it read.
const terminationNumbers = new Map([['SIGINT', 2], ['SIGTERM', 15]]);

export function createTermination(waiting) {
  const waiters = new Set();
  let held = null;
  const publish = () => Atomics.store(waiting, 0, waiters.size);

  function remove(waiter) {
    waiters.delete(waiter);
    publish();
    waiter.signal.removeEventListener('abort', waiter.abort);
  }

  function wait(signal) {
    signal.throwIfAborted();
    if (held !== null) { const number = held; held = null; return Promise.resolve(number); }
    return new Promise((resolve, reject) => {
      const waiter = {signal, resolve, abort: () => { remove(waiter); reject(signal.reason); }};
      waiters.add(waiter);
      publish();
      signal.addEventListener('abort', waiter.abort, {once: true});
    });
  }

  // A signal reaches every task waiting when it arrives, and each wait
  // ends: a second signal ends the process unless a task waits again. A
  // signal that finds no waiter here arrived while tasks waited, since the
  // main thread forwarded it. If a delivery has ended their wait since it
  // was stamped, it arrived alongside that delivery, as a quick second
  // Ctrl-C does, and it is kept for the next wait, at most one. Otherwise
  // its waiter was cancelled on the way, and it is raised again: the main
  // thread, seeing no waiter, ends the process by it.
  function deliver({name, deliveries}) {
    if (waiters.size) {
      for (const waiter of [...waiters]) { remove(waiter); waiter.resolve(terminationNumbers.get(name)); }
      Atomics.add(waiting, 1, 1);
    } else if (Atomics.load(waiting, 1) > deliveries) held ??= terminationNumbers.get(name);
    else process.kill(process.pid, name);
  }

  return {wait, deliver};
}
