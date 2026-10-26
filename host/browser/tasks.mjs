// One execution permit protects the Wasm globals holding dynamic handlers.
// A parked JSPI invocation stays live until its operation, cleanup and unwind
// finish. Only the scheduler releases its resumption Promise.
// The host's reporting hook must not throw. One scheduler owns each program.
export function createScheduler({handlerGlobals = () => [], reportError = () => {}} = {}) {
  const live = new Set(), ready = [], baseline = new Map(), drains = [];
  let active = null, scheduled = false, closed = false, steps = 0;

  // Dynamically loaded modules may introduce handler globals. The compiler
  // initializes each to null; new globals observed during an invocation must
  // not make that invocation's installed handler the runtime default.
  function discover() {
    for (const global of handlerGlobals()) if (!baseline.has(global)) baseline.set(global, active ? null : global.value);
  }
  function snapshot() {
    discover();
    return new Map([...baseline.keys()].map(global => [global, global.value]));
  }
  function install(bindings) {
    discover();
    for (const [global, fallback] of baseline) global.value = bindings.has(global) ? bindings.get(global) : fallback;
  }
  function schedule() {
    if (scheduled || active || !ready.length) return;
    scheduled = true;
    // Bound the microtask chain: many short tasks must still service input.
    if (++steps < 64) queueMicrotask(pump);
    else setTimeout(() => { steps = 0; pump(); }, 0);
  }
  function enqueue(task, next) {
    task.next = next;
    ready.push(task);
    schedule();
  }
  function release(task) {
    if (active !== task) return;
    install(baseline);
    active = null;
    schedule();
  }
  function pump() {
    scheduled = false;
    if (active) return;
    let task;
    while ((task = ready.shift()) && !live.has(task)) {}
    if (!task) return;
    active = task;
    install(task.bindings);
    const next = task.next;
    task.next = null;
    try { next(); }
    catch (error) { finish(task, false, error); }
  }
  function finish(task, ok, result) {
    if (!live.delete(task)) return;
    release(task);
    task.bindings.clear();
    task.work = task.discard = task.next = null;
    if (ok && task.controller.signal.aborted) { ok = false; result = task.controller.signal.reason; }
    if (ok) task.completion.resolve(result);
    else task.completion.reject(result);
    if (!live.size) for (const resolve of drains.splice(0)) resolve();
    schedule();
    if (!ok && task.detached && (!task.controller.signal.aborted || result !== task.controller.signal.reason)) reportError(result);
  }
  function cancel(task, reason = new DOMException('task cancelled', 'AbortError')) {
    if (!live.has(task) || task.controller.signal.aborted) return;
    task.controller.abort(reason);
    // A queued resumption still owns a Wasm invocation and must unwind.
    // Only work that has never entered Wasm can settle without resuming.
    if (task.work !== null) {
      let failure = reason;
      try { task.discard?.(); }
      catch (error) { failure = error; }
      finish(task, false, failure);
    }
  }
  function spawn(work, discard, detached) {
    if (closed) throw new Error('the task runtime has closed');
    discover();
    const task = {work, discard, detached, bindings: detached && active ? snapshot() : new Map(baseline), controller: new AbortController(),
                  completion: Promise.withResolvers(), next: null};
    task.completion.promise.catch(() => {});
    live.add(task); // Reserve before the dispatching task can return.
    enqueue(task, () => {
      const work = task.work;
      task.work = task.discard = null;
      Promise.resolve(work()).then(value => finish(task, true, value), error => finish(task, false, error));
    });
    return {done: task.completion.promise, cancel: reason => cancel(task, reason)};
  }

  // The operation owns its abort listener and settles only after cleanup.
  // An operation that cannot abort may finish normally; cancellation still
  // rejects the gate. A broken adapter that never settles prevents drain.
  // Work returns its complete invocation Promise: a parked task cannot finish
  // or enter another wait before this gate settles. No wait identity is needed.
  // Successful results belong to the gate until delivery. Discard is native,
  // synchronous cleanup and must not reenter Wasm.
  function suspend(operation, discard = null) {
    const task = active;
    if (!task) throw new Error('a runtime wait requires a running task');
    task.controller.signal.throwIfAborted();
    const gate = Promise.withResolvers();
    let pending;
    try { pending = operation(task.controller.signal); }
    catch (error) { pending = Promise.reject(error); }
    task.bindings = snapshot();
    release(task);
    function completed(ok, result) {
      enqueue(task, () => {
        // Cancellation can race with an already queued successful result.
        if (!ok) gate.reject(result);
        else if (task.controller.signal.aborted) {
          try { discard?.(result); gate.reject(task.controller.signal.reason); }
          catch (error) { gate.reject(error); } // Reject the parked stack so it still unwinds.
        } else gate.resolve(result);
        // Keep the permit until JSPI next suspends or its export settles.
      });
    }
    Promise.resolve(pending).then(value => completed(true, value), error => completed(false, error));
    return gate.promise;
  }
  function drain() {
    return live.size ? new Promise(resolve => drains.push(resolve)) : Promise.resolve();
  }
  return {
    start: work => spawn(work, null, false),
    dispatch: (work, discard = null) => spawn(work, discard, true),
    suspend,
    drain,
    close(reason) {
      closed = true;
      for (const task of live) cancel(task, reason);
      return drain();
    },
    get size() { return live.size; },
    get inRoot() { return active !== null && !active.detached; },
  };
}

// Timers own their registration until normal completion or cancellation.
// Even a zero-duration sleep yields an event-loop turn, not just a microtask.
export function delay(signal, milliseconds = 0) {
  signal.throwIfAborted();
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { signal.removeEventListener('abort', abort); resolve(); }, milliseconds);
    function abort() {
      clearTimeout(timer);
      signal.removeEventListener('abort', abort);
      reject(signal.reason);
    }
    signal.addEventListener('abort', abort, {once: true});
  });
}

// Imports can survive a reload. The adapter supplies the current runtime;
// once a call starts, its task and AbortSignal belong to that invocation.
export function taskImports(scheduler) {
  return {
    dispatch(run, drop, owner) {
      scheduler().dispatch(() => WebAssembly.promising(run)(owner), () => drop(owner));
    },
    yield: new WebAssembly.Suspending(() => scheduler().suspend(signal => delay(signal))),
    sleep: new WebAssembly.Suspending(milliseconds => scheduler().suspend(signal => {
      if (milliseconds < 0n || milliseconds > 2147483647n) throw new RangeError('sleep expects 0..2147483647 milliseconds');
      return delay(signal, Number(milliseconds));
    })),
  };
}
