// One durable game record per origin/application. A generation or mount
// path never names a save; compatible deployments reopen the same record.
import {endpoint, protocolContract} from './runtime.mjs';

export function saveName(application) {
  if (typeof application !== 'string' || !/^[a-z][a-z0-9.-]{0,79}$/.test(application))
    throw new Error('settings.id must be a stable lowercase application identifier');
  return `snail.application:${application}`;
}
export function saveContract(manifest) {
  // Only match state is persisted. Adding a camera control must not invalidate
  // a colony; the in-memory runtime still checks the complete live protocol.
  const persistent = {...manifest, applications: manifest.applications.filter(app => app.owner === 'match')};
  return JSON.stringify([protocolContract(persistent), manifest.settings.runMarker ?? null,
    endpoint(manifest, 'match', manifest.settings.reset).id]);
}
function persistentContract(contract) {
  try {
    const [encoded, marker, reset] = JSON.parse(contract), protocol = JSON.parse(encoded);
    protocol.applications = protocol.applications.filter(app => app.owner === 'match');
    if (protocol.applications.length !== 1 || !Array.isArray(protocol.applications[0].handlers) ||
        !protocol.applications[0].handlers.every(handler => Array.isArray(handler) && typeof handler[0] === 'string')) return;
    return [protocol, marker, reset];
  } catch { return undefined; }
}
function acceptsSavedContract(saved, current) {
  const before = persistentContract(saved), after = persistentContract(current);
  if (!before || !after) return false;
  // A page refresh has no old commands in flight. New Match endpoints can read
  // the same save; every previous endpoint and the state/reset contract remain
  // exact. Live code replacement still uses the strict complete protocol.
  const retained = new Set(before[0].applications[0].handlers.map(handler => handler[0]));
  after[0].applications[0].handlers = after[0].applications[0].handlers.filter(handler => retained.has(handler[0]));
  return JSON.stringify(before) === JSON.stringify(after);
}
export function readRecord(record, application, contract) {
  if (record === undefined) return undefined;
  if (record?.format !== 1 || record.application !== application ||
      (record.contract !== contract && !acceptsSavedContract(record.contract, contract)))
    throw new Error('Saved game is incompatible with this package. Reopen the previous compatible package; the save has been retained.');
  if (!Number.isSafeInteger(record.snapshot?.revision) || record.snapshot.revision < 0)
    throw new Error('Invalid saved revision; the save has been retained.');
  return record.snapshot;
}

// The callback's unresolved promise owns the lock. No heartbeat or expiring
// localStorage flag can safely substitute for this browser-managed lifetime.
export async function acquireWriter(application) {
  if (!navigator.locks) throw new Error('Solo saves require Web Locks in a secure browser context (HTTPS or localhost).');
  let acquired, failed, release;
  const ready = new Promise((resolve, reject) => { acquired = resolve; failed = reject; });
  const held = new Promise(resolve => { release = resolve; });
  const finished = navigator.locks.request(`${saveName(application)}:writer`, {ifAvailable: true}, lock => {
    if (!lock) throw new Error('This solo save is open in another tab. Close that tab, then reload this page.');
    acquired(); return held;
  });
  finished.catch(failed);
  await ready;
  return async () => { release(); await finished; };
}

function openDatabase(name) {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(name, 1); let blocked = false;
    request.onupgradeneeded = event => {
      if (event.oldVersion === 0) request.result.createObjectStore('authority');
      else request.transaction.abort(); // Unknown layouts need an explicit migration.
    };
    request.onblocked = () => { blocked = true; reject(new Error('Save upgrade is blocked. Close other tabs and reload; no save was deleted.')); };
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      if (blocked) { request.result.close(); return; }
      request.result.onversionchange = () => request.result.close();
      resolve(request.result);
    };
  });
}
export async function openStore(manifest) {
  const application = manifest.settings.id, contract = saveContract(manifest);
  const db = await openDatabase(saveName(application));
  return {
    load() { return load(db, application, contract); },
    commit(snapshot, expected) { return commit(db, application, contract, snapshot, expected); },
    record(snapshot) { return {format: 1, application, contract, snapshot}; },
    failure() { return failureRecord(db); },
    recordFailure(failure) { return failureRecord(db, failure); },
    close() { db.close(); },
  };
}
function load(db, application, contract) {
  return new Promise((resolve, reject) => {
    const transaction = db.transaction('authority', 'readonly');
    const request = transaction.objectStore('authority').get('match');
    transaction.onabort = () => reject(transaction.error ?? new Error('Save read aborted'));
    transaction.oncomplete = () => {
      try { resolve(readRecord(request.result, application, contract)); }
      catch (error) { reject(error); }
    };
  });
}
function commit(db, application, contract, snapshot, expected) {
  // Materialize before opening the transaction; no await may separate get/put.
  const record = structuredClone({format: 1, application, contract, snapshot});
  if (!Number.isSafeInteger(expected) || expected < 0 || snapshot.revision !== expected + 1)
    return Promise.reject(new Error('invalid durable revision'));
  return new Promise((resolve, reject) => {
    const transaction = db.transaction('authority', 'readwrite', {durability: 'strict'});
    const store = transaction.objectStore('authority'), request = store.get('match'); let failure;
    transaction.oncomplete = () => resolve(); // put success alone is not durable.
    transaction.onabort = () => reject(failure ?? transaction.error ?? new Error('Save transaction aborted'));
    request.onsuccess = () => {
      try {
        const prior = readRecord(request.result, application, contract);
        // Revision zero is bootstrap: the first accepted command creates the record.
        if ((prior?.revision ?? 0) !== expected) throw new Error('durable revision conflict');
        store.put(record, 'match');
      } catch (error) { failure = error; transaction.abort(); }
    };
  });
}

// Keep one reproduction beside the save. A failed reducer never overwrites the
// committed match; diagnostics cannot change its revision or compatibility.
function failureRecord(db, failure) {
  return new Promise((resolve, reject) => {
    const transaction = db.transaction('authority', failure === undefined ? 'readonly' : 'readwrite');
    const store = transaction.objectStore('authority');
    const request = failure === undefined ? store.get('last-failure') : store.put(failure, 'last-failure');
    transaction.oncomplete = () => resolve(failure === undefined ? request.result : undefined);
    transaction.onabort = () => reject(transaction.error ?? new Error('Diagnostic write aborted'));
  });
}
