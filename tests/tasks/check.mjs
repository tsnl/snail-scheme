// Exercise the execution permit with actual JSPI continuations, not mocked
// promises: resolving a gate is not the same as entering its Wasm stack.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createAssembler} from '../../host/native/assemble.mjs';
import {createScheduler, delay} from '../../host/browser/tasks.mjs';

const assemble = await createAssembler(await readFile(process.argv[2]));
const module = await WebAssembly.compile(assemble(`(module
  (import "host" "wait" (func $wait (param i32) (result i32)))
  (import "host" "spawn" (func $spawn (param i32)))
  (import "host" "record" (func $record (param i32 i32)))
  (func $body (export "child") (param $key i32) (result i32)
    (local $result i32)
    (call $record (local.get $key) (i32.const 0))
    (local.set $result (call $wait (local.get $key)))
    (call $record (local.get $key) (i32.const 1))
    (local.get $result))
  (func (export "run") (param $key i32) (result i32)
    (call $body (local.get $key)))
  (func (export "parent") (param $key i32)
    (call $spawn (local.get $key)))
  (func (export "twice") (param $key i32)
    (drop (call $body (local.get $key)))
    (drop (call $body (i32.add (local.get $key) (i32.const 1)))))
  (func (export "fail") (param $key i32)
    (drop (call $body (local.get $key)))
    (unreachable)))`));

const turn = () => new Promise(setImmediate);
async function until(predicate) {
  const end = Date.now() + 3000;
  while (!predicate()) { assert.ok(Date.now() < end, 'task reached its expected boundary'); await turn(); }
}
async function fixture({abortable = true, discard = null} = {}) {
  let instance;
  const waits = new Map(), records = [], errors = [], cleaned = [];
  const scheduler = createScheduler({reportError: error => errors.push(error)});
  const host = {
    wait: new WebAssembly.Suspending(key => scheduler.suspend(signal => {
      const completion = Promise.withResolvers();
      waits.set(key, completion);
      const abort = () => completion.reject(signal.reason);
      if (abortable) signal.addEventListener('abort', abort, {once: true});
      return completion.promise.finally(() => {
        signal.removeEventListener('abort', abort);
        waits.delete(key);
        cleaned.push(key);
      });
    }, discard)),
    spawn: key => scheduler.dispatch(() => WebAssembly.promising(instance.exports.child)(key)),
    record: (key, phase) => records.push([key, phase]),
  };
  instance = await WebAssembly.instantiate(module, {host});
  const run = key => scheduler.start(() => WebAssembly.promising(instance.exports.run)(key));
  return {scheduler, instance, waits, records, errors, cleaned, run,
          settled() { assert.equal(scheduler.size, 0); }};
}

async function isolation() {
  const f = await fixture();
  const first = f.run(1), second = f.run(2);
  await until(() => f.waits.size === 2);
  f.waits.get(2).resolve(20); f.waits.get(1).resolve(10);
  assert.deepEqual(await Promise.all([first.done, second.done]), [10, 20]);
  assert.deepEqual(f.records, [[1, 0], [2, 0], [2, 1], [1, 1]]);
  await f.scheduler.drain(); f.settled();
}

async function detachedChild() {
  const f = await fixture();
  const parent = f.scheduler.start(() => WebAssembly.promising(f.instance.exports.parent)(3));
  await parent.done;
  await until(() => f.waits.has(3));
  assert.equal(f.scheduler.size, 1, 'parent completion does not remove its child');
  let exhausted = false;
  const drain = f.scheduler.drain().then(() => { exhausted = true; });
  await turn(); assert.equal(exhausted, false);
  f.waits.get(3).resolve(30); await drain;
  assert.deepEqual(f.records, [[3, 0], [3, 1]], 'a detached child records after its parent returns');
  f.settled();
}

