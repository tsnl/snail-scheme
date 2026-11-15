// Native file capability for Node. Pending operations own ordinary host data;
// only finish copies a completed buffer into the language's managed Bytes.
import {constants} from 'node:fs';
import {open} from 'node:fs/promises';

const maximumLimit = 16 * 1024 * 1024;
const failure = error => error.code === 'ENOENT' ? -4
  : error.code === 'EACCES' || error.code === 'EPERM' ? -5 : -6;

async function readBounded(path, limit, canceled) {
  if (limit < 0 || limit > maximumLimit || path.includes('\0')) return {code: -2};
  let file, result;
  try {
    file = await open(path, constants.O_RDONLY | (constants.O_NONBLOCK ?? 0));
    result = await readContents(file, limit, canceled);
  } catch (error) { result = {code: failure(error)}; }
  try { await file?.close(); }
  catch (error) { result = {code: failure(error)}; }
  return result;
}

async function readContents(file, limit, canceled) {
  const bytes = new Uint8Array(limit + 1);
  let used = 0;
  while (!canceled()) {
    const {bytesRead} = await file.read(bytes, used, bytes.length - used, used);
    used += bytesRead;
    if (used > limit) return {code: -3};
    if (!bytesRead) return {bytes: bytes.slice(0, used)};
  }
  return {code: -6};
}

export function createAsyncFiles(tasks) {
  const pending = new Map();
  let path = '', next = 0n, held = new Uint8Array(), closed = false;
  const imports = {
    'path-character'(code) { path += String.fromCodePoint(code); },
    'start-read'(ticket, maximum) {
      if (closed) throw new Error('native file provider is closed');
      const name = path; path = '';
      if (next === 0x7fffffffffffffffn) throw new Error('file request IDs exhausted');
      const id = ++next, request = {ticket: Number(ticket), canceled: false};
      pending.set(id, request);
      tasks.start(request.ticket,
        signal => (request.operation = readBounded(name, maximum, () => request.canceled || signal.aborted)),
        result => result, () => pending.delete(id));
      return id;
    },
    finish(id) {
      const request = pending.get(id);
      if (!request || request.canceled) throw new Error('file result is not owned');
      const result = tasks.finish(request.ticket);
      pending.delete(id);
      held = result.bytes ?? new Uint8Array();
      return result.code ?? held.length;
    },
    byte(index) {
      if (index < 0 || index >= held.length) throw new Error('file result byte is out of range');
      return held[index];
    },
  };
  return {imports, async close() {
    closed = true;
    for (const request of pending.values()) request.canceled = true;
    await Promise.all([...pending.values()].map(request => request.operation));
  }};
}
