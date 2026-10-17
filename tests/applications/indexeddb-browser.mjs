// Executed in Chromium against its real IndexedDB and the packaged Scheme/Wasm.
function check(value, message) { if (!value) throw new Error(message); }
const equal = (left, right) => JSON.stringify(left) === JSON.stringify(right);
async function rejects(operation, pattern) {
  try { await operation(); } catch (error) { check(pattern.test(error.message), error.message); return; }
  throw new Error('expected rejection');
}
export async function checkIndexedDB(base) {
  const {ReducerRuntime} = await import(new URL('lib/application/runtime.mjs', base));
  const {Authority} = await import(new URL('lib/application/authority.mjs', base));
  const {openStore, saveName} = await import(new URL('lib/application/indexeddb.mjs', base));
  const manifest = await (await fetch(new URL('manifest.json', base))).json();
  manifest.settings.id = `storage-test-${crypto.randomUUID()}`;
  const bytes = new Uint8Array(await (await fetch(new URL(manifest.module, base))).arrayBuffer());
  async function open() {
    const runtime = new ReducerRuntime(), store = await openStore(manifest), notices = [];
    await runtime.replace(runtime.prepare(bytes, manifest)); await runtime.initialize(1); await runtime.initialize(2);
    const authority = await Authority.open(runtime, {saved: await store.load(),
      commit: (state, expected) => store.commit(state, expected), publish: value => notices.push(value), runMarker: manifest.settings.runMarker});
    const command = (binding, args = []) => authority.submit({client: 'solo', command: runtime.command('match', binding, args)}, {internal: true});
    return {runtime, store, authority, command, notices, close: async () => { await runtime.close(); store.close(); }};
  }
  const results = [], first = await open();
  check(await first.store.load() === undefined, 'fresh open should not fabricate a durable record');
  await first.command('pause-colony', [1]);
  const saved = await first.store.load(); await first.close();
  const active = await open();
  check(equal(active.authority.snapshot(), {revision: saved.revision, epoch: saved.epoch, state: saved.state}), 'reopen changed authority');
  check(equal(active.authority.clients, saved.clients), 'reopen lost receipt');
  results.push('IndexedDB close/reopen restores actual Wasm state, epoch and receipts');

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
  check(active.notices.length === 0 && active.authority.revision === saved.revision, 'aborted commit published metadata/effects');
  check(equal(active.runtime.snapshot(1), saved.state) && equal(await active.store.load(), saved), 'aborted write changed state');
  await active.command('pause-colony', [0]);
  check(active.authority.clients.solo.sequence === 2, 'failed save consumed receipt or poisoned queue');
  results.push('put-success then transaction-abort rejects without publishing; following command commits');

  const beforeReset = await active.store.load(); await active.command('new-run');
  const reset = await active.store.load();
  check(reset.epoch !== beforeReset.epoch && reset.revision === beforeReset.revision + 1, 'reset did not atomically advance epoch/revision');
  check(reset.clients.solo.receipt.epoch === reset.epoch && reset.state[manifest.settings.runMarker] === beforeReset.state[manifest.settings.runMarker] + 1, 'reset record split metadata/state');
  await active.close();
  const restored = await open();
  check(restored.authority.epoch === reset.epoch && equal(restored.runtime.snapshot(1), reset.state), 'reset did not survive restart');
  await restored.close(); results.push('reset epoch, marker and receipt restore together');

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
  const candidates = ['left', 'right'].map(epoch => ({...reset, revision: 1, epoch}));
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
