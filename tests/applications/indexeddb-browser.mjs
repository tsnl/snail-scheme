// Executed in Chromium against its real IndexedDB and the packaged Scheme/Wasm.
function check(value, message) { if (!value) throw new Error(message); }
const equal = (left, right) => JSON.stringify(left) === JSON.stringify(right);
async function rejects(operation, pattern) {
  try { await operation(); } catch (error) { check(pattern.test(error.message), error.message); return; }
  throw new Error('expected rejection');
}
export async function checkIndexedDB(base) {
  const {ReducerRuntime} = await import(new URL('lib/application/runtime.mjs', base));
  const {LocalState} = await import(new URL('lib/application/local.mjs', base));
  const {openStore, saveName} = await import(new URL('lib/application/indexeddb.mjs', base));
  const manifest = await (await fetch(new URL('manifest.json', base))).json();
  manifest.settings.id = `storage-test-${crypto.randomUUID()}`;
  const bytes = new Uint8Array(await (await fetch(new URL(manifest.module, base))).arrayBuffer());
  async function open() {
    const runtime = new ReducerRuntime(), store = await openStore(manifest), notices = [];
    await runtime.replace(runtime.prepare(bytes, manifest)); await runtime.initialize(1); await runtime.initialize(2);
    const local = await LocalState.open(runtime, {saved: await store.load(),
      commit: (state, expected) => store.commit(state, expected), publish: value => notices.push(value)});
    const command = (binding, args = []) => local.submit(runtime.command('match', binding, args));
    return {runtime, store, local, command, notices, close: async () => { await runtime.close(); store.close(); }};
  }
  const results = [], first = await open();
  check(await first.store.load() === undefined, 'fresh open should not fabricate a durable record');
  await first.command('pause-colony', [1]);
  const saved = await first.store.load(); await first.close();
  const legacy = {...saved, epoch: 'legacy-epoch', clients: {solo: {sequence: 1}}};
  await new Promise((resolve, reject) => {
    const request = indexedDB.open(saveName(manifest.settings.id));
    request.onsuccess = () => {
      const db = request.result, transaction = db.transaction('authority', 'readwrite');
      transaction.objectStore('authority').put({format: 1, application: manifest.settings.id,
        contract: first.store.record(saved).contract, snapshot: legacy}, 'match');
      transaction.oncomplete = () => { db.close(); resolve(); }; transaction.onabort = () => reject(transaction.error);
    };
  });
  const active = await open();
  check(equal(active.local.snapshot(), saved), 'reopen changed authority');
  results.push('IndexedDB close/reopen restores actual Wasm state and revision');

  // A successful put can still be rolled back. Abort from its success listener,
  // before the transaction complete event that the adapter must await.
  const put = IDBObjectStore.prototype.put; let succeeded = false;
  IDBObjectStore.prototype.put = function (...args) {
    const request = put.apply(this, args);
    if (this.name === 'authority') request.addEventListener('success', () => { succeeded = true; this.transaction.abort(); });
    return request;
  };
  try { await rejects(() => active.command('pause-colony', [0]), /abort/i); }
  finally { IDBObjectStore.prototype.put = put; }
  check(succeeded, 'abort did not occur after actual put success');
  check(active.notices.length === 0 && active.local.revision === saved.revision, 'aborted commit published metadata/effects');
  check(equal(active.runtime.snapshot(1), saved.state) && equal(await active.store.load(), legacy), 'aborted write changed state');
  await active.command('pause-colony', [0]);
  check(active.local.revision === 2, 'failed save consumed revision or poisoned queue');
  results.push('put-success then transaction-abort rejects without publishing; following command commits');

  const beforeReset = await active.store.load(); await active.command('new-run');
  const reset = await active.store.load();
  check(reset.revision === beforeReset.revision + 1, 'reset did not atomically advance epoch/revision');
  check(reset.state[manifest.settings.runMarker] === beforeReset.state[manifest.settings.runMarker] + 1, 'reset marker was not saved');
  await active.close();
  const restored = await open();
  check(restored.local.revision === reset.revision && equal(restored.runtime.snapshot(1), reset.state), 'reset did not survive restart');
  await restored.close(); results.push('reset state and revision restore together');

  const other = structuredClone(manifest); other.settings.runMarker++;
  const incompatible = await openStore(other);
  await rejects(() => incompatible.load(), /incompatible/);
  await rejects(() => incompatible.commit({...reset, revision: reset.revision + 1}, reset.revision), /incompatible/);
  incompatible.close();
  const retained = await openStore(manifest);
  check(equal(await retained.load(), reset), 'incompatible package changed the save'); retained.close();
  results.push('incompatible load and commit retain the exact old record');

  const racing = structuredClone(manifest); racing.settings.id = `cas-test-${crypto.randomUUID()}`;
  const left = await openStore(racing), right = await openStore(racing);
  const candidates = [1, 2].map(value => ({revision: 1, state: [1, value]}));
  const outcomes = await Promise.allSettled([left.commit(candidates[0], 0), right.commit(candidates[1], 0)]);
  check(outcomes.filter(result => result.status === 'fulfilled').length === 1, 'CAS accepted two writers');
  check(outcomes.some(result => result.status === 'rejected' && /conflict/.test(result.reason.message)), 'CAS did not reject stale writer');
  const winner = outcomes[0].status === 'fulfilled' ? candidates[0] : candidates[1];
  check(equal(await left.load(), winner), 'CAS stored torn candidate'); left.close(); right.close();
  results.push('concurrent real IndexedDB connections compare and replace in one transaction');

  const newer = structuredClone(manifest); newer.settings.id = `version-test-${crypto.randomUUID()}`;
  const db = await new Promise((resolve, reject) => {
    const request = indexedDB.open(saveName(newer.settings.id), 2);
    request.onupgradeneeded = () => request.result.createObjectStore('future');
    request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
  });
  db.close(); await rejects(() => openStore(newer), /version/i);
  const intact = await new Promise(resolve => {
    const request = indexedDB.open(saveName(newer.settings.id)); request.onsuccess = () => resolve(request.result);
  });
  check(intact.version === 2 && intact.objectStoreNames.contains('future'), 'unsupported database was replaced'); intact.close();
  results.push('unsupported database version remains intact');
  return results;
}
