// One save per application in IndexedDB: the bytes of its serialized state.

import {span} from './trace.mjs';
import {blobPartSize, matchesDigest, readBlobParts} from './load.mjs';

function open(name, store) {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(name, 1);
    request.onupgradeneeded = () => request.result.createObjectStore(store);
    request.onsuccess = request.onerror = event => {
      request.onsuccess = request.onerror = request.onupgradeneeded = null;
      if (event.type === 'success') resolve(request.result);
      else reject(request.error);
    };
  });
}

async function transaction(name, store, mode, use) {
  const database = await open(name, store);
  try {
    return await new Promise((resolve, reject) => {
      const tx = database.transaction(store, mode);
      const request = use(tx.objectStore(store));
      tx.oncomplete = tx.onabort = event => {
        tx.oncomplete = tx.onabort = null;
        if (event.type === 'complete') resolve(request.result);
        else reject(tx.error ?? request.error);
      };
    });
  } finally { database.close(); }
}

export function loadSave(key) {
  return transaction('snail-applications', 'saves', 'readonly', store => store.get(key)).catch(() => undefined);
}

export async function storeSave(key, bytes) {
  const start = performance.now();
  try { return await transaction('snail-applications', 'saves', 'readwrite', store => store.put(bytes, key)); }
  finally { span('wait', 'store save', start); }
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
// Only complete, verified bytes enter Cache Storage.
const downloading = new Map();
const objects = 'snail-static-resources-v1';
const sizeHeader = 'x-snail-blob-size';

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
      const prefix = key + '/' + blobPartSize;
      for (let i = 1; i * blobPartSize < bytes.length; i++)
        await cache.put(prefix + '/' + i, new Response(bytes.subarray(i * blobPartSize, (i + 1) * blobPartSize)));
      await cache.put(prefix + '/0', new Response(bytes.subarray(0, blobPartSize), {headers: {[sizeHeader]: String(bytes.length)}}));
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
      const bytes = await readBlobParts(digest, length, async (_path, _length, _offset, index) => {
        const part = index === 0 ? first : await cache.match(key + '/' + index);
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
      if (await verified(bytes, digest, size)) return bytes;
      await cache.delete(key);
    }
    if (size === undefined || size > blobPartSize) return await cachedParts(cache, key + '/' + blobPartSize, digest, size);
  } catch { /* Storage may have been evicted or disabled. */ }
}

export async function readImmutable(digest, size, read, signal) {
  // Linked files, which carry no size, can still run over plain HTTP.
  // Verified acquisition requires Web Crypto. Insecure origins never commit
  // unchecked objects.
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
