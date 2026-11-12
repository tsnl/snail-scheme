// The host side of (snail shell task). The scheduler is Snail-Core's; a
// host drives it a turn at a time and completes the host operations its
// tasks wait on. A task takes a ticket, starts the operation through a
// synchronous import that returns at once, awaits the ticket, and then
// finishes it, through another, which takes the outcome the host kept
// (task.sld's `through-host`). No Wasm stack is ever suspended.

// The exports of the module holding (snail shell task), or null when the
// program does not link it and has no tasks to drive. A program is a
// per-library build, a loaded whole program, or its bare instance, as
// `programEntry` takes them. An engine ((snail shell engine)) runs tasks
// of its own beside the program's, and drives the two as one scheduler
// through its `engine:` exports, which this names as (snail shell task)
// does.
export function taskExports(program) {
  const exports = program.names ? program.linked.get('snail.shell.task')?.exports
    : program.exports ?? program.runtime.exports;
  if (exports?.['engine:turn']) return engineTasks(exports);
  return exports?.['tasks:turn'] ? exports : null;
}

const engineTasks = exports => ({
  ...exports,
  'tasks:dispose': exports['engine:close'],
  'tasks:create': exports['engine:create'], 'tasks:create:release-result': exports['engine:create:release-result'],
  'tasks:turn': exports['engine:turn'], 'tasks:wake': exports['engine:wake'], 'tasks:close': exports['engine:close-tasks'],
  'tasks:running': exports['engine:running'], 'tasks:live': exports['engine:live'],
});

