// The page's `fetch` and `EventSource` for the `Fetch` capability of
// src/snail/shell/fetch.sld, as `with-page-fetch` in
// src/snail/shell/fetch/page.sld calls it. A request and a stream's next
// event are host operations of the task that asked (tasks.mjs), which the
// run's signal aborts when the program stops. A stream keeps what arrives
// between waits, and a dropped connection reconnects, as EventSource does,
// which a stream that hears "error" hears as an event without data.

import {blobPartSize, legacyPartSize, byteView, objectPath, readBlobParts} from './load.mjs';
import {readImmutable} from './storage.mjs';

// Count decoded response bytes, the same representation the publisher hashed.
// The catalog gives the length even when HTTP compresses or omits it.
export async function downloadStatic(url, size, signal, progress) {
  const response = await fetch(url, {signal, cache: 'no-store'});
  if (!response.ok) throw Object.assign(new Error(`${response.status} fetching ${url}`), {status: response.status});
  const reader = response.body?.getReader();
  const bytes = new Uint8Array(size);
  let received = 0;
  if (reader) {
    try {
      for (;;) {
        const {value, done} = await reader.read();
        if (done) break;
        if (value.length > size - received) throw new Error('response exceeds its published byte length');
        bytes.set(value, received);
        received += value.length;
        progress(received);
      }
    } catch (error) {
      await reader.cancel().catch(() => {});
      throw error;
    } finally { reader.releaseLock(); }
  }
  if (received !== size) throw new Error(`expected ${size} bytes, received ${received}`);
  return bytes;
}

// Catalogs describe the whole object. Try its current address first. Only
// a 404 before any bytes permits an older widthless or whole-object layout.
async function downloadObject(base, digest, size, signal, progress) {
  const layouts = size > blobPartSize ? [blobPartSize, legacyPartSize, 0]
    : size > legacyPartSize ? [0, legacyPartSize] : [0];
  for (const width of layouts) {
    let first = true;
    try {
      if (width === 0) return await downloadStatic(new URL(objectPath(digest), base), size, signal, progress);
      return await readBlobParts(digest, size, async (path, length, offset) => {
        const part = await downloadStatic(new URL(path, base), length, signal, n => progress(offset + n));
        first = false;
        return part;
      }, width);
    } catch (error) {
      if (!first || error.status !== 404 || width === layouts.at(-1)) throw error;
    }
  }
}

