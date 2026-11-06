// One save per application in IndexedDB: the bytes of its serialized state.

function open() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('snail-applications', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('saves');
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function transaction(mode, use) {
  return open().then(database => new Promise((resolve, reject) => {
    const transaction = database.transaction('saves', mode);
    const request = use(transaction.objectStore('saves'));
    transaction.oncomplete = () => { database.close(); resolve(request.result); };
    transaction.onabort = () => { database.close(); reject(transaction.error ?? request.error); };
  }));
}

export function loadSave(key) {
  return transaction('readonly', store => store.get(key)).catch(() => undefined);
}

export function storeSave(key, bytes) {
  return transaction('readwrite', store => store.put(bytes, key));
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