// One run of a program's tasks: its outstanding host operations and the
// loop that turns the scheduler. `exports` gives the scheduler's exports
// once the program is loaded. Closing aborts every outstanding operation
// and drops every task.
export function createTasks(exports, {reportError = () => {}} = {}) {
  const outcomes = new Map(), controller = new AbortController();
  let outstanding = 0, resting = null, scheduler = null, owner = null, active = 0, closed = false, disposing = false, closeStatus = 0;
  const settled = [];

  // The run owns one returned credit. Each Wasm entry retains its arguments;
  // release consumes only this host credit, after queued work has closed.
  function context() {
    if (!scheduler) {
      scheduler = exports();
      if (scheduler) owner = scheduler['tasks:create']();
    }
    return scheduler;
  }
  function enter(name, ...args) {
    if (closed && !(disposing && typeof name === 'string' && name.startsWith('resource:'))) throw new Error('the task scheduler has closed');
    const api = context();
    if (!api) return null;
    active++;
    try { return (typeof name === 'function' ? name : api[name])(owner, ...args); }
    finally {
      active--;
      if (!active && !disposing) {
        if (closed) release();
        else while (settled.length) settle(...settled.shift());
      }
    }
  }
  function release() {
    if (owner === null) return;
    const value = owner;
    disposing = true;
    try {
      scheduler['tasks:close'](value);
      closeStatus = Number(scheduler['tasks:dispose']?.(value) ?? 0);
    } finally {
      owner = null; // Consume the credit before invoking its release companion.
      try { scheduler['tasks:create:release-result'](value); }
      finally { disposing = false; }
    }
  }

  // ---- Completions ----

  // A settled operation wakes its ticket. A ticket that wakes nothing, as
  // after closing, or after its task trapped, leaves its success to be
  // disposed of: an accepted connection is closed.
  function settle(ticket, outcome) {
    if (active) { settled.push([ticket, outcome]); return; }
    outstanding--;
    if (closed || !wake(ticket)) return outcome.dispose();
    outcomes.set(ticket, outcome);
  }
  function wake(ticket) {
    const woke = enter('tasks:wake', BigInt(ticket)) !== 0;
    if (woke) resting?.();
    return woke;
  }

  // ---- Turns ----

  // Between turns the host runs its own work: at once when a task is
  // ready, and otherwise until a wake or the earliest deadline.
  function rest(next) {
    if (next === 0) return nextMacrotask();
    return new Promise(resolve => {
      const timer = next > 0 ? setTimeout(() => resting(), next) : null;
      resting = () => { clearTimeout(timer); resting = null; resolve(); };
    });
  }

  return {
    signal: controller.signal,
    call: enter,
    get closeStatus() { return closeStatus; },
    get owner() { if (closed) throw new Error('the task scheduler has closed'); context(); return owner; },
    startMain(body) { enter('tasks:start-main', body); },
    running() { return owner === null ? 0 : Number(scheduler['tasks:running'](owner)); },
    live() { return owner === null ? 0 : Number(scheduler['tasks:live'](owner)); },
    // Runs `operation` with the run's AbortSignal. `deliver` builds the
    // managed result from its value when the task finishes the ticket,
    // and `dispose` releases a value that no task finished.
    start(ticket, operation, deliver, dispose = () => {}) {
      outstanding++;
      let pending;
      try { pending = Promise.resolve(operation(controller.signal)); }
      catch (error) { pending = Promise.reject(error); }
      pending.then(value => settle(ticket, {deliver: () => deliver(value), dispose: () => dispose(value)}),
                   error => settle(ticket, {deliver: () => { throw error; }, dispose: () => {}}));
    },
    // A host failure throws into the Wasm that finishes it, where it traps
    // the task.
    finish(ticket) {
      const outcome = outcomes.get(ticket);
      if (!outcome) throw new Error('a ticket was finished before its operation completed');
      outcomes.delete(ticket);
      return outcome.deliver();
    },
    // A dropped operation token may own an already-ready result whose task
    // was canceled before delivery. Pending work is disposed by settle when
    // its ticket no longer wakes a continuation.
    discard(ticket) {
      const outcome = outcomes.get(ticket);
      if (outcome) { outcomes.delete(ticket); outcome.dispose(); }
    },
    // Turns until no task is live or the caller stops. A trap is terminal:
    // Wasm does not unwind source ownership. Close reachable queued work,
    // but never pretend to recover owners stranded in a trapped frame.
    async drive(stopped = () => false) {
      if (closed || !context()) return;
      for (;;) {
        if (closed) return;
        let next;
        try { next = Number(enter('tasks:turn', BigInt(Date.now()))); }
        catch (error) {
          reportError(error, owner === null ? 0 : Number(scheduler['tasks:running'](owner)));
          this.close(error);
          return;
        }
        if (next === -1 || stopped()) return;
        if (next === -2 && outstanding === 0) throw new Error('every task waits on a ticket that nothing will wake');
        await rest(next);
      }
    },
    // Wakes the loop from its rest, so that `stopped` is asked again.
    interrupt() { resting?.(); },
    close(reason) {
      if (closed) return;
      closed = true;
      controller.abort(reason);
      let failure;
      try { if (!active) release(); } catch (error) { failure = error; }
      // A source finalizer may trap. Host results still belong to this run
      // and must be disposed even when releasing the scheduler failed.
      outstanding -= settled.length;
      const abandoned = [...settled.splice(0).map(([, outcome]) => outcome), ...outcomes.values()];
      outcomes.clear();
      for (const outcome of abandoned) {
        try { outcome.dispose(); } catch (error) { failure ??= error; }
      }
      resting?.();
      if (failure) throw failure;
    },
  };
}

// A native operation's coded failure, such as ECONNRESET, is a value: the
// operation's Err result. A cancellation, or a failure without a code,
// stays a failure, which traps the finish.
export function coded(operation) {
  return async signal => {
    try { return {value: await operation(signal)}; }
    catch (error) {
      signal.throwIfAborted();
      if (!(error instanceof Error) || typeof error.code !== 'string' || !/^[A-Z][A-Z0-9_]*$/.test(error.code)) throw error;
      return {code: error.code};
    }
  };
}

// A turn of the event loop, not only a microtask, so the host's own events
// run between turns: setImmediate in Node, a message in a browser, whose
// zero timeouts are clamped.
function nextMacrotask() {
  if (typeof setImmediate === 'function') return new Promise(resolve => setImmediate(resolve));
  return new Promise(resolve => {
    const channel = new MessageChannel();
    channel.port1.onmessage = () => { channel.port1.close(); resolve(); };
    channel.port2.postMessage(null);
  });
}