async function cancellation() {
  const discarded = [], f = await fixture({discard: value => discarded.push(value)});
  let dropped = 0;
  const queued = f.scheduler.dispatch(() => assert.fail('cancelled work ran'), () => dropped++);
  queued.cancel(); queued.cancel();
  await assert.rejects(queued.done, {name: 'AbortError'});
  assert.equal(dropped, 1);
  const waiting = f.run(4);
  await until(() => f.waits.has(4));
  waiting.cancel();
  await assert.rejects(waiting.done, {name: 'AbortError'});
  assert.deepEqual(f.cleaned, [4]);
  assert.equal(f.records.length, 1, 'cancelled continuation unwinds without running its next instruction');
  const ready = f.run(5);
  await until(() => f.waits.has(5));
  const held = Promise.withResolvers();
  const blocker = f.scheduler.start(() => held.promise);
  await turn(); // Hold the permit while the other invocation becomes ready.
  f.waits.get(5).resolve(50);
  await turn();
  ready.cancel(); held.resolve(); await blocker.done;
  await assert.rejects(ready.done, {name: 'AbortError'});
  assert.equal(f.records.filter(([key]) => key === 5).length, 1);
  assert.deepEqual(discarded, [50], 'cancellation disposes the queued result exactly once');
  const closing = f.run(9);
  await until(() => f.waits.has(9));
  const heldOnClose = Promise.withResolvers();
  const blockerOnClose = f.scheduler.start(() => heldOnClose.promise);
  await turn();
  f.waits.get(9).resolve(90); await turn();
  let drained = false;
  const closed = f.scheduler.close().then(() => { drained = true; });
  await turn(); assert.equal(drained, false, 'close waits for disposal and JSPI unwind');
  heldOnClose.resolve();
  await assert.rejects(blockerOnClose.done, {name: 'AbortError'});
  await assert.rejects(closing.done, {name: 'AbortError'});
  await closed;
  assert.deepEqual(discarded, [50, 90]);
  assert.throws(() => f.scheduler.dispatch(() => {}), /closed/);
  f.settled();
}

async function cleanupBeforeCompletion() {
  const discarded = [], f = await fixture({abortable: false, discard: value => discarded.push(value)});
  const task = f.run(6);
  await until(() => f.waits.has(6));
  task.cancel();
  await turn();
  assert.equal(f.scheduler.size, 1, 'non-abortable operation remains accounted until it finishes');
  assert.deepEqual(discarded, []);
  f.waits.get(6).resolve(60);
  await assert.rejects(task.done, {name: 'AbortError'});
  assert.deepEqual(f.cleaned, [6]);
  assert.deepEqual(discarded, [60], 'late successful result is never delivered to cancelled Wasm');
  f.settled();
}

async function failure() {
  const f = await fixture();
  const bad = f.scheduler.dispatch(() => WebAssembly.promising(f.instance.exports.fail)(7));
  const good = f.run(8);
  await until(() => f.waits.size === 2);
  f.waits.get(7).resolve(70); f.waits.get(8).resolve(80);
  await assert.rejects(bad.done, WebAssembly.RuntimeError);
  assert.equal(await good.done, 80);
  assert.equal(f.errors.length, 1);
  assert.deepEqual(f.records.at(-1), [8, 1]);
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

async function failedResultDiscard() {
  const disposed = [], failure = new Error('result disposal failed'), operationFailure = new Error('operation failed');
  const f = await fixture({abortable: false, discard: value => { disposed.push(value); throw failure; }});
  const bad = f.scheduler.dispatch(() => WebAssembly.promising(f.instance.exports.run)(7));
  const good = f.run(8), rejected = f.run(9);
  await until(() => f.waits.size === 3);
  bad.cancel();
  f.waits.get(7).resolve(70); f.waits.get(8).resolve(80); f.waits.get(9).reject(operationFailure);
  await assert.rejects(bad.done, error => error === failure);
  assert.equal(await good.done, 80);
  await assert.rejects(rejected.done, error => error === operationFailure);
  assert.deepEqual(disposed, [70], 'delivered results and operation failures do not call the disposer');
  assert.deepEqual(f.errors, [failure], 'a disposal failure reports once after the parked stack unwinds');
  assert.deepEqual(f.records.filter(([key]) => key === 7).map(([, phase]) => phase), [0]);
  assert.deepEqual(f.records.at(-1), [8, 1]);
  await f.scheduler.drain(); f.settled();
}

async function repeatedSuspension() {
  const f = await fixture();
  const task = f.scheduler.start(() => WebAssembly.promising(f.instance.exports.twice)(10));
  await until(() => f.waits.has(10)); f.waits.get(10).resolve(100);
  await until(() => f.waits.has(11)); task.cancel();
  await assert.rejects(task.done, {name: 'AbortError'});
  assert.deepEqual(f.records, [[10, 0], [10, 1], [11, 0]]);
  assert.deepEqual(f.cleaned, [10, 11]); f.settled();
}

await isolation();
await detachedChild();
await cancellation();
await cleanupBeforeCompletion();
await failure();
await fairness();
await failedDiscard();
await failedResultDiscard();
await repeatedSuspension();
console.log('tasks: JSPI permits, exhaustion, cancellation, cleanup and fairness');
