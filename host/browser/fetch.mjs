// The page's `fetch` and `EventSource` for the `fetch` effect of
// src/snail/shell/fetch.sld, as `with-page-fetch` in
// src/snail/shell/fetch/page.sld calls it. A request and a stream's next
// event are host operations of the task that asked (tasks.mjs), which the
// run's signal aborts when the program stops. A stream keeps what arrives
// between waits, and a dropped connection reconnects, as EventSource does,
// which a stream that hears "error" hears as an event without data.

import {byteSnapshot} from './load.mjs';

export function createFetch(runtime) {
  const decoder = new TextDecoder();
  let parts, streams, nextStream, reply = [];
  reset();

  // A program that starts knows no streams, so they close with the last.
  function reset() {
    for (const stream of streams?.values() ?? []) stream.source.close();
    streams = new Map();
    nextStream = 1;
    parts = {method: 'GET', url: '', headers: [], body: ''};
  }
  const text = address => decoder.decode(byteSnapshot(runtime.execution.entry.memory, address));
  const tasks = () => runtime.execution.tasks;
  // The text a finished wait leaves, read a scalar at a time.
  function answer(value) {
    reply = [...value];
    return reply.length;
  }

  // ---- Requests ----

  // A GET or HEAD has no body to send.
  function start(ticket) {
    const {method, url, headers, body} = parts;
    parts = {method: 'GET', url: '', headers: [], body: ''};
    tasks().start(Number(ticket), async signal => {
      try {
        const response = await fetch(url, {method, headers, signal, body: method === 'GET' || method === 'HEAD' ? undefined : body});
        return {status: response.status, text: await response.text()};
      } catch (error) {
        if (signal.aborted) throw error;
        return {status: -1, text: error.message};
      }
    }, ({status, text}) => { answer(text); return status; });
  }

  // ---- Streams ----

  // The URL, then the kinds of event it hears, a NUL between each.
  function open(description) {
    const [url, ...kinds] = description.split('\0');
    const stream = {source: new EventSource(url), messages: [], closed: false, waiter: null};
    const heard = message => { stream.messages.push(message); stream.waiter?.(); };
    for (const kind of kinds.filter(kind => kind !== 'error')) stream.source.addEventListener(kind, event => heard(`${kind}\0${event.data}`));
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
