// One JSPI invocation owns its queue and waits; its application owns resources.
import {programEntry, runEntry, byteSnapshot} from './actors.mjs';

export const FRAME = 11, HIDDEN = 12, RELOAD = 13;
const MOVE = 4, RESIZE = 8;

// A queue has one frame scheduled or queued. Only consuming a frame permits
// another RAF; a slow application cannot accumulate a backlog of clock ticks.
export function createEventQueue(frames = null) {
  const events = [];
  let phase = 'open', waiter = null, ticket = null, last = null;
  const wake = () => { waiter?.resolve(); waiter = null; };
  function schedule() {
    if (!frames || phase !== 'open' || ticket !== null) return;
    if (last === null) last = performance.now();
    ticket = frames.request(now => {
      ticket = null;
      push(FRAME, Math.round(Math.min(250, Math.max(0, now - last))));
      last = now;
    });
  }
  function push(kind, ...fields) {
    if (phase !== 'open') return false;
    const event = [kind, ...fields];
    const previous = events.at(-1);
    if ((kind === RESIZE && previous?.[0] === RESIZE) ||
        (kind === MOVE && previous?.[0] === MOVE && previous[1] === fields[0])) events[events.length - 1] = event;
    else if (kind !== FRAME || !events.some(event => event[0] === FRAME)) events.push(event);
    wake();
    return true;
  }
  return {
    push,
    poll() { const event = events.shift(); if (event?.[0] === FRAME) schedule(); return event; },
    wait() {
      if (events.length) return Promise.resolve();
      if (phase === 'closed') return Promise.reject(new Error('the application has stopped'));
      if (waiter) throw new Error('an application can have only one event waiter');
      waiter = Promise.withResolvers();
      return waiter.promise;
    },
    reload() {
      if (phase !== 'open') return;
      phase = 'reload';
      if (ticket !== null) frames.cancel(ticket);
      ticket = null;
      events.push([RELOAD]);
      wake();
    },
    close() {
      phase = 'closed';
      if (ticket !== null) frames.cancel(ticket);
      ticket = null;
      const unread = events.splice(0).filter(([kind]) => kind !== FRAME && kind !== RELOAD);
      waiter?.reject(new Error('the application has stopped'));
      waiter = null;
      return unread;
    },
    get closed() { return phase === 'closed'; },
  };
}

// Both packaging modes describe the same entry, memory, and dynamic handlers.
export function applicationEntry(program) {
  return programEntry(program, 'app_main');
}

// Imports stay attached to the application: kept library instances retain
// these functions on relink. Async operations capture their invocation before
// awaiting. Exactly one entry runs at once, so handler globals can be restored
// after settlement without changing another suspended invocation's handlers.
export function createRuntime({size = () => [960, 640], seed = 1, load = async () => undefined,
                               store = async () => {}, frames = null, reportError = () => {}, warn = console.warn} = {}) {
  let current = null;
  const pending = [];
  const imports = {
    'snail.events': {
      poll() {
        const run = current;
        if (!run.accepted && run.event?.[0] === FRAME) {
          // Returning to poll acknowledges successful initial presentation.
          // Hold transition input until that boundary, even during storage.
          run.accepted = true;
          run.ready.resolve(run.boot);
          while (pending.length && run.queue.push(...pending[0])) pending.shift();
        }
        const event = run.queue.poll();
        if (!event) return 0;
        run.event = event;
        return event[0];
      },
      wait: new WebAssembly.Suspending(() => current.queue.wait()),
      field: index => current.event[index + 1] ?? 0,
      seed: () => seed,
      width: () => size()[0],
      height: () => size()[1],
      boot: kind => { current.boot = kind; },
    },
    'snail.storage': {
      load: new WebAssembly.Suspending(async () => {
        const run = current;
        run.loaded = run.restore === undefined ? await load() : run.restore;
        return run.loaded == null ? -1 : run.loaded.length;
      }),
      byte: index => current.loaded[index],
      store: new WebAssembly.Suspending(async address => {
        const run = current, bytes = byteSnapshot(run.entry.memory, address);
        run.saved = bytes;
        try { await store(bytes); }
        catch (error) { warn(`save failed: ${error.message}`); }
      }),
    },
  };
  function finish(run, state, error) {
    const unread = run.queue.close();
    if (run.accepted) pending.unshift(...unread);
    if (error) {
      run.ready.reject(error);
      if (run.accepted) reportError(error);
    } else if (!run.accepted) run.ready.reject(new Error(run.boot === null ?
      'the new program could not take over the running state' : 'the application stopped before startup completed'));
    return {state, error};
  }
  function start(entry, handover = null, {restore, transfer = false} = {}) {
    if (current && !current.queue.closed) throw new Error('application entries must not overlap');
    const ready = Promise.withResolvers(), queue = createEventQueue(transfer ? null : frames);
    const run = {entry, ready, queue, restore, accepted: false, saved: null, loaded: null, event: null, boot: null, done: null};
    ready.promise.catch(() => {});
    current = run;
    if (transfer) queue.push(RELOAD);
    else { queue.push(RESIZE, ...size()); queue.push(FRAME, 0); }
    // Deferring the call also turns a synchronous ABI error into settlement.
    run.done = Promise.resolve().then(() => runEntry(entry, handover)).then(
      state => finish(run, state, null),
      error => finish(run, run.boot === null ? handover : entry.exports.app_state(), error));
    return run;
  }
  async function stop() {
    let run = current;
    run.queue.reload();
    let result = await run.done;
    if (result.error && result.state !== null) {
      // Transfer the checkpoint through old code without replaying the event
      // or view that trapped. Reload is the first event in this invocation.
      run = start(run.entry, result.state, {transfer: true});
      result = await run.done;
    }
    return {state: result.state, saved: run.saved, error: result.error};
  }
  function send(...event) {
    if (!current?.accepted || !current.queue.push(...event)) pending.push(event);
  }
  return {imports, start, stop, send,
          get execution() { return current; }};
}
