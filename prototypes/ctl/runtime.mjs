// Experimental single-shot handlers. This host owns one program invocation
// and every suspension beneath it. It does not integrate with the actor host.
// A task is one physical JSPI stack; an answer is one suspended caller.

const owned = new WeakSet();
class Abandoned extends Error {
  constructor() { super('the handled continuation was abandoned'); }
}

export function createControlHost() {
  const tasks = new Set(), frames = new Map(), continuations = new Set(), queue = [];
  let globals = [], baseline = [], active = null, running = false, queued = false;

  // ---- Stack scheduling ----

  const snapshot = () => globals.map(global => global.value);
  const restore = context => globals.forEach((global, index) => { global.value = context[index]; });

  function enqueue(task, action) {
    queue.push({task, action});
    pump();
  }

  function pump() {
    if (active || queued || !queue.length) return;
    queued = true;
    queueMicrotask(() => {
      queued = false;
      if (active) return;
      const {task, action} = queue.shift();
      active = task;
      restore(task.context);
      action();
    });
  }

  function release(task) {
    if (active !== task) throw new Error('a stack relinquished another stack\'s execution lease');
    task.context = snapshot();
    active = null;
    restore(baseline);
    pump();
  }

  function start(parent, context, code, args, completed) {
    const task = {parent, context: context.slice(), wait: null, cancelled: null, done: Promise.withResolvers()};
    tasks.add(task);
    enqueue(task, () => {
      if (task.cancelled) { finish(task, undefined, task.cancelled, completed); return; }
      WebAssembly.promising(code)(...args).then(
        value => finish(task, value, null, completed), error => finish(task, undefined, error, completed));
    });
    return task;
  }

  function finish(task, value, error, completed) {
    release(task);
    Promise.resolve(completed(value, task.cancelled ?? error)).finally(() => {
      tasks.delete(task);
      task.context = [];
      task.parent = null;
      task.done.resolve();
    });
  }

  // An import hands back a pending promise before any other Wasm entry runs.
  // The execution lease remains held after a wakeup is resolved, until Wasm
  // reaches its next import or its promising invocation actually settles.
  function suspend() {
    if (!active) throw new Error('control operations require the prototype runner');
    const task = active, wait = {task, deferred: Promise.withResolvers(), outcome: null, close: null};
    task.wait = wait;
    release(task);
    return wait;
  }

  function answer(wait, value, error = null) {
    if (!wait?.task || wait.outcome) return;
    wait.outcome = {value, error};
    enqueue(wait.task, () => {
      const {task, outcome} = wait;
      task.wait = null;
      wait.close?.();
      if (task.cancelled ?? outcome.error) wait.deferred.reject(task.cancelled ?? outcome.error);
      else wait.deferred.resolve(outcome.value);
      wait.task = null;
      wait.outcome = null;
      wait.close = null;
    });
  }

  function beneath(task, ancestor) {
    for (let current = task; current; current = current.parent) if (current === ancestor) return true;
    return false;
  }

  // Handler tasks are siblings of the selected body. Earlier handlers waiting
  // on resume survive this cancellation; inner bodies and handlers do not.
  async function abandon(body) {
    const suffix = [...tasks].filter(task => beneath(task, body));
    for (const task of suffix) {
      task.cancelled = new Abandoned();
      if (task.wait) answer(task.wait, undefined, task.cancelled);
    }
    await Promise.all(suffix.map(task => task.done.promise));
  }

  // ---- Logical answers ----

  function handle(code, closure, handler) {
    const wait = suspend();
    const frame = {parent: wait.task, outer: wait.task.context.slice(), body: null, answer: wait, closed: false};
    frames.set(handler, frame);
    wait.close = () => { frame.closed = true; frames.delete(handler); };
    frame.body = start(frame.parent, frame.outer, code, [closure, handler], (value, error) => {
      const recipient = frame.answer;
      frame.answer = null;
      answer(recipient, value, error);
    });
    return wait.deferred.promise;
  }

  function perform(handler, code, closure, args) {
    const frame = frames.get(handler);
    if (!frame || frame.closed || !frame.answer || !beneath(active, frame.body)) throw new Error('no active control boundary');
    const wait = suspend(), recipient = frame.answer;
    frame.answer = null;
    const token = {frame, wait, owner: null};
    continuations.add(token);
    token.owner = start(frame.parent, frame.outer, code, [closure, args, token], async (value, error) => {
      token.frame = null; token.wait = null; token.owner = null;
      continuations.delete(token);
      await abandon(frame.body);
      answer(recipient, value, error);
    });
    return wait.deferred.promise;
  }

  // Calling an inner continuation from an enclosing clause would require
  // splicing its captured outer handlers onto a different logical answer.
  // Scoped callers preserve the parent tree that abandonment relies on.
  function resume(token, value) {
    if (!continuations.has(token) || !token.wait || token.frame.closed)
      throw new Error('a continuation may be resumed only once, before its handler returns');
    if (!beneath(active, token.owner)) throw new Error('the ctl prototype resumes only within the originating clause');
    const operation = token.wait;
    token.wait = null; token.owner = null;
    const wait = suspend();
    token.frame.answer = wait;
    answer(operation, value);
    return wait.deferred.promise;
  }

  // Every asynchronous foreign import must use this wrapper. A raw
  // WebAssembly.Suspending import would bypass the execution lease.
  function suspending(operation) {
    return new WebAssembly.Suspending((...args) => {
      const result = operation(...args), wait = suspend();
      Promise.resolve(result).then(value => answer(wait, value), error => answer(wait, undefined, error));
      return wait.deferred.promise;
    });
  }

  async function run(entry, ...args) {
    if (running || entry.handlers.some(global => owned.has(global))) throw new Error('control prototype entries must not overlap');
    running = true;
    globals = [...new Set(entry.handlers)]; baseline = snapshot();
    globals.forEach(global => owned.add(global));
    const result = Promise.withResolvers();
    const root = start(null, baseline, entry.main, args, (value, error) => error ? result.reject(error) : result.resolve(value));
    try { return await result.promise; }
    finally {
      await root.done.promise;
      await abandon(root);
      restore(baseline);
      globals.forEach(global => owned.delete(global));
      globals = []; baseline = []; running = false;
    }
  }

  return {run, suspending, imports: {handle: new WebAssembly.Suspending(handle), perform: new WebAssembly.Suspending(perform),
                                   resume: new WebAssembly.Suspending(resume)},
          get stats() { return {tasks: tasks.size, boundaries: frames.size, continuations: continuations.size, queued: queue.length, active: active !== null}; }};
}