export function createFetch(runtime) {
  const decoder = new TextDecoder();
  let parts, streams, nextStream, received, reply = [], bytes = new Uint8Array();
  reset();

  // A program that starts knows no streams, so they close with the last.
  function reset() {
    for (const stream of streams?.values() ?? []) stream.source.close();
    streams = new Map();
    received = new Map();
    nextStream = 1;
    parts = {method: 'GET', url: '', headers: [], body: ''};
  }
  const text = address => decoder.decode(byteView(runtime.execution.entry.memory, address));
  const tasks = () => runtime.execution.tasks;
  // The text a finished wait leaves, read a scalar at a time.
  function answer(value) {
    reply = [...value];
    return reply.length;
  }

  // ---- Requests ----

  // A GET is fetch's default request, so it goes without a method, as a
  // page's own reads do; a GET or HEAD has no body to send.
  function start(ticket) {
    const {method, url, headers, body} = parts;
    parts = {method: 'GET', url: '', headers: [], body: ''};
    const init = method === 'GET' ? {headers} : {method, headers, body: method === 'HEAD' ? undefined : body};
    tasks().start(Number(ticket), async signal => {
      try {
        const response = await fetch(url, {...init, signal});
        return {status: response.status, text: await response.text()};
      } catch (error) {
        if (signal.aborted) throw error;
        return {status: -1, text: error.message};
      }
    }, ({status, text}) => { answer(text); return status; });
  }

  // A GET whose body is read as bytes; a status other than OK is a reason.
  function startBytes(ticket) {
    const {url} = parts;
    parts = {method: 'GET', url: '', headers: [], body: ''};
    tasks().start(Number(ticket), async signal => {
      try {
        const response = await fetch(url, {signal});
        if (!response.ok) return {failed: `${response.status} fetching ${url}`};
        return {body: new Uint8Array(await response.arrayBuffer())};
      } catch (error) {
        if (signal.aborted) throw error;
        return {failed: error.message};
      }
    }, ({failed, body}) => {
      if (failed !== undefined) return (answer(failed), -1);
      bytes = body;
      return body.length;
    });
  }

  // ---- Streams ----

  // The URL, then the kinds of event it hears, a NUL between each.
  function open(description) {
    const [url, ...kinds] = description.split('\0');
    const stream = {source: new EventSource(url), messages: [], closed: false, waiter: null};
    const heard = message => { stream.messages.push(message); stream.waiter?.(); };
    for (const kind of kinds.filter(kind => kind !== 'error')) stream.source.addEventListener(kind, event => heard(`${kind}\0${event.data ?? ''}`));
    stream.source.addEventListener('error', () => {
      if (stream.source.readyState === EventSource.CLOSED) { stream.closed = true; stream.waiter?.(); }
      else if (kinds.includes('error')) heard('error\0');
    });
    streams.set(nextStream, stream);
    return nextStream++;
  }
  // The next event, its kind and data, or null once the stream is closed
  // and drained.
  function next(stream, signal) {
    return new Promise((resolve, reject) => {
      const settle = () => {
        if (stream.messages.length) resolve(stream.messages.shift());
        else if (stream.closed) resolve(null);
        else return;
        stream.waiter = null;
      };
      stream.waiter = settle;
      signal.addEventListener('abort', () => reject(signal.reason), {once: true});
      settle();
    });
  }
  function close(id) {
    const stream = streams.get(id);
    if (!stream) return;
    stream.source.close();
    stream.closed = true;
    stream.waiter?.();
    streams.delete(id);
  }

  // A ticket owns its progress until its fetch settles. The Scheme task can
  // sample it while waiting. finish-request exposes either bytes or an error.
  function startStatic(ticket, size, address) {
    const id = Number(ticket), digest = text(address), counts = received;
    const catalog = new URL(parts.url, document.baseURI);
    parts = {method: 'GET', url: '', headers: [], body: ''};
    counts.set(id, 0);
    tasks().start(id, async signal => {
      let cached = true;
      try {
        const body = await readImmutable(digest, size, () => {
          cached = false;
          return downloadObject(catalog, digest, size, signal, n => counts.set(id, n));
        }, signal);
        return {body, cached};
      } catch (error) {
        signal.throwIfAborted();
        return {failed: error.message};
      } finally { counts.delete(id); }
    }, result => {
      if (result.failed !== undefined) { answer(result.failed); return -1; }
      bytes = result.body;
      return result.cached ? 1 : 0;
    });
  }

  const imports = {
    'request-method': address => { parts.method = text(address); },
    'request-url': address => { parts.url = text(address); },
    'request-header'(address) {
      const header = text(address), end = header.indexOf('\0');
      parts.headers.push([header.slice(0, end), header.slice(end + 1)]);
    },
    'request-body': address => { parts.body = text(address); },
    'start-request': start,
    'finish-request': ticket => tasks().finish(Number(ticket)),
    'start-bytes': startBytes,
    'start-static': startStatic,
    'static-received': ticket => received.get(Number(ticket)) ?? -1,
    'reply-byte': index => bytes[index],
    'page-address': () => answer(globalThis.location?.href ?? ''),
    'stream-open': address => open(text(address)),
    'stream-start'(ticket, id) {
      const stream = streams.get(id) ?? {messages: [], closed: true, waiter: null};
      tasks().start(Number(ticket), signal => next(stream, signal), message => (message === null ? (answer(''), -1) : answer(message)));
    },
    'stream-finish': ticket => tasks().finish(Number(ticket)),
    'stream-close': close,
    'reply-count': () => reply.length,
    'reply-scalar': index => reply[index].codePointAt(0),
  };
  return {imports, reset};
}
