// Exercise the execution permit with actual JSPI continuations, not mocked
// promises: resolving a gate is not the same as entering its Wasm stack.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createAssembler} from '../../scripts/assemble.mjs';
import {createScheduler, delay} from '../../src/app/tasks.mjs';

const assemble = await createAssembler(await readFile(process.argv[2]));
const module = await WebAssembly.compile(assemble(`(module
  (import "host" "wait" (func $wait (param i32) (result i32)))
  (import "host" "spawn" (func $spawn (param i32)))
  (import "host" "record" (func $record (param i32 externref i32)))
  (global $handler (export "handler.test") (mut externref) (ref.null extern))
  (func $body (export "child") (param $key i32) (result i32)
    (local $result i32)
    (call $record (local.get $key) (global.get $handler) (i32.const 0))
    (local.set $result (call $wait (local.get $key)))
    (call $record (local.get $key) (global.get $handler) (i32.const 1))
    (local.get $result))
  (func (export "run") (param $token externref) (param $key i32) (result i32)
    (global.set $handler (local.get $token))
    (call $body (local.get $key)))
  (func (export "parent") (param $token externref) (param $key i32)
    (global.set $handler (local.get $token))
    (call $spawn (local.get $key)))
  (func (export "twice") (param $token externref) (param $key i32)
    (global.set $handler (local.get $token))
    (drop (call $body (local.get $key)))
    (drop (call $body (i32.add (local.get $key) (i32.const 1)))))
  (func (export "fail") (param $token externref) (param $key i32)
    (global.set $handler (local.get $token))
    (drop (call $body (local.get $key)))
    (unreachable)))`));

const turn = () => new Promise(setImmediate);
async function until(predicate) {
  const end = Date.now() + 3000;
  while (!predicate()) { assert.ok(Date.now() < end, 'task reached its expected boundary'); await turn(); }
}
async function fixture({abortable = true} = {}) {
  let instance;
  const waits = new Map(), records = [], errors = [], cleaned = [];
  const scheduler = createScheduler({handlerGlobals: () => instance ? [instance.exports['handler.test']] : [],
                                     reportError: error => errors.push(error)});
  const host = {
    wait: scheduler.suspending((signal, key) => {
      const completion = Promise.withResolvers();
      waits.set(key, completion);
      const abort = () => completion.reject(signal.reason);
      if (abortable) signal.addEventListener('abort', abort, {once: true});
      return completion.promise.finally(() => {
        signal.removeEventListener('abort', abort);
        waits.delete(key);
        cleaned.push(key);
      });
    }),
    spawn: key => scheduler.dispatch(() => WebAssembly.promising(instance.exports.child)(key)),
    record: (key, token, phase) => records.push([key, token, phase]),
  };
  instance = await WebAssembly.instantiate(module, {host});
  const run = (token, key) => scheduler.start(() => WebAssembly.promising(instance.exports.run)(token, key));
  return {scheduler, instance, waits, records, errors, cleaned, run,
          settled() { assert.equal(scheduler.size, 0); assert.equal(instance.exports['handler.test'].value, null); }};
}

async function isolation() {
  const f = await fixture(), a = {}, b = {};
  const first = f.run(a, 1), second = f.run(b, 2);
  await until(() => f.waits.size === 2);
  assert.equal(f.instance.exports['handler.test'].value, null, 'idle globals hold runtime defaults');
  f.waits.get(2).resolve(20); f.waits.get(1).resolve(10);
  assert.deepEqual(await Promise.all([first.done, second.done]), [10, 20]);
  assert.deepEqual(f.records, [[1, a, 0], [2, b, 0], [2, b, 1], [1, a, 1]]);
  await f.scheduler.drain(); f.settled();
}

async function detachedChild() {
  const f = await fixture(), token = {};
  const parent = f.scheduler.start(() => WebAssembly.promising(f.instance.exports.parent)(token, 3));
  await parent.done;
  await until(() => f.waits.has(3));
  assert.equal(f.scheduler.size, 1, 'parent completion does not remove its child');
  let exhausted = false;
  const drain = f.scheduler.drain().then(() => { exhausted = true; });
  await turn(); assert.equal(exhausted, false);
  f.waits.get(3).resolve(30); await drain;
  assert.deepEqual(f.records, [[3, token, 0], [3, token, 1]], 'ordinary bindings survive parent return');
  f.settled();
}

