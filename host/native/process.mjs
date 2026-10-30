// Concrete Node child-process ownership, replacing the process, and the
// termination signals. Scalar handles never retain managed wrappers.
import {spawn as startChild, spawnSync} from 'node:child_process';
import {on, once} from 'node:events';
import {accessSync, constants, statSync} from 'node:fs';
import {join} from 'node:path';

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

// ---- Running a command to its end ----

// `run` blocks the calling thread until the child exits, so it serves a
// tool that runs once, never a service. The input is written whole, and
// both outputs are kept whole. A command that cannot start fails with the
// codes spawn gives.
export function runChild(directory, program, args, input) {
  let result;
  try { result = spawnSync(program, args, {cwd: directory, input, maxBuffer: Infinity}); }
  catch (error) { throw String(error.code).startsWith('ERR_') ? fault('EINVAL', error.message) : error; }
  if (result.error) throw result.error;
  return {code: result.status ?? -1, signal: result.signal ?? '', stdout: result.stdout, stderr: result.stderr};
}

// ---- Replacing the program ----

// `exec` replaces the process. The directory is the process's to change,
// and it changes back when the attempt fails, which answers its code.
// execve searches no PATH, so a program with no slash is found on PATH
// here, as spawn finds one.
export function replaceProcess(directory, program, args) {
  const home = process.cwd();
  try {
    process.chdir(directory);
    process.execve(executable(program), [program, ...args], process.env);
  } catch (error) {
    try { process.chdir(home); } catch {}
    return /^E[A-Z0-9]+$/.test(error.code) ? error.code : String(error.code).startsWith('ERR_') ? 'EINVAL' : 'EIO';
  }
}

function executable(program) {
  if (program.includes('/')) return program;
  for (const directory of (process.env.PATH ?? '').split(':')) {
    const path = join(directory || '.', program);
    try { accessSync(path, constants.X_OK); if (statSync(path).isFile()) return path; } catch {}
  }
  throw fault('ENOENT', `${program} is not on PATH`);
}

// ---- Termination ----

// SIGINT and SIGTERM, for the tasks waiting for them. A signal reaches
// every task waiting when it arrives, and each wait ends. One that finds
// no waiter while a delivered wait is still to be finished by its task
// arrived alongside that delivery, as a quick second Ctrl-C does, and it
// is kept for the next wait, at most one. The handlers are the process's
// only while a task waits or has such a wait to finish, so any other
// signal ends the process by Node's default at once, even while a turn
// computes and no handler could run.
const terminationNumbers = new Map([['SIGINT', 2], ['SIGTERM', 15]]);

export function createTermination() {
  const waiters = new Set();
  let held = null, unfinished = 0, listening = false;

  function listen(wanted = waiters.size > 0 || unfinished > 0) {
    if (wanted === listening) return;
    listening = wanted;
    for (const name of terminationNumbers.keys()) {
      if (wanted) process.on(name, arrive);
      else process.removeListener(name, arrive);
    }
  }

  function remove(waiter) {
    waiters.delete(waiter);
    waiter.signal.removeEventListener('abort', waiter.abort);
  }

  // A signal the handlers took after their last waiter left is raised
  // again, by the default once they are gone.
  function arrive(name) {
    const number = terminationNumbers.get(name);
    if (waiters.size) for (const waiter of [...waiters]) { remove(waiter); unfinished++; waiter.resolve(number); }
    else if (unfinished) held ??= number;
    else { listen(false); process.kill(process.pid, name); }
  }

  function wait(signal) {
    signal.throwIfAborted();
    if (held !== null) { const number = held; held = null; unfinished++; listen(); return Promise.resolve(number); }
    return new Promise((resolve, reject) => {
      const waiter = {signal, resolve, abort: () => { remove(waiter); listen(); reject(signal.reason); }};
      waiters.add(waiter);
      listen();
      signal.addEventListener('abort', waiter.abort, {once: true});
    });
  }

  // `settled` says a task finished, or dropped, a wait a signal ended.
  return {wait, settled() { unfinished--; listen(); }, close() { listen(false); }};
}
