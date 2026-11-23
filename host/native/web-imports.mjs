// The native web boundary, src/snail/runtime/native/web.sld, over Node's
// fetch, answered as socket-imports.mjs answers. The length of the file at
// a URL comes from a HEAD request, and a part of it from a GET with a
// Range, which the server must answer with exactly those bytes: status
// 206, the range asked for in its Content-Range, and that many bytes. A
// server that answers a part with the whole file is refused before its
// body comes, so reading a part of a large file never fetches the rest.
import {stagedStrings} from '../browser/load.mjs';
import {heldAnswers} from './answers.mjs';

const fault = code => Object.assign(new Error(code), {code});

// The bytes as the server keeps them: a compressed answer would not have
// the length a part asks for.
const identity = {'Accept-Encoding': 'identity'};

// A failure of the network, whether before the answer or while its body
// arrives, as its code; an abort is the caller's own.
async function network(signal, operation) {
  try { return await operation(); }
  catch (error) {
    if (signal.aborted) throw error;
    const code = error.cause?.code;
    throw fault(typeof code === 'string' && /^[A-Z][A-Z0-9_]*$/.test(code) ? code : 'EFETCH');
  }
}

const requested = (url, options) =>
  network(options.signal, () => fetch(url, {...options, headers: {...identity, ...options.headers}}));

async function size(signal, url) {
  const response = await requested(url, {method: 'HEAD', signal});
  if (!response.ok) throw fault(`HTTP_${response.status}`);
  const length = response.headers.get('content-length');
  if (length === null || !/^[0-9]+$/.test(length)) throw fault('NO_LENGTH');
  return Number(length);
}

async function part(signal, url, start, count) {
  const range = `${start}-${start + count - 1n}`;
  const response = await requested(url, {headers: {Range: `bytes=${range}`}, signal});
  const answered = response.headers.get('content-range') ?? '';
  if (response.status !== 206 || !answered.startsWith(`bytes ${range}/`)) {
    await response.body?.cancel();
    throw fault(!response.ok ? `HTTP_${response.status}` : response.status === 206 ? 'WRONG_PART' : 'NO_RANGES');
  }
  const bytes = new Uint8Array(await network(signal, () => response.arrayBuffer()));
  if (BigInt(bytes.length) !== count) throw fault('WRONG_PART');
  return bytes;
}

export function webImports(tasks) {
  const {start, imports} = heldAnswers(tasks);
  const url = stagedStrings();
  const taken = () => url.take().at(-1);
  return {
    ...imports,
    ...url.imports,
    // A length may pass 2^32, so it crosses as an I64.
    'held-number': () => BigInt(imports['held-number']()),
    'start-size'(ticket) {
      const address = taken();
      start(ticket, signal => size(signal, address), length => ({number: length}));
    },
    'start-part'(ticket, first, count) {
      const address = taken();
      start(ticket, signal => part(signal, address, first, count), bytes => ({strings: [bytes]}));
    },
  };
}
