// Host operations that complete later, by ticket. Snail-Core takes a
// ticket, starts the operation and returns at once, awaits the ticket, and
// then finishes it ((snail shell task)'s `through-host`). Starting and
// finishing are synchronous imports, so the only wait is on the ticket.
//
// `start` runs an operation with the starting task's AbortSignal. When it
// settles, its outcome waits under the ticket and the ticket is woken; a
// ticket that nothing awaits any more wakes nothing, and a success is
// disposed of then. So is one whose task is cancelled after the wake but
// before it finishes. `finish` delivers the outcome: it builds the managed
// result through the library's exposed helpers, synchronously, or throws a
// host failure into the Wasm that finishes it, where it traps.
export function createCompletions(wake) {
  const outcomes = new Map();
  // A woken outcome is disposed of if its task is cancelled first; the
  // listener goes when the outcome does, so a long-lived task keeps none.
  function settle(ticket, signal, outcome) {
    outcomes.set(ticket, outcome);
    if (!wake(ticket)) return take(ticket).dispose();
    outcome.cancel = () => take(ticket)?.dispose();
    outcome.signal = signal;
    signal.addEventListener('abort', outcome.cancel, {once: true});
  }
  function take(ticket) {
    const outcome = outcomes.get(ticket);
    outcomes.delete(ticket);
    outcome?.signal?.removeEventListener('abort', outcome.cancel);
    return outcome;
  }
  return {
    // `deliver` and `dispose` take the operation's value; a failure has
    // nothing to dispose of.
    start(ticket, signal, operation, deliver, dispose = () => {}) {
      let pending;
      try { pending = Promise.resolve(operation(signal)); }
      catch (error) { pending = Promise.reject(error); }
      pending.then(value => settle(ticket, signal, {deliver: () => deliver(value), dispose: () => dispose(value)}),
                   error => settle(ticket, signal, {deliver: () => { throw error; }, dispose: () => {}}));
    },
    finish(ticket) {
      const outcome = take(ticket);
      if (!outcome) throw new Error('a ticket was finished before its operation completed');
      return outcome.deliver();
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
