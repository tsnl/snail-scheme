// One run target, one latest launch intent, one owned OS process. Build
// acceptance and Start/Restart policy belong to the project development owner.
import {spawn} from 'node:child_process';
import {join} from 'node:path';

const outputLimit = 64 * 1024;

function tail(previous, bytes) {
  if (bytes.length >= outputLimit) return Buffer.from(bytes.subarray(-outputLimit));
  const retained = previous.subarray(Math.max(0, previous.length + bytes.length - outputLimit));
  return Buffer.concat([retained, bytes]);
}

function phase(run) {
  if (run.finished) return run.error ? 'failed' : 'exited';
  if (run.stopping) return 'stopping';
  return run.child?.pid ? 'running' : 'starting';
}

export function applicationProcess({root, target, cwd = process.cwd()}) {
  const listeners = new Set();
  let desired = null, attempt = null, reconciling = null, closing = null;

  function status() {
    return {target, desired: desired && {build: desired.build}, attempt: attempt && {
      build: attempt.request.build, pid: attempt.child?.pid ?? null,
      phase: phase(attempt),
      code: attempt.child?.exitCode ?? null, signal: attempt.child?.signalCode ?? null,
      error: attempt.error, stdout: attempt.stdout.toString('utf8'), stderr: attempt.stderr.toString('utf8'),
    }};
  }

  // Observers may request or close synchronously, but must not throw. Obtain
  // current state for each observer so a nested report cannot be overwritten.
  function report() {
    for (const listener of listeners) listener(status());
  }

  function error(run, failure) {
    run.error ??= failure.message;
    report();
  }

  function signal(run, name) {
    if (run.finished || !run.child?.pid || run.child.exitCode !== null || run.child.signalCode !== null) return;
    // A false return also means the child already exited. Other delivery
    // failures arrive through the child's error event or throw here.
    try { run.child.kill(name); }
    catch (failure) { error(run, failure); }
  }

  function stop(run) {
    if (run.stopping) return run.stopping;
    if (run.finished) return run.done.promise;
    run.stopping = Promise.resolve().then(async () => {
      const timer = setTimeout(() => signal(run, 'SIGKILL'), 2000);
      try { signal(run, 'SIGTERM'); await run.done.promise; }
      finally { clearTimeout(timer); }
    });
    report();
    return run.stopping;
  }

  function launch(request) {
    const run = {request, child: null, finished: false, error: null, stopping: null,
      done: Promise.withResolvers(), stdout: Buffer.alloc(0), stderr: Buffer.alloc(0)};
    attempt = run; // Own the attempt even when spawning fails synchronously.
    try {
      run.child = spawn(process.execPath, ['--no-warnings', join(root, 'host/native/run-lofi.mjs'), request.entry, ...request.args],
        {cwd, stdio: ['ignore', 'pipe', 'pipe']});
    } catch (failure) {
      run.finished = true; run.done.resolve(); error(run, failure);
      return;
    }
    run.child.on('error', failure => error(run, failure));
    run.child.once('close', () => { run.finished = true; run.done.resolve(); report(); });
    for (const stream of ['stdout', 'stderr']) {
      run.child[stream].on('data', bytes => { run[stream] = tail(run[stream], bytes); report(); });
      run.child[stream].on('error', failure => { error(run, failure); void stop(run); });
    }
    report();
  }

  async function reconcile() {
    for (;;) {
      if (attempt && !attempt.finished && attempt.request !== desired) await stop(attempt);
      if (!desired || attempt?.request === desired) return; // A terminal matching attempt is not retried.
      launch(desired); // No await between observing intent and owning its child.
    }
  }

  function schedule() {
    if (reconciling) return;
    // Install ownership before callbacks can request another launch. A request
    // arriving between loop completion and promise cleanup still gets a turn.
    reconciling = Promise.resolve().then(reconcile).finally(() => {
      reconciling = null;
      if (desired ? attempt?.request !== desired : attempt && !attempt.finished) schedule();
    });
  }

  function request(next) {
    if (closing) throw new Error('application process owner is closed');
    desired = next === null ? null : {build: next.build, entry: next.entry, args: [...next.args]};
    schedule(); report();
  }

  function close() {
    if (closing) return closing;
    desired = null;
    // Intent stays null permanently. Await the owned child directly: a
    // reconciliation promise may already be handing off to its next turn.
    closing = Promise.resolve().then(async () => {
      if (attempt) await stop(attempt);
      listeners.clear();
    });
    report();
    return closing;
  }

  return {request, close, get status() { return status(); },
    subscribe(listener) {
      if (closing) throw new Error('application process owner is closed');
      listeners.add(listener); listener(status());
      return () => listeners.delete(listener);
    }};
}
