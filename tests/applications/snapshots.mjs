// Inspect the public S-expression wire format in application tests. This reader
// knows records and scalar tags, but contains no Siegework field order or schema.
import assert from 'node:assert/strict';

function readSexp(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const decoder = new TextDecoder('utf-8', {fatal: true}); let at = 0;
  const integer = (width, signed = false) => {
    const methods = {1: signed ? 'getInt8' : 'getUint8', 2: signed ? 'getInt16' : 'getUint16',
      4: signed ? 'getInt32' : 'getUint32', 8: signed ? 'getBigInt64' : 'getBigUint64'};
    const value = view[methods[width]](at); at += width; return Number(value);
  };
  const text = length => { const value = decoder.decode(bytes.subarray(at, at + length)); at += length; return value; };
  const array = length => Array.from({length}, read);
  const symbol = length => { assert.equal(integer(1), 1); return {symbol: text(length)}; };
  function read() {
    const tag = integer(1);
    if (tag < 0x80) return tag;
    if (tag >= 0xe0) return tag - 256;
    if (tag >= 0x90 && tag < 0xa0) return array(tag - 0x90);
    if (tag >= 0xa0 && tag < 0xc0) return text(tag - 0xa0);
    if (tag >= 0xcc && tag <= 0xcf) return integer(2 ** (tag - 0xcc));
    if (tag >= 0xd0 && tag <= 0xd3) return integer(2 ** (tag - 0xd0), true);
    if (tag >= 0xd4 && tag <= 0xd8) return symbol(2 ** (tag - 0xd4));
    if (tag >= 0xc7 && tag <= 0xc9) return symbol(integer(2 ** (tag - 0xc7)));
    if (tag >= 0xd9 && tag <= 0xdb) return text(integer(2 ** (tag - 0xd9)));
    if (tag === 0xdc || tag === 0xdd) return array(integer(tag === 0xdc ? 2 : 4));
    throw new Error(`unexpected snapshot S-expression tag ${tag}`);
  }
  const result = read(); assert.equal(at, bytes.length); return result;
}

function recordValue(value) {
  const tag = value[0].symbol;
  if (tag === 'data') return Object.fromEntries(value.slice(3).map(([field, contents]) => [field.symbol, recordValue(contents)]));
  if (tag.startsWith('(List ')) return value[1].map(recordValue);
  if (tag === 'I32') return value[1];
  throw new Error(`unexpected application value type ${tag}`);
}

export function snapshotValue(words, {marked = false} = {}) {
  const header = marked ? 3 : 2, count = words[header - 1], bytes = new Uint8Array(count);
  assert.equal(words.length, header + Math.ceil(count / 4));
  for (let index = 0; index < count; index++) bytes[index] = words[header + (index >>> 2)] >>> ((index & 3) * 8);
  return recordValue(readSexp(bytes));
}
export const state = (runtime, owner = 1) => snapshotValue(runtime.snapshot(owner));

// Fixtures construct the documented wire values, then the real Scheme decoder
// checks them. This writer has no application rules or record field offsets.
function writeSexp(value, output) {
  const integer = (number, width) => {
    for (let byte = width - 1; byte >= 0; byte--) output.push((number / 2 ** (byte * 8)) & 255);
  };
  const sized = (count, tags) => {
    const width = count <= 255 ? 1 : count <= 65535 ? 2 : 4;
    output.push(tags[Math.log2(width)]); integer(count, width);
  };
  if (Array.isArray(value)) {
    if (value.length < 16) output.push(0x90 + value.length);
    else { output.push(value.length <= 65535 ? 0xdc : 0xdd); integer(value.length, value.length <= 65535 ? 2 : 4); }
    for (const item of value) writeSexp(item, output);
  } else if (Number.isInteger(value)) {
    if (value >= -32 && value <= 127) output.push(value & 255);
    else {
      const width = value >= 0 ? value <= 255 ? 1 : value <= 65535 ? 2 : 4 : value >= -128 ? 1 : value >= -32768 ? 2 : 4;
      output.push((value >= 0 ? 0xcc : 0xd0) + Math.log2(width)); integer(value >>> 0, width);
    }
  } else {
    const symbol = typeof value === 'object', bytes = new TextEncoder().encode(symbol ? value.symbol : value);
    if (symbol) { sized(bytes.length, [0xc7, 0xc8, 0xc9]); output.push(1); }
    else if (bytes.length < 32) output.push(0xa0 + bytes.length);
    else sized(bytes.length, [0xd9, 0xda, 0xdb]);
    output.push(...bytes);
  }
}
export function snapshotWords(schema, value, marker) {
  const bytes = []; writeSexp(value, bytes);
  const header = marker === undefined ? [schema, bytes.length] : [schema, marker, bytes.length];
  const words = Array(Math.ceil(bytes.length / 4)).fill(0);
  bytes.forEach((byte, index) => words[index >>> 2] |= byte << ((index & 3) * 8));
  return [...header, ...words];
}
