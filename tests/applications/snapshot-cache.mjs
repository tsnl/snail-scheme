// Execute the real managed decoder cache. Reads of field 1 count codec inputs;
// schema probes use field 0 and never masquerade as a decoded-value reuse.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';

const contract = {version: 1, applications: [
  {owner: 'match', schema: 1, handlers: [
    {binding: 'add', id: 'add', slot: 0, payload: ['I32']},
    {binding: 'invalid', id: 'invalid', slot: 1, payload: []}]},
  {owner: 'client', schema: 1, handlers: [{binding: 'remember', id: 'remember', slot: 0, payload: []}]}]};
const add = (r, amount, options) => r.dispatch(1, r.command('match', 'add', [amount]), options);
const values = r => r.view().quads[0].slice(0, 4);
function fieldReads(runtime) {
  const original = runtime.read, previous = runtime.previousBank; let counts = [0, 0];
  runtime.read = function(owner, index) {
    if (index === 1) counts[owner - 1]++;
    return original.call(this, owner, index);
  };
  runtime.previousBank = function(owner, index) {
    if (index === 1) counts[owner - 1]++;
    return previous.call(this, owner, index);
  };
  return () => { const result = counts; counts = [0, 0]; return result; };
}
async function fresh(bytes) {
  const runtime = new ReducerRuntime();
  await runtime.replace(runtime.prepare(bytes, contract));
  await runtime.initialize(1); await runtime.initialize(2); return runtime;
}
function delayedSave() {
  let accept, reject, entered;
  const pending = new Promise((yes, no) => { accept = yes; reject = no; });
  const ready = new Promise(yes => entered = yes);
  return {ready, accept, reject, persist: state => { entered(state); return pending; }};
}

