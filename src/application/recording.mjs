// A bounded history of published World banks. Banks belong to the runtime and
// never mutate after publication; only the latest one is retained for diffing.
import {validateManifest, parseCommand, protocolContract} from './runtime.mjs';

const encoder = new TextEncoder(), decoder = new TextDecoder('utf-8', {fatal: true});
const magic = encoder.encode('SNLRUN01');
const littleEndian = new Uint8Array(Int32Array.of(1).buffer)[0] === 1;
export const recordingLimits = Object.freeze({bytes: 64 * 1024 * 1024, entries: 12000,
  chunk: 128, words: 1048576, fileBytes: 72 * 1024 * 1024, metadataBytes: 65536});
const integer = (value, minimum, maximum) => Number.isSafeInteger(value) && value >= minimum && value <= maximum;
function requireValue(condition, message = 'Invalid recording dump') { if (!condition) throw new Error(message); }
const jsonBytes = value => encoder.encode(JSON.stringify(value));
const readJSON = bytes => JSON.parse(decoder.decode(bytes));

// ---- Packed word changes, including shifts in variable-length serialization ----

export function encodeChange(before, after) {
  let prefix = 0, suffix = 0, changed = 0;
  while (prefix < Math.min(before.length, after.length) && before[prefix] === after[prefix]) prefix++;
  while (suffix < Math.min(before.length, after.length) - prefix
      && before[before.length - 1 - suffix] === after[after.length - 1 - suffix]) suffix++;
  if (before.length === after.length)
    for (let i = prefix; i < after.length - suffix; i++) if (before[i] !== after[i]) changed++;
  const sparse = before.length === after.length && 1 + changed * 2 < 3 + after.length - prefix - suffix;
  return sparse ? sparseChange(before, after, changed) : spliceChange(after, prefix, suffix);
}
function sparseChange(before, after, changed) {
  const data = new Int32Array(1 + changed * 2); data[0] = after.length; let at = 1;
  for (let i = 0; i < after.length; i++) if (before[i] !== after[i]) { data[at++] = i; data[at++] = after[i]; }
  return {encoding: 2, data};
}
function spliceChange(after, prefix, suffix) {
  const data = new Int32Array(3 + after.length - prefix - suffix);
  data.set([after.length, prefix, suffix]); data.set(after.subarray(prefix, after.length - suffix), 3);
  return {encoding: 1, data};
}
export function applyChange(before, {encoding, data}) {
  if (encoding === 0) { requireValue(data.length > 0 && data.length <= recordingLimits.words); return data.slice(); }
  requireValue([1, 2].includes(encoding) && before && integer(data[0], 1, recordingLimits.words));
  return encoding === 1 ? applySplice(before, data) : applySparse(before, data);
}
function applySplice(before, data) {
  const [length, prefix, suffix] = data;
  requireValue(data.length >= 3 && integer(prefix, 0, before.length) && integer(suffix, 0, before.length - prefix));
  requireValue(prefix + suffix <= length && data.length - 3 === length - prefix - suffix);
  const result = new Int32Array(length); result.set(before.subarray(0, prefix));
  result.set(data.subarray(3), prefix); result.set(before.subarray(before.length - suffix), length - suffix); return result;
}
function applySparse(before, data) {
  requireValue(data.length % 2 === 1 && data[0] === before.length);
  let previous = -1;
  for (let i = 1; i < data.length; i += 2) {
    requireValue(integer(data[i], previous + 1, before.length - 1)); previous = data[i];
  }
  const result = before.slice();
  for (let i = 1; i < data.length; i += 2) result[data[i]] = data[i + 1]; return result;
}

// ---- Retention: whole chunks keep their own independent starting bank ----