async function cancellation() {
  const f = await fixture();
  let dropped = 0;
  const queued = f.scheduler.dispatch(() => assert.fail('cancelled work ran'), () => dropped++);
  queued.cancel(); queued.cancel();
  await assert.rejects(queued.done, {name: 'AbortError'});
  assert.equal(dropped, 1);
  const waiting = f.run({}, 4);
  await until(() => f.waits.has(4));
  waiting.cancel();
  await assert.rejects(waiting.done, {name: 'AbortError'});
  assert.deepEqual(f.cleaned, [4]);
  assert.equal(f.records.length, 1, 'cancelled continuation unwinds without running its next instruction');
  const ready = f.run({}, 5);
  await until(() => f.waits.has(5));
  const held = Promise.withResolvers();
  const blocker = f.scheduler.start(() => held.promise);
  await turn(); // Hold the permit while the other invocation becomes ready.
  f.waits.get(5).resolve(50);
  await turn();
  ready.cancel(); held.resolve(); await blocker.done;
  await assert.rejects(ready.done, {name: 'AbortError'});
  assert.equal(f.records.filter(([key]) => key === 5).length, 1);
  const closing = f.run({}, 9);
  await until(() => f.waits.has(9));
  const closed = f.scheduler.close();
  await assert.rejects(closing.done, {name: 'AbortError'});
  await closed;
  assert.throws(() => f.scheduler.dispatch(() => {}), /closed/);
  f.settled();
}

async function cleanupBeforeCompletion() {
  const f = await fixture({abortable: false});
  const task = f.run({}, 6);
  await until(() => f.waits.has(6));
  task.cancel();
  await turn();
  assert.equal(f.scheduler.size, 1, 'non-abortable operation remains accounted until it finishes');
  f.waits.get(6).resolve(60);
  await assert.rejects(task.done, {name: 'AbortError'});
  assert.deepEqual(f.cleaned, [6]);
  f.settled();
}

async function failure() {
  const f = await fixture(), goodToken = {};
  const bad = f.scheduler.dispatch(() => WebAssembly.promising(f.instance.exports.fail)({}, 7));
  const good = f.run(goodToken, 8);
  await until(() => f.waits.size === 2);
  f.waits.get(7).resolve(70); f.waits.get(8).resolve(80);
  await assert.rejects(bad.done, WebAssembly.RuntimeError);
  assert.equal(await good.done, 80);
  assert.equal(f.errors.length, 1);
  assert.deepEqual(f.records.at(-1), [8, goodToken, 1]);
  const undefinedFailure = f.scheduler.start(() => f.scheduler.suspend(() => { throw undefined; }));
  assert.deepEqual(await Promise.allSettled([undefinedFailure.done]), [{status: 'rejected', reason: undefined}]);
  f.settled();
}

async function fairness() {
  const scheduler = createScheduler();
  let input = false, count = 0;
  setTimeout(() => { input = true; }, 0);
  function again() { if (++count < 200) scheduler.dispatch(again); }
  scheduler.dispatch(again);
  await scheduler.drain();
  assert.equal(count, 200); assert.equal(input, true, 'a chain of short tasks does not starve the event loop');
  const task = scheduler.start(() => scheduler.suspend(signal => delay(signal, 0)));
  await task.done;
  const controller = new AbortController(); controller.abort();
  assert.throws(() => delay(controller.signal), {name: 'AbortError'});
}

async function failedDiscard() {
  const errors = [], scheduler = createScheduler({reportError: error => errors.push(error)});
  const bad = scheduler.dispatch(() => assert.fail('discarded work ran'), () => { throw new Error('discard failed'); });
  const other = scheduler.dispatch(() => assert.fail('closing work ran'));
  await scheduler.close();
  await assert.rejects(bad.done, /discard failed/);
  await assert.rejects(other.done, {name: 'AbortError'});
  assert.equal(errors.length, 1); assert.equal(scheduler.size, 0);
}

async function repeatedSuspension() {
  const f = await fixture(), token = {};
  const task = f.scheduler.start(() => WebAssembly.promising(f.instance.exports.twice)(token, 10));
  await until(() => f.waits.has(10)); f.waits.get(10).resolve(100);
  await until(() => f.waits.has(11)); task.cancel();
  await assert.rejects(task.done, {name: 'AbortError'});
  assert.deepEqual(f.records, [[10, token, 0], [10, token, 1], [11, token, 0]]);
  assert.deepEqual(f.cleaned, [10, 11]); f.settled();
}

async function lateHandlers() {
  const globals = [], token = {}, observed = [];
  const scheduler = createScheduler({handlerGlobals: () => globals});
  const parent = scheduler.start(() => {
    const global = new WebAssembly.Global({value: 'externref', mutable: true}, token);
    globals.push(global);
    scheduler.dispatch(async () => {
      observed.push(global.value);
      await scheduler.suspend(signal => delay(signal));
      observed.push(global.value);
    });
  });
  await parent.done; await scheduler.drain();
  assert.deepEqual(observed, [token, token]); assert.equal(globals[0].value, null);
}

await isolation();
await detachedChild();
await cancellation();
await cleanupBeforeCompletion();
await failure();
await fairness();
await failedDiscard();
await repeatedSuspension();
await lateHandlers();
console.log('tasks: JSPI bindings, exhaustion, cancellation, cleanup and fairness');
