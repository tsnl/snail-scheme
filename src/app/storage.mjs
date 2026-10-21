// One save per application in IndexedDB: the bytes of its serialized state.

function open() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('lofi-applications', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('saves');
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function transaction(mode, use) {
  return open().then(database => new Promise((resolve, reject) => {
    const store = database.transaction('saves', mode).objectStore('saves');
    const request = use(store);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  }));
}

export function loadSave(key) {
  return transaction('readonly', store => store.get(key)).catch(() => undefined);
}

export function storeSave(key, bytes) {
  return transaction('readwrite', store => store.put(bytes, key));
}