export class RunRecording {
  #chunks = []; #previous; #sequence = 0; #bytes = 0; #count = 0; #started = performance.now();
  #revision; #generation; #run; #enabled = true;
  constructor(manifest, {revision = () => null, bytes = recordingLimits.bytes, entries = recordingLimits.entries} = {}) {
    requireValue(integer(bytes, 1024, recordingLimits.bytes) && integer(entries, 1, recordingLimits.entries), 'Invalid recording limits');
    this.manifest = manifest; this.maximumBytes = bytes; this.maximumEntries = entries; this.#revision = revision;
    this.startedAt = new Date().toISOString(); this.dropped = 0; this.reason = '';
  }
  static start(runtime, options) {
    const recording = new RunRecording(runtime.manifest, options);
    recording.capture(runtime, {kind: 'checkpoint', command: null, effects: []}); return recording;
  }
  get enabled() { return this.#enabled; }
  get length() { return this.#count; }
  get first() { return this.#chunks[0]?.entries[0].sequence; }
  get last() { return this.#chunks.at(-1)?.entries.at(-1).sequence; }
  get bytes() { return this.#bytes; }
  stop() { this.#enabled = false; this.#previous = undefined; this.reason = 'Stopped; later commits are not recorded.'; }
  fail(message) { this.stop(); this.reason = `Recording stopped: ${String(message).slice(0, 240)}`; }
  resume(runtime) {
    if (this.#enabled) return;
    this.#enabled = true; this.reason = ''; this.capture(runtime, {kind: 'checkpoint', command: null, effects: []});
  }
  capture(runtime, event) {
    if (!this.#enabled) return;
    requireValue(event.effects.length <= 1024, 'Recording event has too many effects');
    const words = runtime.stores.get(1), generation = runtime.manifest.generation;
    const run = this.manifest.settings.runMarker === undefined ? null : words[this.manifest.settings.runMarker];
    const boundary = !this.#previous || event.kind !== 'commit' || generation !== this.#generation || run !== this.#run;
    const metadata = jsonBytes({persisted: false, ...event, sequence: this.#sequence, elapsed: Math.round(performance.now() - this.#started),
      revision: this.#revision(), generation, run});
    requireValue(metadata.length <= recordingLimits.metadataBytes, 'Recording event metadata is too large');
    this.#append(words, metadata, boundary); this.#sequence++;
    this.#previous = words; this.#generation = generation; this.#run = run;
  }
  #append(words, metadata, boundary) {
    let chunk = this.#chunks.at(-1), keyframe = boundary || !chunk || chunk.entries.length === Math.min(recordingLimits.chunk, this.maximumEntries);
    let patch = keyframe ? {encoding: 0, data: words.slice()} : encodeChange(this.#previous, words);
    // A busy chunk closes early; never retain a delta without its keyframe.
    if (!keyframe && (patch.data.byteLength >= words.byteLength
        || chunk.bytes + patch.data.byteLength + metadata.byteLength + 12 > this.maximumBytes)) {
      keyframe = true; patch = {encoding: 0, data: words.slice()};
    }
    const entry = {...patch, metadata, sequence: this.#sequence}, bytes = entry.data.byteLength + metadata.byteLength + 12;
    requireValue(bytes <= this.maximumBytes, 'A World checkpoint exceeds the recording memory limit');
    if (keyframe) { chunk = {entries: [], bytes: 0}; this.#chunks.push(chunk); }
    chunk.entries.push(entry); chunk.bytes += bytes; this.#count++; this.#bytes += bytes; this.#trim();
  }
  #trim() {
    while (this.#chunks.length > 1 && (this.#bytes > this.maximumBytes || this.#count > this.maximumEntries)) {
      const removed = this.#chunks.shift(); this.#bytes -= removed.bytes; this.#count -= removed.entries.length;
      this.dropped += removed.entries.length;
    }
  }
  #find(sequence) {
    requireValue(Number.isSafeInteger(sequence), 'Choose a recording entry');
    const chunk = this.#chunks.find(value => sequence >= value.entries[0].sequence && sequence <= value.entries.at(-1).sequence);
    requireValue(chunk, 'Recording entry was not retained'); return chunk;
  }
  entry(sequence) {
    return readJSON(this.#find(sequence).entries.find(value => value.sequence === sequence).metadata);
  }
  snapshot(sequence) {
    let words;
    for (const entry of this.#find(sequence).entries) {
      words = applyChange(words, entry); if (entry.sequence === sequence) return words;
    }
  }
  *frames() {
    for (const chunk of this.#chunks) {
      let words;
      for (const entry of chunk.entries) { words = applyChange(words, entry); yield {entry: readJSON(entry.metadata), words}; }
    }
  }
  stats() {
    let wordBytes = 0, metadataBytes = 0;
    for (const chunk of this.#chunks) for (const entry of chunk.entries) {
      wordBytes += entry.data.byteLength; metadataBytes += entry.metadata.byteLength;
    }
    return {entries: this.length, chunks: this.#chunks.length, first: this.first, last: this.last, dropped: this.dropped,
      wordBytes, metadataBytes, framingBytes: this.length * 12, latestBankBytes: this.#previous?.byteLength ?? 0,
      maximumBytes: this.maximumBytes, enabled: this.enabled, reason: this.reason};
  }

  // Binary words avoid decimal JSON arrays and their large temporary heaps.
  // Blob snapshots the private buffers synchronously. Export does not first
  // duplicate every word buffer, and callers cannot mutate retained history.
  exportBlob() {
    const header = jsonBytes({format: 1, manifest: this.manifest, startedAt: this.startedAt,
      dropped: this.dropped, count: this.length, maximumBytes: this.maximumBytes, reason: this.reason});
    requireValue(header.length <= recordingLimits.metadataBytes, 'Recording manifest is too large to export');
    const prefix = new Uint8Array(12); prefix.set(magic); new DataView(prefix.buffer).setUint32(8, header.length, true);
    const parts = [prefix, header];
    for (const chunk of this.#chunks) for (const entry of chunk.entries) parts.push(...encodeFrame(entry));
    return new Blob(parts, {type: 'application/octet-stream'});
  }
  static import(buffer) {
    const parsed = parseDump(buffer);
    return RunRecording.#fromParsed(parsed);
  }
  static #fromParsed(parsed) {
    const result = new RunRecording(parsed.header.manifest, {bytes: parsed.header.maximumBytes});
    result.#chunks = parsed.chunks; result.#bytes = parsed.bytes; result.#count = parsed.header.count;
    result.#sequence = parsed.last + 1; result.#previous = undefined; result.#enabled = false;
    result.startedAt = parsed.header.startedAt; result.dropped = parsed.header.dropped;
    result.reason = parsed.header.reason || 'Imported recording; read-only.'; return result;
  }
}

// ---- A bounded binary reader establishes a replayable chain before exposure ----

function encodeFrame(entry) {
  const header = new Uint8Array(12), view = new DataView(header.buffer);
  view.setUint32(0, entry.metadata.length, true); view.setUint32(4, entry.data.length, true); view.setUint32(8, entry.encoding, true);
  return [header, entry.metadata, encodeWords(entry.data)];
}
function encodeWords(data) {
  if (littleEndian) return data;
  const bytes = new Uint8Array(data.byteLength), words = new DataView(bytes.buffer);
  for (let i = 0; i < data.length; i++) words.setInt32(i * 4, data[i], true); return bytes;
}
function parseHeader(bytes, view) {
  requireValue(bytes.length >= 12 && magic.every((value, i) => bytes[i] === value));
  const length = view.getUint32(8, true);
  requireValue(length <= recordingLimits.metadataBytes && 12 + length <= bytes.length);
  const header = readJSON(bytes.subarray(12, 12 + length));
  requireValue(header.format === 1 && integer(header.count, 1, recordingLimits.entries));
  requireValue(integer(header.dropped, 0, Number.MAX_SAFE_INTEGER) && integer(header.maximumBytes, 1024, recordingLimits.bytes));
  requireValue(typeof header.startedAt === 'string' && header.startedAt.length <= 64 && typeof header.reason === 'string' && header.reason.length <= 512);
  header.manifest = validateManifest(header.manifest); return {header, offset: 12 + length};
}
function parseMetadata(bytes, manifest, previous) {
  const value = readJSON(bytes);
  requireValue(['checkpoint', 'commit', 'restore', 'generation'].includes(value.kind));
  requireValue(integer(value.sequence, previous ? previous.sequence + 1 : 0, Number.MAX_SAFE_INTEGER));
  if (previous) requireValue(value.sequence === previous.sequence + 1 && value.elapsed >= previous.elapsed);
  requireValue(integer(value.elapsed, 0, Number.MAX_SAFE_INTEGER) && (value.revision === null || integer(value.revision, 0, Number.MAX_SAFE_INTEGER)));
  requireValue(typeof value.persisted === 'boolean');
  requireValue(typeof value.generation === 'string' && value.generation.length <= 128 && (value.run === null || integer(value.run, 0, 2147483647)));
  requireValue(Array.isArray(value.effects) && value.effects.length <= 1024);
  if (value.kind === 'commit') parseCommand(manifest, 'match', value.command);
  else requireValue(value.command === null && !value.effects.length);
  for (const effect of value.effects) parseEffect(effect, manifest); return value;
}
function parseEffect(effect, manifest) {
  if (effect.kind === 'notice') requireValue(typeof effect.text === 'string' && effect.text.length <= 65536);
  else {
    requireValue(effect.kind === 'send' && [1, 2].includes(effect.owner));
    parseCommand(manifest, effect.owner === 1 ? 'match' : 'client', effect.command);
  }
}
function readFrame(bytes, view, offset) {
  requireValue(offset + 12 <= bytes.length);
  const metadataLength = view.getUint32(offset, true), count = view.getUint32(offset + 4, true), encoding = view.getUint32(offset + 8, true);
  const end = offset + 12 + metadataLength + count * 4;
  requireValue(metadataLength <= recordingLimits.metadataBytes && count <= recordingLimits.words * 2 + 3 && end <= bytes.length);
  requireValue([0, 1, 2].includes(encoding));
  const metadata = bytes.slice(offset + 12, offset + 12 + metadataLength), data = new Int32Array(count);
  for (let i = 0; i < count; i++) data[i] = view.getInt32(offset + 12 + metadataLength + i * 4, true);
  return {entry: {encoding, metadata, data}, end};
}
function parseDump(buffer) {
  requireValue(buffer instanceof ArrayBuffer && buffer.byteLength <= recordingLimits.fileBytes, 'Recording file exceeds the 72 MiB import limit');
  const bytes = new Uint8Array(buffer), view = new DataView(buffer), parsed = parseHeader(bytes, view);
  const chunks = [], schema = parsed.header.manifest.applications.find(app => app.owner === 'match').schema;
  let offset = parsed.offset, previous, words, storedBytes = 0;
  for (let i = 0; i < parsed.header.count; i++) {
    const frame = readFrame(bytes, view, offset), entry = frame.entry;
    const metadata = parseMetadata(entry.metadata, parsed.header.manifest, previous);
    const boundary = !previous || metadata.kind !== 'commit' || metadata.generation !== previous.generation || metadata.run !== previous.run;
    requireValue(!boundary || entry.encoding === 0); words = applyChange(words, entry); requireValue(words[0] === schema);
    const marker = parsed.header.manifest.settings.runMarker;
    requireValue(marker === undefined ? metadata.run === null : integer(marker, 1, words.length - 1) && words[marker] === metadata.run);
    if (!previous) requireValue(metadata.sequence === parsed.header.dropped);
    if (entry.encoding === 0) chunks.push({entries: [], bytes: 0});
    const chunk = chunks.at(-1); requireValue(chunk && chunk.entries.length < recordingLimits.chunk);
    entry.sequence = metadata.sequence; chunk.entries.push(entry); chunk.bytes += frame.end - offset;
    storedBytes += frame.end - offset; requireValue(storedBytes <= parsed.header.maximumBytes);
    previous = metadata; offset = frame.end;
  }
  requireValue(offset === bytes.length); return {header: parsed.header, chunks, bytes: storedBytes, last: previous.sequence};
}

export function compatibleRecording(recording, manifest) {
  return recording.manifest.settings.id === manifest.settings.id && protocolContract(recording.manifest) === protocolContract(manifest);
}
