// A page's program is a script: the host calls its start with a scheduler,
// whose first task runs the script's main with what (snail target browser)
// provides, and drives the scheduler. This file holds the page's event
// queue and its one save; (snail shell task) owns the tasks.
import {programEntry} from './entry.mjs';
import {byteSnapshot} from './load.mjs';
import {createTasks, taskExports} from './tasks.mjs';

export const FRAME = 11, HIDDEN = 12, SAVE = 16;
const MOVE = 4, RESIZE = 8, POINTER_DELTA = 18;

// A queue has one frame scheduled or queued. Only consuming a frame permits
// another RAF; a slow application cannot accumulate a backlog of clock ticks.
export function createEventQueue(frames = null) {
  const events = [];
  let open = true, waiter = null, ticket = null, last = null;
  const wake = () => { waiter?.resolve(); waiter = null; };
  function schedule() {
    if (!frames || !open || ticket !== null) return;
    if (last === null) last = Math.round(performance.now());
    ticket = frames.request(now => {
      ticket = null;
      // Difference the rounded timestamps so fractional refresh intervals add up.
      const stamp = Math.round(now);
      push(FRAME, Math.min(250, Math.max(0, stamp - last)));
      last = stamp;
    });
  }
  function push(kind, ...fields) {
    if (!open) return false;
    const event = [kind, ...fields];
    const previous = events.at(-1);
    if (kind === POINTER_DELTA && previous?.[0] === POINTER_DELTA) {
      previous[1] += fields[0]; previous[2] += fields[1];
    } else if ((kind === RESIZE && previous?.[0] === RESIZE) ||
        (kind === MOVE && previous?.[0] === MOVE && previous[1] === fields[0])) events[events.length - 1] = event;
    else if (kind !== FRAME || !events.some(event => event[0] === FRAME)) events.push(event);
    wake();
    return true;
  }
  return {
    push,
    poll() { const event = events.shift(); if (event?.[0] === FRAME) schedule(); return event; },
    wait(signal) {
      if (signal?.aborted) return Promise.reject(signal.reason);
      if (events.length) return Promise.resolve();
      if (!open) return Promise.reject(new Error('the application has stopped'));
      if (waiter) throw new Error('an application can have only one event waiter');
      waiter = Promise.withResolvers();
      const pending = waiter;
      if (!signal) return pending.promise;
      function abort() {
        if (waiter === pending) waiter = null;
        pending.reject(signal.reason);
      }
      signal.addEventListener('abort', abort, {once: true});
      return pending.promise.finally(() => signal.removeEventListener('abort', abort));
    },
    close() {
      open = false;
      if (ticket !== null) frames.cancel(ticket);
      ticket = null;
      events.length = 0;
      waiter?.reject(new Error('the application has stopped'));
      waiter = null;
    },
    get closed() { return !open; },
    get waiting() { return waiter !== null; },
  };
}

// Both packaging modes describe the same entry: the program's main and
// memory, and the exports of (snail shell task), which drive its tasks.
export function applicationEntry(program) {
  return {...programEntry(program), tasks: taskExports(program)};
}

// Imports stay attached to the application. Async operations capture their
// run before awaiting.
export function createRuntime({size = () => [960, 640], seed = 1, load = async () => undefined,
                               store = async () => {}, frames = null, initial = () => [[RESIZE, ...size()], [FRAME, 0]], reportError = () => {}, warn = console.warn} = {}) {
  let current = null;
  const pending = [];
  const run = () => {
    if (!current || current.queue.closed) throw new Error('the application has stopped');
    return current;
  };
  const imports = {
    'snail.runtime.browser.events': {
      poll() {
        const event = run().queue.poll();
        if (!event) return 0;
        current.event = event;
        return event[0];
      },
      // Waiting for an event is a ticket the queue's next push completes.
      'start-wait'(ticket) {
        const {tasks, queue} = run();
        // finish() closes this run's queue and rejects its pending wait.
        tasks.start(Number(ticket), () => queue.wait(), () => 0);
      },
      'finish-wait': ticket => run().tasks.finish(Number(ticket)),
      field: index => run().event[index + 1] ?? 0,
      seed: () => seed,
      width: () => size()[0],
      height: () => size()[1],
      boot(kind) {
        const current = run();
        current.boot = kind;
        saveLater(current);
      },
      // The first frame shown: startup is complete, and input sent before
      // it is delivered.
      ready() {
        const current = run();
        if (current.accepted) return;
        current.accepted = true;
        current.ready.resolve(current.boot);
        while (pending.length && current.queue.push(...pending[0])) pending.shift();
      },
    },
    'snail.runtime.browser.storage': {
      'start-load'(ticket) {
        const current = run();
        current.tasks.start(Number(ticket), async signal => {
          current.loaded = current.fresh ? null : await load(signal);
          return current.loaded == null ? -1 : current.loaded.length;
        }, count => count);
      },
      'finish-load': ticket => run().tasks.finish(Number(ticket)),
      byte: index => run().loaded[index],
      'start-store'(ticket, address) {
        const current = run(), bytes = byteSnapshot(current.entry.memory, address);
        saveLater(current);
        current.tasks.start(Number(ticket), async signal => {
          try {
            await store(bytes, signal);
            current.saved = bytes;
            return 1;
          } catch (error) {
            if (!signal.aborted) warn(`save failed: ${error.message}`);
            return 0;
          }
        }, stored => stored);
      },
      'finish-store': ticket => run().tasks.finish(Number(ticket)),
    },
  };
  // run-page reports a boot when it takes charge of automatic checkpoints.
  // A game that manages its own save slot can use storage without a timer.
  function saveLater(run) {
    if (run.boot === null) return;
    clearTimeout(run.saveTimer);
    run.saveTimer = setTimeout(() => run.queue.push(SAVE), 5000);
  }
  // Wasm traps do not unwind a trapped frame, so a trap in any task ends
  // the run; the page keeps its last save.
  function finish(run, error) {
    clearTimeout(run.saveTimer);
    run.queue.close();
    try { run.tasks.close(); } catch (failure) { error ??= failure; }
    if (error) {
      run.ready.reject(error);
      if (run.accepted) reportError(error);
    } else if (!run.accepted) run.ready.reject(new Error('the application stopped before startup completed'));
    return {error};
  }
  // A fresh run boots without the stored save.
  function start(entry, {fresh = false} = {}) {
    if (current && !current.queue.closed) throw new Error('application runs must not overlap');
    const ready = Promise.withResolvers(), queue = createEventQueue(frames);
    const started = {entry, ready, queue, fresh, tasks: null, accepted: false, saved: null, loaded: null,
                     event: null, boot: null, failure: null, done: null, saveTimer: null};
    started.tasks = createTasks(() => entry.tasks, {reportError: error => { started.failure ??= error; }});
    ready.promise.catch(() => {});
    current = started;
    for (const event of initial()) queue.push(...event);
    let driven;
    try {
      started.tasks.call(entry.main);
      driven = started.tasks.drive().then(() => started.failure, error => error);
    } catch (error) { driven = Promise.resolve(error); }
    started.done = driven.then(error => finish(started, error));
    return started;
  }
  // Ends the run, as leaving the page does: its tasks are discarded, its
  // drive returns and finishes it, and its save stays as it was last stored.
  function close() {
    current?.tasks.close();
  }
  function send(...event) {
    if (!current?.accepted || !current.queue.push(...event)) pending.push(event);
  }
  return {imports, start, close, send,
          get execution() { return current; }};
}
