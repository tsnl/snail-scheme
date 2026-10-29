// The host side of (snail shell task). The scheduler is Snail-Core's; a
// host drives it a turn at a time and completes the host operations its
// tasks wait on. A task takes a ticket, starts the operation through a
// synchronous import that returns at once, awaits the ticket, and then
// finishes it, through another, which takes the outcome the host kept
// (task.sld's `through-host`). No Wasm stack is ever suspended.

// The exports of the module holding (snail shell task), or null when the
// program does not link it and has no tasks to drive. A program is a
// per-library build, a loaded whole program, or its bare instance, as
// `programEntry` takes them.
export function taskExports(program) {
  const exports = program.names ? program.linked.get('snail.shell.task')?.exports
    : program.exports ?? program.runtime.exports;
  return exports?.['tasks:turn'] ? exports : null;
}

// One run of a program's tasks: its outstanding host operations and the
// loop that turns the scheduler. `exports` gives the scheduler's exports
// once the program is loaded. Closing aborts every outstanding operation
// and drops every task.
export function createTasks(exports, {reportError = () => {}} = {}) {
  const outcomes = new Map(), controller = new AbortController();
  let outstanding = 0, resting = null;

  // ---- Completions ----

  // A settled operation wakes its ticket. A ticket that wakes nothing, as
  // after closing, or after its task trapped, leaves its success to be
  // disposed of: an accepted connection is closed.
  function settle(ticket, outcome) {
    outstanding--;
    if (controller.signal.aborted || !wake(ticket)) return outcome.dispose();
    outcomes.set(ticket, outcome);
  }
  function wake(ticket) {
    const woke = exports()['tasks:wake'](BigInt(ticket)) !== 0;
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
    // Turns until no task is live, or `stopped` holds after a turn. A trap
    // ends only the task that ran (task.sld's `run-ready!`), so it is
    // reported with that task's id, and the turns go on. Every task waiting
    // on a ticket while no host operation is outstanding is a deadlock.
    async drive(stopped = () => false) {
      if (!exports()) return;
      for (;;) {
        let next;
        try { next = Number(exports()['tasks:turn'](BigInt(Date.now()))); }
        catch (error) {
          reportError(error, Number(exports()['tasks:running']()));
          next = 0;
        }
        if (next === -1 || stopped()) return;
        if (next === -2 && outstanding === 0) throw new Error('every task waits on a ticket that nothing will wake');
        await rest(next);
      }
    },
    // Wakes the loop from its rest, so that `stopped` is asked again.
    interrupt() { resting?.(); },
    close(reason) {
      controller.abort(reason);
      exports()?.['tasks:close']();
      for (const outcome of outcomes.values()) outcome.dispose();
      outcomes.clear();
      resting?.();
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
