// Stable owner, replaceable code. Only this private scalar bridge handles
// mutable buffers; application handlers receive explicit immutable values.
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../lofi/execute.mjs';

// ---- Typed Wasm forwarding for host scalar functions ----

const encoder = new TextEncoder();
const uleb = value => { const bytes = []; do { const n = value & 127; value >>>= 7; bytes.push(n | (value ? 128 : 0)); } while (value); return bytes; };
const name = value => { const bytes = encoder.encode(value); return [...uleb(bytes.length), ...bytes]; };
const section = (id, bytes) => [id, ...uleb(bytes.length), ...bytes];
function scalarProvider(functions) {
  const signatures = [['length', 1, true], ['read', 2, true], ['write', 3, false],
    ['command', 4, false], ['note', 2, false], ['quad', 6, false], ['label', 2, false]];
  const types = signatures.flatMap(([, count, result]) => [0x60, count, ...Array(count).fill(0x7f), ...(result ? [1, 0x7f] : [0])]);
  const imports = signatures.flatMap(([key], i) => [...name('host'), ...name(key), 0, i]);
  const exports = signatures.flatMap(([key], i) => [...name(key), 0, i]);
  const count = signatures.length;
  const bytes = [0, 97, 115, 109, 1, 0, 0, 0, ...section(1, [count, ...types]),
    ...section(2, [count, ...imports]), ...section(7, [count, ...exports])];
  return new WebAssembly.Instance(new WebAssembly.Module(Uint8Array.from(bytes)), {host: functions});
}
const i32 = value => Number.isInteger(value) && value >= -2147483648 && value <= 2147483647;

// ---- Manifest establishes endpoint identity and payload shape ----

function freezeValue(value) {
  if (value && typeof value === 'object') { Object.values(value).forEach(freezeValue); Object.freeze(value); }
  return value;
}
export function validateManifest(input) {
  const manifest = structuredClone(input);
  if (manifest?.version !== 1 || !Array.isArray(manifest.applications)) throw new Error('unsupported application manifest');
  for (const app of manifest.applications) {
    if (!['match', 'client'].includes(app.owner) || !Number.isInteger(app.schema) || app.schema < 1)
      throw new Error('invalid owner or state schema');
    const ids = new Set();
    for (const [slot, handler] of app.handlers.entries()) {
      if (handler.slot !== slot || typeof handler.id !== 'string' || ids.has(handler.id)
          || !Array.isArray(handler.payload) || handler.payload.length > 2 || handler.payload.some(x => x !== 'I32'))
        throw new Error('invalid generated handler descriptor');
      ids.add(handler.id);
    }
  }
  if (new Set(manifest.applications.map(a => a.owner)).size !== 2) throw new Error('expected match and client owners');
  return freezeValue(manifest);
}
export function endpoint(manifest, owner, binding) {
  const value = manifest.applications.find(a => a.owner === owner)?.handlers.find(h => h.binding === binding);
  if (!value) throw new Error(`unknown lexical endpoint in manifest: ${owner}/${binding}`);
  return value;
}
export function parseCommand(manifest, owner, command) {
  const handler = manifest.applications.find(a => a.owner === owner)?.handlers.find(h => h.id === command?.handler);
  if (!handler || !Array.isArray(command.args) || command.args.length !== handler.payload.length || !command.args.every(i32))
    throw new Error('unknown endpoint identity or invalid typed payload');
  return {handler, args: command.args};
}

// Contracts may reorder slots, but a live replacement cannot add/remove/change
// endpoint identities. Pending envelopes remain encoded under their old contract.
function protocolContract(manifest) {
  return JSON.stringify({effects: manifest.effects,
    applications: manifest.applications.map(app => ({owner: app.owner, state: app.state, schema: app.schema,
      handlers: app.handlers.map(h => [h.id, h.payload, h.result]).sort((a,b) => a[0].localeCompare(b[0]))}))
      .sort((a,b) => a.owner.localeCompare(b.owner))});
}

