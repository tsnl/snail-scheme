// Actual tiny Wasm reducers with controllable I/O: no alternative reducer model.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {LocalState} from '../../src/application/local.mjs';

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return {promise, resolve, reject};
}
function delayedSave() {
  const entered = deferred(), completion = deferred();
  return {entered: entered.promise, ...completion, persist: (state, effects) => {
    entered.resolve({state, effects}); return completion.promise;
  }};
}
const handlers = [['add', 1], ['add-also', 1], ['view-flag', 1], ['reset', 0], ['bad-notice', 0], ['bad-send', 0], ['trap', 0]];
const contract = {version: 1, applications: [
  {owner: 'match', schema: 1, handlers: handlers.map(([binding, arity], slot) => ({binding, id: binding, slot, payload: Array(arity).fill('I32')}))},
  {owner: 'client', schema: 1, handlers: [{binding: 'local', id: 'local', slot: 0, payload: ['I32']}]},
]};
async function fresh(bytes) {
  const r = new ReducerRuntime();
  await r.replace(r.prepare(bytes, contract)); await r.initialize(1); await r.initialize(2);
  return r;
}
const command = (binding, args = []) => ({handler: binding, args});
export async function checkAsyncRuntime(test, fixture) {
  const bytes = fixture('async-boundary'), viewBytes = fixture('async-view');
  await test('pending saves expose committed queries, capture commands and serialize both owners', async () => {
    const r = await fresh(bytes), independent = await fresh(bytes), before = r.snapshot(1), save = delayedSave();
    let published = 0;
    const first = r.dispatch(1, command('add', [2]), {persist: save.persist, publish: output => {
      assert.equal(r.snapshot(1)[1], 2); assert.equal(output.effects[0].text, 'A'); published++;
    }});
    const candidate = await save.entered, mutable = command('add', [3]);
    const next = r.dispatch(1, mutable), local = r.dispatch(2, command('local', [4])); mutable.args[0] = 99;
    assert.equal(r.active, undefined); assert.throws(() => r.provider.exports.read(1, 0), /outside a transaction/);
    assert.deepEqual(r.snapshot(1), before); assert.equal(r.snapshot(2)[1], 0); assert.equal(r.view().label, 'A');
    assert.equal(published, 0); assert.equal(candidate.state[1], 2);
    assert.throws(() => candidate.state[1] = 99, TypeError);
    assert.throws(() => candidate.effects[1].command.args[0] = 99, TypeError);
    await independent.dispatch(1, command('add', [9])); assert.equal(independent.snapshot(1)[1], 9);
    save.resolve(); await Promise.all([first, next, local]);
    assert.equal(r.snapshot(1)[1], 5); assert.equal(r.snapshot(2)[1], 4); assert.equal(published, 1);
    await r.close(); await independent.close();
  });
  await test('async local commits serialize revisions and retain the previous state until durable', async () => {
    const r = await fresh(bytes), save = delayedSave(); let durable, writes = 0;
    const local = new LocalState(r, {commit: (checkpoint, expected) => {
      assert.equal(checkpoint.revision, expected + 1); durable = checkpoint;
      return ++writes === 1 ? save.persist(checkpoint) : undefined;
    }});
    const mutable = command('add', [2]), first = local.submit(mutable), second = local.submit(command('add', [3]));
    mutable.args[0] = 99; await save.entered;
    assert.equal(local.revision, 0); assert.equal(r.snapshot(1)[1], 0);
    save.resolve(); await Promise.all([first, second]); assert.equal(local.revision, 2); assert.equal(r.snapshot(1)[1], 5);
    const copy = await fresh(bytes), restored = await LocalState.open(copy, {saved: durable});
    assert.deepEqual(restored.snapshot(), local.snapshot()); await r.close(); await copy.close();
  });
  await test('failed async commit can retry without changing code or consuming a revision', async () => {
    const r = await fresh(bytes); await r.replace(r.prepare(bytes, contract));
    const instance = r.instance, save = delayedSave(); let writes = 0, deliveries = 0;
    const local = new LocalState(r, {commit: () => ++writes === 1 ? save.persist() : undefined, publish: () => deliveries++});
    const before = local.snapshot(), first = local.submit(command('add', [2]));
    const failed = assert.rejects(first, /storage offline/), retry = local.submit(command('add', [2]));
    await save.entered; assert.deepEqual(local.snapshot(), before); save.reject(new Error('storage offline'));
    await failed; await retry; assert.equal(r.instance, instance); assert.equal(r.snapshot(1)[1], 2);
    assert.equal(local.revision, 1); assert.equal(deliveries, 1); await r.close();
  });
  await test('imported checkpoints validate and persist before publication, including rollback on failure', async () => {
    const r = await fresh(bytes), save = delayedSave(), local = new LocalState(r, {commit: save.persist});
    const before = local.snapshot(), words = [1, 8, 0, 0], importing = local.restore(words); words[1] = 99;
    const rejected = assert.rejects(importing, /load failed/); await save.entered;
    assert.deepEqual(local.snapshot(), before); save.reject(new Error('load failed')); await rejected;
    assert.deepEqual(local.snapshot(), before); local.commit = () => {};
    await local.restore([1, 8, 0, 0]); assert.equal(local.revision, 1); assert.equal(r.snapshot(1)[1], 8);
    const accepted = local.snapshot(); await assert.rejects(() => local.restore([99, 9, 0, 0]), /schema/);
    assert.deepEqual(local.snapshot(), accepted); await r.close();
  });
  await test('notice conversion, effect routing and reducer traps all fail before persistence', async () => {
    const r = await fresh(bytes), before = r.snapshot(1); let writes = 0, deliveries = 0;
    for (const binding of ['bad-notice', 'bad-send', 'trap']) {
      await assert.rejects(r.dispatch(1, command(binding), {persist: () => writes++, publish: () => deliveries++}));
      assert.deepEqual(r.snapshot(1), before);
    }
    assert.equal(writes, 0); assert.equal(deliveries, 0); await r.close();
  });
  await test('delayed effects retain their originating handler identity across reordered slots', async () => {
    const r = await fresh(bytes), save = delayedSave(), reordered = structuredClone(contract);
    [reordered.applications[0].handlers[0], reordered.applications[0].handlers[1]] =
      [reordered.applications[0].handlers[1], reordered.applications[0].handlers[0]];
    reordered.applications[0].handlers.forEach((handler, slot) => handler.slot = slot);
    const transition = r.dispatch(2, command('local', [7]), {persist: save.persist}); await save.entered;
    const candidate = r.prepare(bytes, reordered), install = r.replace(candidate), previous = r.instance;
    assert.equal(r.instance, previous); assert.equal(r.snapshot(2)[1], 0);
    save.resolve(); const result = await transition; await install;
    assert.equal(r.instance, candidate.instance); assert.equal(r.manifest.applications[0].handlers[0].id, 'add-also');
    assert.deepEqual(r.effectCommand(result.effects[0]), command('add', [7]));
    await r.dispatch(1, r.effectCommand(result.effects[0])); assert.equal(r.snapshot(1)[1], 7); await r.close();
  });
  await test('candidate installation waits for persistence and validates the latest committed state', async () => {
    const r = await fresh(bytes), save = delayedSave(), original = r.instance;
    const transition = r.dispatch(1, command('view-flag', [1]), {persist: save.persist}); await save.entered;
    const candidate = r.prepare(viewBytes, contract), rejected = assert.rejects(r.replace(candidate), WebAssembly.RuntimeError);
    assert.equal(r.instance, original); assert.equal(r.snapshot(1)[2], 0);
    save.resolve(); await transition; await rejected;
    assert.equal(r.snapshot(1)[2], 1); assert.equal(r.instance, original); r.discard(candidate); await r.close();
  });
  await test('query recovery waits for a pending save and ignores a later installed activation', async () => {
    for (const replaceBeforeRecovery of [false, true]) {
      const r = await fresh(bytes), original = r.instance;
      await r.replace(r.prepare(viewBytes, contract)); const faulty = r.instance;
      await r.dispatch(1, command('view-flag', [1]));
      const save = delayedSave(), pending = r.dispatch(1, command('add', [2]), {persist: save.persist}); await save.entered;
      const candidate = replaceBeforeRecovery ? r.prepare(bytes, contract) : undefined;
      const replacement = candidate ? r.replace(candidate) : undefined;
      assert.throws(() => r.view(), WebAssembly.RuntimeError); assert.equal(r.instance, faulty);
      save.resolve(); await pending; await replacement; await r.message(() => {});
      assert.equal(r.instance, candidate?.instance ?? original); assert.equal(r.snapshot(1)[1], 2);
      assert.equal(r.view().label, 'A'); await r.close();
    }
  });
  await test('restore captures its input and close drains admitted messages while rejecting new work', async () => {
    const r = await fresh(bytes), save = delayedSave(), first = r.dispatch(1, command('add', [2]), {persist: save.persist});
    await save.entered;
    const words = [1, 20, 0, 0], restore = r.restore(1, words), last = r.dispatch(1, command('add', [3])); words[1] = 99;
    const local = new LocalState(r), admitted = local.submit(command('add', [4])), closing = r.close();
    await assert.rejects(r.dispatch(2, command('local', [1])), /closing/);
    await assert.rejects(local.submit(command('add', [9])), /closing/);
    assert.throws(() => r.view(), /closing/); assert.equal(r.snapshot(1)[1], 0);
    save.resolve(); await Promise.all([first, restore, last, admitted, closing]);
    assert.equal(r.snapshot(1)[1], 27); assert.equal(local.revision, 1); assert.equal(r.close(), closing);
  });
  await test('message dispatch is single use, expires, and drains an unreturned transition promise', async () => {
    const r = await fresh(bytes), save = delayedSave(); let retained, finished = false;
    const first = r.message(dispatch => {
      retained = dispatch; void dispatch(1, command('add', [2]), {persist: save.persist});
      assert.throws(() => dispatch(1, command('add', [9])), /one transition/);
      return 'message result';
    });
    const next = r.message(() => finished = true); await save.entered;
    assert.equal(finished, false); save.resolve(); assert.equal(await first, 'message result'); await next;
    assert.equal(r.snapshot(1)[1], 2); assert.throws(() => retained(1, command('add', [9])), /one transition/);
    await r.close();
  });
}

if (process.argv[1] && resolve(process.argv[1]) === import.meta.filename) {
  const directory = resolve(process.argv[2]); let passed = 0;
  await checkAsyncRuntime(async (name, run) => { await run(); console.log(`ok ${++passed} - ${name}`); },
    name => readFileSync(join(directory, `${name}.wasm`)));
  console.log(`${passed} async runtime checks passed`);
}
