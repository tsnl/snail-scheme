// One save per application in IndexedDB: the bytes of its serialized state.

function open(name, store) {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(name, 1);
    request.onupgradeneeded = () => request.result.createObjectStore(store);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function transaction(name, store, mode, use) {
  return open(name, store).then(database => new Promise((resolve, reject) => {
    const transaction = database.transaction(store, mode);
    const request = use(transaction.objectStore(store));
    transaction.oncomplete = () => { database.close(); resolve(request.result); };
    transaction.onabort = () => { database.close(); reject(transaction.error ?? request.error); };
  }));
}

export function loadSave(key) {
  return transaction('snail-applications', 'saves', 'readonly', store => store.get(key)).catch(() => undefined);
}

export function storeSave(key, bytes) {
  return transaction('snail-applications', 'saves', 'readwrite', store => store.put(bytes, key));
}

// Session saves are isolated by tab and survive navigation on this origin.
// Read failures propagate: an unavailable or corrupt recovery record must not
// be mistaken for an empty application and overwritten.
export function loadSessionSave(key) {
  const text = sessionStorage.getItem(`snail-save:${key}`);
  return text === null ? undefined : Uint8Array.from(atob(text), char => char.charCodeAt(0));
}

export function storeSessionSave(key, bytes) {
  sessionStorage.setItem(`snail-save:${key}`, btoa(Array.from(bytes, byte => String.fromCharCode(byte)).join('')));
}

// Each immutable build object is shared by its SHA-256 across games on this origin.
// On secure origins verify a completed response before letting it enter the store.
const downloading = new Map();

async function storedObject(digest, read) {
  const fromDisk = () => transaction('snail-linked-files', 'objects', 'readonly', store => store.get(digest)).catch(() => undefined);
  async function download() {
    const saved = await fromDisk();
    if (saved instanceof Uint8Array) return saved;
    const bytes = await read();
    if (globalThis.crypto?.subtle) {
      const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
      if (Array.from(hash, byte => byte.toString(16).padStart(2, '0')).join('') !== digest)
        throw new Error(`linked file did not match SHA-256 ${digest}`);
    }
    await transaction('snail-linked-files', 'objects', 'readwrite', store => store.put(bytes, digest)).catch(() => {});
    return bytes;
  }
  // A second tab checks storage after the first tab commits its download.
  if (!globalThis.navigator?.locks) return download();
  let entered = false;
  try {
    return await navigator.locks.request('snail-file-' + digest, () => { entered = true; return download(); });
  } catch (error) {
    if (entered) throw error;
    return download();
  }
}

export function readLinkedFile(digest, read) {
  if (!downloading.has(digest))
    downloading.set(digest, storedObject(digest, read).finally(() => downloading.delete(digest)));
  return downloading.get(digest);
}