export async function checkSnapshotCache(test, fixture) {
  const bytes = fixture('snapshot-cache');
  await test('decoded World and Client values reuse exact current and prior banks', async () => {
    const r = await fresh(bytes), reads = fieldReads(r);
    assert.deepEqual(values(r), [0, 0, 0, 0]); assert.deepEqual(values(r), [0, 0, 0, 0]);
    assert.deepEqual(reads(), [0, 0]);
    await add(r, 5); assert.deepEqual(reads(), [1, 0]);
    assert.deepEqual(values(r), [5, 0, 0, 0]); assert.deepEqual(reads(), [0, 0]);
    await r.dispatch(2, r.command('client', 'remember'));
    assert.deepEqual(reads(), [0, 1]); assert.deepEqual(values(r), [5, 5, 0, 0]);
    assert.deepEqual(reads(), [0, 0]); await r.close();
  });
  await test('new encoded candidates and equal external restores always pass decoding', async () => {
    const r = await fresh(bytes), reads = fieldReads(r), initial = r.stores.get(1);
    await add(r, 0); assert.deepEqual(reads(), [1, 0]); assert.equal(r.stores.get(1), initial);
    const words = r.snapshot(1); await r.restore(1, words); words[1] = 99;
    assert.deepEqual(reads(), [1, 0]); assert.notEqual(r.stores.get(1), initial);
    assert.deepEqual(values(r), [0, 0, 0, 0]); assert.deepEqual(reads(), [0, 0]); await r.close();
  });
  await test('invalid interpretations never enter the cache or reach persistence', async () => {
    const r = await fresh(bytes), reads = fieldReads(r), invalid = new Int32Array([1, -1]);
    const banks = new Map(r.stores).set(1, invalid), before = r.snapshot(1); let writes = 0;
    for (let attempt = 0; attempt < 2; attempt++) {
      assert.throws(() => r.validateState(r.instance, banks), WebAssembly.RuntimeError);
      assert.deepEqual(reads(), [1, 0]);
    }
    await assert.rejects(r.dispatch(1, r.command('match', 'invalid'), {persist: () => writes++}), WebAssembly.RuntimeError);
    assert.deepEqual(reads(), [1, 0]); assert.equal(writes, 0); assert.deepEqual(r.snapshot(1), before);
    assert.deepEqual(values(r), [0, 0, 0, 0]); assert.deepEqual(reads(), [0, 0]);
    await assert.rejects(r.restore(1, [1, -1]), WebAssembly.RuntimeError);
    await assert.rejects(r.restore(1, [1, 0, 1]), /invalid snapshot/); await r.close();
  });
  await test('pending saves and failed saves retain committed current/prior values', async () => {
    const r = await fresh(bytes); await add(r, 2);
    const reads = fieldReads(r), save = delayedSave(); let publications = 0;
    const pending = add(r, 3, {persist: save.persist, publish: output => {
      assert.deepEqual(values(r), [5, 0, 2, 0]); assert.equal(output.effects[0].text, 'saved'); publications++;
    }});
    assert.deepEqual(await save.ready, [1, 5]); assert.deepEqual(reads(), [1, 0]);
    assert.deepEqual(values(r), [2, 0, 0, 0]); assert.deepEqual(reads(), [0, 0]); assert.equal(publications, 0);
    save.accept(); await pending; assert.equal(publications, 1); assert.deepEqual(reads(), [0, 0]);
    const failing = delayedSave(), failed = add(r, 7, {persist: failing.persist, publish: () => publications++});
    const rejection = assert.rejects(failed, /disk unavailable/); await failing.ready;
    assert.deepEqual(values(r), [5, 0, 2, 0]); failing.reject(new Error('disk unavailable')); await rejection;
    assert.deepEqual(values(r), [5, 0, 2, 0]); assert.equal(publications, 1); await r.close();
  });
  await test('prepared generations and rollback use their own validated interpretations', async () => {
    const r = await fresh(bytes), original = r.instance, reads = fieldReads(r);
    const candidate = r.prepare(bytes, contract); assert.deepEqual(reads(), [1, 1]);
    assert.deepEqual(values(r), [0, 0, 0, 0]); assert.deepEqual(reads(), [0, 0]);
    await r.replace(candidate); assert.deepEqual(reads(), [0, 0]);
    await add(r, 9); assert.deepEqual(reads(), [1, 0]);
    await assert.rejects(r.dispatch(1, r.command('match', 'invalid')), WebAssembly.RuntimeError);
    assert.equal(r.instance, original); assert.deepEqual(reads(), [2, 0]);
    assert.deepEqual(values(r), [9, 0, 0, 0]); assert.deepEqual(reads(), [0, 0]); await r.close();
  });
  await test('installing a prepared generation validates banks committed after preparation', async () => {
    const r = await fresh(bytes), candidate = r.prepare(bytes, contract);
    await add(r, 4); const reads = fieldReads(r);
    await r.replace(candidate); assert.deepEqual(reads(), [1, 0]);
    assert.deepEqual(values(r), [4, 0, 0, 0]); assert.deepEqual(reads(), [0, 0]); await r.close();
  });
  await test('independent runtimes may issue equal tokens without sharing interpretations', async () => {
    const first = await fresh(bytes), second = await fresh(bytes);
    await add(first, 6); await add(second, 9);
    assert.deepEqual(values(first), [6, 0, 0, 0]); assert.deepEqual(values(second), [9, 0, 0, 0]);
    await first.close(); await second.close();
  });
  await test('each decoder retains only three interpretations and eviction revalidates', async () => {
    const r = await fresh(bytes), banks = [r.stores.get(1)], reads = fieldReads(r);
    for (let i = 0; i < 3; i++) { await add(r, 1); banks.push(r.stores.get(1)); }
    reads();
    for (const bank of banks.slice(1)) r.validateState(r.instance, new Map(r.stores).set(1, bank));
    assert.deepEqual(reads(), [0, 0]);
    r.validateState(r.instance, new Map(r.stores).set(1, banks[0])); assert.deepEqual(reads(), [1, 0]);
    assert.deepEqual(values(r), [3, 0, 2, 0]); await r.close();
  });
  await test('snapshot identities are private-scope monotonic tokens, including discarded banks', async () => {
    const r = await fresh(bytes), identity = r.snapshotIdentity, seen = new Map(), worldTokens = [];
    r.snapshotIdentity = function(owner, previous) {
      const bank = previous ? this.previousBank(owner) : this.bank(owner), token = identity.call(this, owner, previous);
      if (seen.has(token)) assert.equal(seen.get(token), bank);
      else { seen.set(token, bank); if (owner === 1) worldTokens.push(token); }
      return token;
    };
    for (let i = 0; i < 40; i++) await r.restore(1, [1, i % 3]);
    assert.ok(seen.size >= 41); assert.deepEqual(worldTokens, [...worldTokens].sort((a, b) => a - b));
    r.snapshotIdentity = identity;
    assert.throws(() => r.provider.exports.identity(1, 0), /outside a transaction/);
    assert.throws(() => r.provider.exports.identity(1, 2), /invalid snapshot identity source/); await r.close();
  });
}

if (process.argv[1] && resolve(process.argv[1]) === import.meta.filename) {
  const directory = resolve(process.argv[2]); let passed = 0;
  await checkSnapshotCache(async (name, run) => { await run(); console.log(`ok ${++passed} - ${name}`); },
    name => readFileSync(join(directory, `${name}.wasm`)));
  console.log(`${passed} decoded snapshot cache checks passed`);
}
