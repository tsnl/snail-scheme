// Applications own input and checkpoint handover; (snail shell task) owns
// tasks, the application's loop among them.
import {programEntry} from './entry.mjs';
import {byteSnapshot} from './load.mjs';
import {createTasks, taskExports} from './tasks.mjs';

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
    wait(signal) {
      if (signal?.aborted) return Promise.reject(signal.reason);
      if (events.length) return Promise.resolve();
      if (phase === 'closed') return Promise.reject(new Error('the application has stopped'));
      if (waiter) throw new Error('an application can have only one event waiter');
      waiter = Promise.withResolvers();
      const pending = waiter;
      function abort() {
        if (waiter === pending) waiter = null;
        pending.reject(signal.reason);
      }
      signal?.addEventListener('abort', abort, {once: true});
      return pending.promise.finally(() => signal?.removeEventListener('abort', abort));
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
    get waiting() { return waiter !== null; },
  };
}

// Both packaging modes describe the same entry: the application's exports
// and memory, the exports of (snail shell app), where the loop leaves its
// answer, and those of (snail shell task), which drive the loop.
export function applicationEntry(program) {
  const entry = programEntry(program, 'app_main');
  return {...entry, app: program.names ? program.linked.get('snail.shell.page').exports : entry.exports,
          tasks: taskExports(program)};
}

// Imports stay attached to the application: kept library instances retain
// these functions on relink. Async operations capture their invocation before
// awaiting.
export function createRuntime({size = () => [960, 640], seed = 1, load = async () => undefined,
                               store = async () => {}, frames = null, reportError = () => {}, warn = console.warn} = {}) {
  let current = null, stopping = null;
  const pending = [];
  // This scope starts exactly one loop, the root task, which owns the
  // application protocol. Other tasks must not consume its input or replace
  // checkpoint bytes while its storage operation is outstanding.
  function applicationRun() {
    if (!current || Number(current.entry.tasks['tasks:running']()) !== current.loop) {
      throw new Error('application events and checkpoint storage belong to the root task');
    }
    return current;
  }
  const imports = {
    'snail.runtime.browser.events': {
      poll() {
        const run = applicationRun();
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
      // Waiting for an event is a ticket the queue's next push completes.
      'start-wait'(ticket) {
        const run = applicationRun();
        run.tasks.start(Number(ticket), signal => run.queue.wait(signal), () => 0);
      },
      'finish-wait': ticket => applicationRun().tasks.finish(Number(ticket)),
      field: index => applicationRun().event[index + 1] ?? 0,
      seed: () => seed,
      width: () => size()[0],
      height: () => size()[1],
      boot: kind => { applicationRun().boot = kind; },
    },
    'snail.runtime.browser.storage': {
      'start-load'(ticket) {
        const run = applicationRun();
        run.tasks.start(Number(ticket), async signal => {
          run.loaded = run.restore === undefined ? await load(signal) : run.restore;
          return run.loaded == null ? -1 : run.loaded.length;
        }, count => count);
      },
      'finish-load': ticket => applicationRun().tasks.finish(Number(ticket)),
      byte: index => applicationRun().loaded[index],
      'start-store'(ticket, address) {
        const run = applicationRun(), bytes = byteSnapshot(run.entry.memory, address);
        run.saved = bytes;
        run.tasks.start(Number(ticket), async signal => {
          try { await store(bytes, signal); }
          catch (error) { if (!signal.aborted) warn(`save failed: ${error.message}`); }
        }, () => 0);
      },
      'finish-store': ticket => applicationRun().tasks.finish(Number(ticket)),
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
  // A trap in the loop ends the run, keeping its last checkpoint; a trap in
  // another task ends only that task.
  function trapped(run, error, task) {
    if (task !== run.loop) reportError(error);
    else run.failure ??= error instanceof Error ? error : new Error('application failed', {cause: error});
  }
  // The loop's answer: the state it handed over, or none when it could not
  // boot.
  function answer(run) {
    if (run.failure) return {state: null, error: run.failure};
    if (run.entry.app.app_outcome() === 0) return {state: null, error: new Error('the application loop stopped without answering')};
    return {state: run.entry.app.app_handover(), error: null};
  }
  function start(entry, handover = null, {restore, transfer = false} = {}) {
    if (current && !current.queue.closed) throw new Error('application entries must not overlap');
    if (!transfer) stopping = null;
    const ready = Promise.withResolvers(), queue = createEventQueue(transfer ? null : frames);
    const run = {entry, ready, queue, restore, tasks: null, accepted: false, saved: null, loaded: null,
                 event: null, boot: null, loop: null, failure: null, root: null, done: null};
    run.tasks = createTasks(() => entry.tasks, {reportError: (error, task) => trapped(run, error, task)});
    ready.promise.catch(() => {});
    current = run;
    if (transfer) queue.reload();
    else { queue.push(RESIZE, ...size()); queue.push(FRAME, 0); }
    // `app_main` dispatches the loop and answers its task; the turns run it.
    run.loop = Number(entry.main(handover));
    const answered = () => run.failure !== null || entry.app.app_outcome() !== 0;
    run.root = run.tasks.drive(answered).then(() => answer(run), error => ({state: null, error}));
    run.done = run.root.then(async result => {
      // After the sole event consumer returns, an unpresented application
      // can never become ready. Its children cannot complete startup for it.
      if (result.error || !run.accepted) run.tasks.close();
      else await run.tasks.drive().catch(reportError);
      const state = result.error ? (run.boot === null ? handover : entry.exports.app_state()) : result.state;
      return finish(run, state, result.error);
    });
    return run;
  }
  async function stopRun(run) {
    run.queue.reload();
    await run.root; // The application saves its checkpoint before teardown.
    run.tasks.close();
    return run.done;
  }
  async function stopCurrent() {
    let run = current;
    let result = await stopRun(run);
    if (result.error && result.state !== null) {
      // Transfer the checkpoint through old code without replaying the event
      // or view that trapped. Reload is the first event in this invocation.
      run = start(run.entry, result.state, {transfer: true});
      result = await stopRun(run);
    }
    return {state: result.state, saved: run.saved, error: result.error};
  }
  function stop() { return stopping ??= stopCurrent(); }
  function send(...event) {
    if (!current?.accepted || !current.queue.push(...event)) pending.push(event);
  }
  return {imports, start, stop, send,
          get execution() { return current; }};
}
