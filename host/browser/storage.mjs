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