// ---- One synchronous transition per owner ----

export class ReducerRuntime {
  stores = new Map(); active; instance; manifest; previous;
  constructor() {
    this.provider = scalarProvider({length: id => this.bank(id).length,
      read: (id, index) => this.read(id, index), write: (id, index, value) => this.write(id, index, value),
      command: (owner, slot, a, b) => this.stageEffect({kind: 'send', owner, slot, args: [a, b]}),
      note: (index, value) => this.stageText('note', index, value),
      quad: (...words) => this.active.output.quads.push(words),
      label: (index, value) => this.stageText('label', index, value)});
  }
  bank(id, index) {
    if (!this.active) throw new Error('snapshot bridge used outside a transaction');
    const bank = this.stores.get(id);
    if (!bank || (index !== undefined && (index < 0 || index >= bank.length))) throw new RangeError('invalid snapshot field');
    return bank;
  }
  read(id, index) { return this.bank(id, index)[index]; } // Always the prior snapshot.
  write(id, index, value) {
    const bank = this.bank(id, index);
    if (this.active.readOnly || this.active.owner !== id) throw new Error('write outside this owner transition');
    if (!this.active.next) this.active.next = bank.slice();
    this.active.next[index] = value;
  }
  stageEffect(effect) {
    if (this.active.readOnly) throw new Error('effect during a query or candidate validation');
    this.active.effects.push(effect);
  }
  stageText(kind, index, value) {
    if (index === -1) {
      if (value < 0 || value > 65536) throw new Error('invalid text length');
      const chars = Array(value).fill(0); this.active[kind] = chars;
      if (kind === 'note') this.stageEffect({kind: 'notice', chars});
    } else {
      const chars = this.active[kind];
      if (!chars || index < 0 || index >= chars.length) throw new Error('invalid text position');
      chars[index] = value;
    }
  }
  transaction(instance, args, {owner, readOnly = false, persist} = {}) {
    if (this.active) throw new Error('nested transition');
    this.active = {owner, readOnly, effects: [], output: {quads: []}};
    let phase = "reduce";
    try {
      const result = invokeEntry(instance, args), tx = this.active;
      this.validateReplacement(instance, tx);
      const next = tx.next ?? this.stores.get(owner);
      phase = "persist";
      if (persist) persist(next, tx.effects); // A failed durable commit publishes nothing.
      if (tx.next) this.stores.set(owner, tx.next);
      return {result, effects: tx.effects, quads: tx.output.quads,
        label: tx.label ? String.fromCodePoint(...tx.label) : ''};
    } catch (error) { error.transitionPhase = phase; throw error; }
    finally { this.active = undefined; }
  }
  validateReplacement(instance, tx) {
    if (!tx.next) return;
    const ownerName = tx.owner === 1 ? 'match' : 'client';
    const schema = this.manifest.applications.find(app => app.owner === ownerName).schema;
    if (tx.next[0] !== schema) throw new Error('replacement snapshot has an invalid schema');
    const previous = this.stores.get(tx.owner);
    // Validation sees the proposed snapshot in an isolated read-only scope.
    // Neither durable storage nor observers can see it before this returns.
    this.stores.set(tx.owner, tx.next);
    this.active = {readOnly: true, effects: [], output: {quads: []}};
    try {
      if (!invokeEntry(instance, [10, 0, 0, 0])) throw new Error('invalid replacement snapshot');
    } finally { this.stores.set(tx.owner, previous); this.active = tx; }
  }
  metadata(instance, index) { return this.transaction(instance, [0, index, 0, 0], {readOnly: true}).result; }
  prepare(bytes, manifest) {
    manifest = validateManifest(manifest);
    if (this.manifest && protocolContract(manifest) !== protocolContract(this.manifest))
      throw new Error('incompatible endpoint contract; restart or explicit protocol migration required');
    const instance = instantiate(loadWasm(bytes), new Map([['snail.reducer', this.provider]]));
    try {
      if (this.metadata(instance, 0) !== 1) throw new Error('incompatible scalar bridge ABI');
      for (const owner of [1, 2]) {
        const size = this.metadata(instance, owner);
        if (size < 1 || size > 65536 || (this.stores.has(owner) && size !== this.stores.get(owner).length))
          throw new Error('incompatible state shape; explicit migration required');
        if (!this.stores.has(owner)) this.stores.set(owner, new Int32Array(size));
        const app = manifest.applications.find(a => a.owner === (owner === 1 ? 'match' : 'client'));
        if (app.schema !== this.metadata(instance, owner + 2)) throw new Error('manifest/module schema mismatch');
      }
      this.validateCandidate(instance);
      return {instance, manifest};
    } catch (error) { closeInstance(instance); throw error; }
  }
  validateState(instance) {
    if (!this.transaction(instance, [10, 0, 0, 0], {readOnly: true}).result)
      throw new Error('incompatible state schema; explicit migration required');
  }
  validateCandidate(instance) {
    this.validateState(instance);
    // Test presentation before activation too. Initial absent owners have no
    // values to render; their initialization remains a separate transition.
    if ([1, 2].every(owner => this.stores.get(owner)?.[0]))
      this.transaction(instance, [4, 0, 0, 0], {readOnly: true});
  }
  discard(candidate) { closeInstance(candidate.instance); }
  replace(candidate) {
    this.validateCandidate(candidate.instance); // State may have advanced while GPU preparation awaited.
    if (this.previous) closeInstance(this.previous.instance);
    this.previous = this.instance ? {instance: this.instance, manifest: this.manifest} : undefined;
    this.instance = candidate.instance; this.manifest = candidate.manifest;
  }
  initialize(owner) {
    if (!this.stores.get(owner)[0]) return this.transaction(this.instance, [1, owner, 0, 0], {owner});
  }
  dispatch(owner, command, options = {}) {
    const {handler, args} = parseCommand(this.manifest, owner === 1 ? 'match' : 'client', command);
    try { return this.transaction(this.instance, [owner === 1 ? 2 : 3, handler.slot, args[0] ?? 0, args[1] ?? 0], {owner, ...options}); }
    catch (error) {
      this.recoverCode(error);
      throw error;
    }
  }
  recoverCode(error) {
    // A trap does not commit. Persistence failures alone must not change code.
    if (error.transitionPhase !== 'reduce' || !this.previous) return;
    this.validateCandidate(this.previous.instance);
    closeInstance(this.instance); this.instance = this.previous.instance;
    this.manifest = this.previous.manifest; this.previous = undefined;
  }
  command(owner, binding, args = []) { return {handler: endpoint(this.manifest, owner, binding).id, args}; }
  effectCommand(effect) {
    const app = this.manifest.applications.find(a => a.owner === (effect.owner === 1 ? 'match' : 'client'));
    const handler = app?.handlers[effect.slot];
    if (!handler) throw new Error('effect targets invalid endpoint');
    return {handler: handler.id, args: effect.args.slice(0, handler.payload.length)};
  }
  view() {
    try { return this.transaction(this.instance, [4, 0, 0, 0], {readOnly: true}); }
    catch (error) { this.recoverCode(error); throw error; }
  }
  snapshot(owner) { return Array.from(this.stores.get(owner)); }
  restore(owner, words) {
    if (!Array.isArray(words) || words.length !== this.stores.get(owner).length || !words.every(i32)) throw new Error('invalid snapshot');
    const previous = this.stores.get(owner); this.stores.set(owner, Int32Array.from(words));
    try { this.validateState(this.instance); }
    catch (error) { this.stores.set(owner, previous); throw error; }
  }
  close() { if (this.instance) closeInstance(this.instance); if (this.previous) closeInstance(this.previous.instance); }
}
