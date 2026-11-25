// One save per application in IndexedDB: the bytes of its serialized state.

import {blobPartSize, matchesDigest, readBlobParts} from './load.mjs';

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

// Immutable bodies share a digest key across applications on this origin.
// Only complete, verified bytes enter Cache Storage. Older builds kept the
// same bytes under the same digest in IndexedDB.
const downloading = new Map();
const objects = 'snail-static-resources-v1';
const sizeHeader = 'x-snail-blob-size';
const legacy = (mode, use) => transaction('snail-linked-files', 'objects', mode, use);

async function verified(bytes, digest, size) {
  if (!(bytes instanceof Uint8Array) || (size !== undefined && bytes.length !== size)) return false;
  return matchesDigest(bytes, digest);
}

async function put(cache, key, bytes) {
  if (!cache) return false;
  try {
    if (bytes.length <= blobPartSize) await cache.put(key, new Response(bytes));
    else {
      // Part zero commits the complete set. A failed cache write can be retried.
      for (let i = 1; i * blobPartSize < bytes.length; i++)
        await cache.put(key + '/' + i, new Response(bytes.subarray(i * blobPartSize, (i + 1) * blobPartSize)));
      await cache.put(key + '/0', new Response(bytes.subarray(0, blobPartSize), {headers: {[sizeHeader]: String(bytes.length)}}));
    }
    return true;
  }
  catch { return false; } // Quota and private-mode failures leave the bytes usable.
}

async function cachedParts(cache, key, digest, size) {
  const first = await cache?.match(key + '/0');
  if (!first) return;
  const length = Number(first.headers.get(sizeHeader));
  try {
    if (size === undefined || size === length) {
      const bytes = await readBlobParts(digest, length, async (_path, _length, offset) => {
        const part = offset === 0 ? first : await cache.match(key + '/' + offset / blobPartSize);
        if (!part) throw new Error('cached part missing');
        return new Uint8Array(await part.arrayBuffer());
      });
      if (await matchesDigest(bytes, digest)) return bytes;
    }
  } catch { /* A missing or truncated part makes the set a cache miss. */ }
  await cache.delete(key + '/0');
}

async function cachedBytes(cache, key, digest, size) {
  try {
    const response = await cache?.match(key);
    if (response) {
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (await verified(bytes, digest, size)) {
        if (bytes.length > blobPartSize && await put(cache, key, bytes)) await cache.delete(key).catch(() => {});
        return bytes;
      }
      await cache.delete(key);
    }
    if (size === undefined || size > blobPartSize) {
      const bytes = await cachedParts(cache, key, digest, size);
      if (bytes) return bytes;
    }
  } catch { /* Storage may have been evicted or disabled. */ }
  const old = await legacy('readonly', store => store.get(digest)).catch(() => undefined);
  if (!old) return;
  const valid = await verified(old, digest, size);
  if (!valid || await put(cache, key, old))
    await legacy('readwrite', store => store.delete(digest)).catch(() => {});
  if (valid) return old;
}

export async function readImmutable(digest, size, read, signal) {
  // Legacy linked files can still run over plain HTTP. Verified acquisition
  // requires Web Crypto. Insecure origins never commit unchecked objects.
  if (!globalThis.crypto?.subtle) {
    if (size !== undefined) throw new Error('verified resources need HTTPS or localhost');
    return read();
  }
  async function acquire() {
    let cache;
    try { cache = await globalThis.caches?.open(objects); } catch {}
    const key = cache && new URL('/.snail/sha256/' + digest, location.href).href;
    const saved = await cachedBytes(cache, key, digest, size);
    signal?.throwIfAborted();
    if (saved) return saved;
    const bytes = await read();
    if (!await verified(bytes, digest, size)) throw new Error('file did not match SHA-256 ' + digest);
    signal?.throwIfAborted();
    await put(cache, key, bytes);
    return bytes;
  }
  if (!globalThis.navigator?.locks) return acquire();
  let entered = false;
  try {
    return await navigator.locks.request('snail-file-' + digest, signal ? {signal} : {}, () => {
      entered = true;
      return acquire();
    });
  } catch (error) {
    if (entered || signal?.aborted) throw error;
    return acquire();
  }
}

export function readLinkedFile(digest, read) {
  if (!downloading.has(digest))
    downloading.set(digest, readImmutable(digest, undefined, read).finally(() => downloading.delete(digest)));
  return downloading.get(digest);
}
