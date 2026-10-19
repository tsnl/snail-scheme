// Stable owner, replaceable code. Only this private scalar bridge handles
// mutable buffers; application handlers receive explicit immutable values.
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../lofi/compiler/execute.mjs';
import {createUiBridge} from '../ui/bridge.mjs';
import {createSceneBridge} from '../draw3d/bridge.mjs';

// ---- Typed Wasm forwarding for host scalar functions ----

const encoder = new TextEncoder();
const uleb = value => { const bytes = []; do { const n = value & 127; value >>>= 7; bytes.push(n | (value ? 128 : 0)); } while (value); return bytes; };
const name = value => { const bytes = encoder.encode(value); return [...uleb(bytes.length), ...bytes]; };
const section = (id, bytes) => [id, ...uleb(bytes.length), ...bytes];
function scalarProvider(functions, signatures = [['length', 1, true], ['read', 2, true], ['write', 3, false],
    ['command', 4, false], ['note', 2, false], ['quad', 6, false], ['label', 2, false],
    ['previous-length', 1, true], ['previous-read', 2, true], ['identity', 2, true],
    ['observe', 7, false]]) {
  const types = signatures.flatMap(([, count, result]) => [0x60, count, ...Array(count).fill(0x7f), ...(result ? [1, 0x7f] : [0])]);
  const imports = signatures.flatMap(([key], i) => [...name('host'), ...name(key), 0, i]);
  const exports = signatures.flatMap(([key], i) => [...name(key), 0, i]);
  const count = signatures.length;
  const bytes = [0, 97, 115, 109, 1, 0, 0, 0, ...section(1, [count, ...types]),
    ...section(2, [count, ...imports]), ...section(7, [count, ...exports])];
  return new WebAssembly.Instance(new WebAssembly.Module(Uint8Array.from(bytes)), {host: functions});
}
const i32 = value => Number.isInteger(value) && value >= -2147483648 && value <= 2147483647;
const maximumSnapshotWords = 1048576;
function sameSnapshot(left, right) {
  if (left?.length !== right.length) return false;
  for (let index = 0; index < right.length; index++) if (left[index] !== right[index]) return false;
  return true;
}

// Diagnostics transport Unicode scalars only. The provider releases its token
// before throwing, so a malformed snapshot cannot retain a partial message.
function diagnosticProvider() {
  const tokens = new Map(); let next = 1;
  return scalarProvider({
    'snail:datum/token-open': () => { const id = next++; tokens.set(id, []); return id; },
    'snail:datum/token-character': (id, value) => {
      const text = tokens.get(id);
      if (!text || value < 0 || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff))
        throw new Error('invalid diagnostic token or Unicode scalar');
      text.push(String.fromCodePoint(value));
    },
    'snail:datum/fail': id => {
      const text = tokens.get(id); tokens.delete(id);
      throw new WebAssembly.RuntimeError(text ? text.join('') : 'invalid diagnostic token');
    }
  }, [['snail:datum/token-open', 0, true], ['snail:datum/token-character', 2, false],
      ['snail:datum/fail', 1, false]]);
}

// ---- Manifest establishes endpoint identity and payload shape ----

function freezeValue(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.values(value).forEach(freezeValue); Object.freeze(value);
  }
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
// endpoint identities. Lexical requests retain their identity across reloads.
export function protocolContract(manifest) {
  return JSON.stringify({effects: manifest.effects,
    applications: manifest.applications.map(app => ({owner: app.owner, state: app.state, schema: app.schema,
      handlers: app.handlers.map(h => [h.id, h.payload, h.result]).sort((a,b) => a[0].localeCompare(b[0]))}))
      .sort((a,b) => a.owner.localeCompare(b.owner))});
}

// ---- One message lane for the shared two-owner instance ----

export class ReducerRuntime {
  stores = new Map(); previousSnapshots = new Map(); active; instance; manifest; sizes; previous;
  #tail = Promise.resolve(); #closing; #activation = 0; #recoveries = new Set();
  #snapshotIdentities = new WeakMap(); #nextSnapshotIdentity = 1;
  // One optional diagnostic recorder. It observes publication, never owns it.
  recording;
  constructor() {
    this.provider = scalarProvider({length: id => this.bank(id).length,
      read: (id, index) => this.read(id, index), write: (id, index, value) => this.write(id, index, value),
      command: (owner, slot, a, b) => this.stageEffect({kind: 'send', owner, slot, args: [a, b]}),
      note: (index, value) => this.stageText('note', index, value),
      quad: (...words) => this.active.output.quads.push(words),
      observe: (...words) => this.stageObservation(words),
      label: (index, value) => this.stageText('label', index, value),
      'previous-length': id => this.previousBank(id).length,
      'previous-read': (id, index) => this.previousBank(id, index)[index],
      identity: (id, previous) => this.snapshotIdentity(id, previous)});
    this.diagnostics = diagnosticProvider();
    this.uiBridge = createUiBridge(scalarProvider, () => this.active);
    this.sceneBridge = createSceneBridge(scalarProvider, () => this.active);
  }
  bank(id, index) {
    if (!this.active) throw new Error('snapshot bridge used outside a transaction');
    const bank = this.active.snapshots.get(id);
    if (!bank || (index !== undefined && (index < 0 || index >= bank.length))) throw new RangeError('invalid snapshot field');
    return bank;
  }
  read(id, index) { return this.bank(id, index)[index]; } // The staged input, never the replacement being written.
  snapshotIdentity(id, previous) {
    if (previous !== 0 && previous !== 1) throw new RangeError('invalid snapshot identity source');
    const bank = previous ? this.previousBank(id) : this.bank(id);
    let identity = this.#snapshotIdentities.get(bank);
    if (identity === undefined) {
      // Never recycle an identity: a retained Wasm cache may outlive its bank.
      if (this.#nextSnapshotIdentity > 0x7fffffff) throw new RangeError('snapshot identity exhausted');
      identity = this.#nextSnapshotIdentity++; this.#snapshotIdentities.set(bank, identity);
    }
    return identity;
  }
  previousBank(id, index) {
    const current = this.bank(id);
    const bank = this.active.previousSnapshots?.get(id) ?? current;
    if (index !== undefined && (index < 0 || index >= bank.length)) throw new RangeError('invalid previous snapshot field');
    return bank;
  }
  write(id, index, value) {
    const bank = this.bank(id);
    if (this.active.readOnly || this.active.owner !== id) throw new Error('write outside this owner transition');
    if (index === -1) {
      if (value < 1 || value > maximumSnapshotWords || (this.sizes[id - 1] && value !== this.sizes[id - 1]))
        throw new Error('invalid declared/encoded snapshot size');
      this.active.next = new Int32Array(value); return;
    }
    if (!this.active.next) this.active.next = bank.slice();
    if (index < 0 || index >= this.active.next.length) throw new RangeError('invalid snapshot field');
    this.active.next[index] = value;
  }
  stageEffect(effect) {
    if (this.active.readOnly) throw new Error('effect during a query or candidate validation');
    this.active.effects.push(effect);
  }
  stageObservation(words) {
    if (!this.active?.readOnly || !this.active.output.observation)
      throw new Error('observation row outside an observation query');
    if (this.active.output.observation.length >= 131072) throw new Error('observation row limit');
    this.active.output.observation.push(words);
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
  #enqueue(operation) {
    const result = this.#tail.then(operation);
    this.#tail = result.catch(() => {}); // One failed message cannot poison the lane.
    return result;
  }
  // An admitted operation uses the supplied dispatcher inside this same message.
  // Awaiting another queued mutation here would wait on the current message.
  message(operation) {
    if (this.#closing) return Promise.reject(new Error('runtime is closing'));
    return this.#enqueue(() => this.#runMessage(operation));
  }
  async #runMessage(operation) {
    let transition, open = true, used = false;
    const dispatch = (...args) => {
      if (!open || used) throw new Error('one transition per runtime message');
      used = true;
      return transition = this.#transition(...args);
    };
    try { return await operation(dispatch); }
    finally { open = false; await transition; }
  }

  // ---- Synchronous scalar scope; no host I/O can observe its candidate ----

  #stage(instance, args, {owner, readOnly = false, snapshots = this.stores, manifest = this.manifest, observation = false} = {}) {
    if (this.active) throw new Error('nested transition');
    this.active = {owner, readOnly, snapshots, previousSnapshots: this.previousSnapshots,
      instance, effects: [], output: {quads: [], ...(observation ? {observation: []} : {})}};
    try {
      const result = invokeEntry(instance, args), tx = this.active;
      this.validateReplacement(instance, tx);
      const ui = this.uiBridge.finish(tx, manifest);
      const scene = this.sceneBridge.finish(tx);
      const output = freezeValue({result, effects: tx.effects.map(effect => this.#materializeEffect(effect)),
        quads: tx.output.quads, label: tx.label ? String.fromCodePoint(...tx.label) : '',
        ...(observation ? {observation: tx.output.observation} : {}),
        ...(ui ? {ui} : {}), ...(scene ? {scene} : {})});
      return {next: tx.next, output};
    } catch (error) {
      error.transitionPhase = 'reduce';
      if (!readOnly && this.active.next) error.candidateSnapshot = Array.from(this.active.next);
      throw error;
    }
    finally { this.active = undefined; }
  }
  #materializeEffect(effect) {
    if (effect.kind === 'notice') return {kind: 'notice', text: String.fromCodePoint(...effect.chars)};
    const app = this.manifest.applications.find(a => a.owner === (effect.owner === 1 ? 'match' : 'client'));
    const handler = app?.handlers[effect.slot];
    if (!handler || ![1, 2].includes(effect.owner)) throw new Error('effect targets invalid endpoint');
    const command = {handler: handler.id, args: effect.args.slice(0, handler.payload.length)};
    parseCommand(this.manifest, app.owner, command);
    return {kind: 'send', owner: effect.owner, command};
  }
  validateReplacement(instance, tx) {
    if (!tx.next) return;
    const ownerName = tx.owner === 1 ? 'match' : 'client';
    const schema = this.manifest.applications.find(app => app.owner === ownerName).schema;
    if (tx.next[0] !== schema) throw new Error('replacement snapshot has an invalid schema');
    // Candidate validation receives its own read-only map. Committed snapshots
    // remain visible even while preparing a replacement or awaiting a save.
    const snapshots = new Map(tx.snapshots).set(tx.owner, tx.next);
    this.active = {readOnly: true, snapshots, previousSnapshots: tx.previousSnapshots,
      instance, effects: [], output: {quads: []}};
    try {
      if (!invokeEntry(instance, [10, 0, 0, 0])) throw new Error('invalid replacement snapshot');
    } finally { this.active = tx; }
  }
  metadata(instance, index) { return this.#stage(instance, [0, index, 0, 0], {readOnly: true}).output.result; }
  prepare(bytes, manifest) {
    if (this.#closing) throw new Error('runtime is closing');
    if (this.active) throw new Error('code preparation during a transition');
    manifest = validateManifest(manifest);
    if (this.manifest && protocolContract(manifest) !== protocolContract(this.manifest))
      throw new Error('incompatible endpoint contract; restart or explicit protocol migration required');
    const instance = instantiate(loadWasm(bytes), new Map([['snail.reducer', this.provider], ['snail.library', this.diagnostics],
      ['snail.ui', this.uiBridge.provider], ['snail.scene', this.sceneBridge.provider]]));
    try {
      if (this.metadata(instance, 0) !== 1) throw new Error('incompatible scalar bridge ABI');
      const sizes = Object.freeze([this.metadata(instance, 1), this.metadata(instance, 2)]);
      for (const owner of [1, 2]) {
        if (sizes[owner - 1] < 0 || sizes[owner - 1] > maximumSnapshotWords) throw new Error('invalid declared state size');
        const app = manifest.applications.find(a => a.owner === (owner === 1 ? 'match' : 'client'));
        if (app.schema !== this.metadata(instance, owner + 2)) throw new Error('manifest/module schema mismatch');
      }
      this.candidateStores(instance, sizes, manifest);
      return {instance, manifest, sizes};
    } catch (error) { closeInstance(instance); throw error; }
  }
  candidateStores(instance, sizes, manifest = this.manifest) {
    const proposed = new Map(this.stores);
    for (const owner of [1, 2]) {
      if (proposed.has(owner) && sizes[owner - 1] && proposed.get(owner).length !== sizes[owner - 1])
        throw new Error('incompatible state shape; explicit migration required');
      if (!proposed.has(owner)) proposed.set(owner, new Int32Array(sizes[owner - 1] || 1));
    }
    // This scope is synchronous. Preparing code never reserves an absent owner's
    // shape, and installation constructs a fresh map from the then-current state.
    this.validateCandidate(instance, proposed, manifest); return proposed;
  }
  validateState(instance, snapshots = this.stores) {
    if (!this.#stage(instance, [10, 0, 0, 0], {readOnly: true, snapshots}).output.result)
      throw new Error('incompatible state schema; explicit migration required');
  }
  validateCandidate(instance, snapshots = this.stores, manifest = this.manifest) {
    this.validateState(instance, snapshots);
    // Test presentation before activation too. Initial absent owners have no
    // values to render; their initialization remains a separate transition.
    if ([1, 2].every(owner => snapshots.get(owner)?.[0]))
      this.#stage(instance, [4, 0, 0, 0], {readOnly: true, snapshots, manifest});
  }
  discard(candidate) { closeInstance(candidate.instance); }
  replace(candidate) {
    return this.message(() => this.#install(candidate));
  }
  #install(candidate) {
    if (this.manifest && protocolContract(candidate.manifest) !== protocolContract(this.manifest))
      throw new Error('incompatible endpoint contract; restart or explicit protocol migration required');
    const stores = this.candidateStores(candidate.instance, candidate.sizes, candidate.manifest);
    if (this.previous) closeInstance(this.previous.instance);
    this.previous = this.instance ? {instance: this.instance, manifest: this.manifest, sizes: this.sizes} : undefined;
    this.stores = stores; this.instance = candidate.instance; this.manifest = candidate.manifest; this.sizes = candidate.sizes;
    this.#activation++;
    this.#record('generation', 1);
  }
  initialize(owner) {
    return this.message(() => {
      if (this.stores.get(owner)[0]) return;
      const staged = this.#stage(this.instance, [1, owner, 0, 0], {owner});
      if (staged.next) this.#commitSnapshot(owner, staged.next, true);
      return staged.output;
    });
  }
  async dispatch(owner, command, {persist, publish} = {}) {
    command = structuredClone(command); // The queued request owns its input.
    return this.message(dispatch => dispatch(owner, command, {persist, publish}));
  }
  async #transition(owner, command, {persist, publish} = {}) {
    const {handler, args} = parseCommand(this.manifest, owner === 1 ? 'match' : 'client', command);
    const handledCommand = owner === 1 ? {handler: handler.id, args: args.slice()} : undefined;
    let staged;
    try { staged = this.#stage(this.instance, [owner === 1 ? 2 : 3, handler.slot, args[0] ?? 0, args[1] ?? 0], {owner}); }
    catch (error) {
      error.reproduction = this.lastFailure = {format: 1, generation: this.manifest.generation,
        owner, command: structuredClone(command), message: error.message,
        snapshots: [...this.stores].map(([owner, state]) => ({owner, state: Array.from(state)})),
        ...(error.candidateSnapshot ? {candidate: error.candidateSnapshot} : {})};
      try { this.#recoverCode(error); }
      catch (recoveryError) { error.recoveryError = recoveryError; }
      throw error;
    }
    // The bridge is inactive and reads still see committed snapshots. A saver
    // receives an immutable copy, never the buffer that will become committed.
    if (persist) await persist(Object.freeze(Array.from(staged.next ?? this.stores.get(owner))), staged.output.effects);
    if (staged.next) this.#commitSnapshot(owner, staged.next, false);
    // Recording cannot interrupt revision publication or queue effects twice.
    try { if (publish) publish(staged.output); }
    finally { this.#record('commit', owner, handledCommand, staged.output.effects, !!persist); }
    return staged.output;
  }
  // Both endpoints advance in the publication turn, after validation and any
  // durable write. Initialization and explicit restores begin without motion.
  #commitSnapshot(owner, next, reset) {
    if (!reset && sameSnapshot(this.stores.get(owner), next)) return;
    this.previousSnapshots = new Map(this.previousSnapshots).set(owner, reset ? next : this.stores.get(owner));
    this.stores = new Map(this.stores).set(owner, next);
  }
  #record(kind, owner, command = null, effects = [], persisted = false) {
    if (owner !== 1 || !this.recording || !this.stores.get(1)?.[0]) return;
    try { this.recording.capture(this, {kind, command, effects, persisted}); }
    catch (error) {
      this.recordingError = String(error.message ?? error);
      try { this.recording.fail(this.recordingError); } catch {} // Diagnostics stay nonfatal.
    }
  }
  #recoverCode(error) {
    // A trap does not commit. Persistence failures alone must not change code.
    if (error.transitionPhase !== 'reduce' || !this.previous) return;
    this.validateCandidate(this.previous.instance, this.stores, this.previous.manifest);
    closeInstance(this.instance); this.instance = this.previous.instance;
    this.manifest = this.previous.manifest; this.sizes = this.previous.sizes; this.previous = undefined;
    this.#activation++;
    this.#record('generation', 1);
  }
  command(owner, binding, args = []) { return {handler: endpoint(this.manifest, owner, binding).id, args}; }
  effectCommand(effect) { return effect.command; }
  view() {
    if (this.#closing) throw new Error('runtime is closing');
    try { return this.#stage(this.instance, [4, 0, 0, 0], {readOnly: true}).output; }
    catch (error) { this.#deferRecovery(this.#activation, error); throw error; }
  }
  #deferRecovery(activation, error) {
    if (this.#closing || this.#recoveries.has(activation)) return;
    this.#recoveries.add(activation);
    this.#enqueue(() => { if (this.#activation === activation) this.#recoverCode(error); })
      .catch(() => {}) // The original query reports failure; failed recovery preserves installed code.
      .finally(() => this.#recoveries.delete(activation));
  }
  snapshot(owner) { return Array.from(this.stores.get(owner)); }
  observe() {
    if (this.#closing) throw new Error('runtime is closing');
    if (this.manifest.settings?.observation?.version !== 1)
      throw new Error('package does not support observation version 1; rebuild the application');
    return this.#stage(this.instance, [12, 0, 0, 0], {readOnly: true, observation: true}).output.observation;
  }
  inspect(index) {
    if (this.#closing) throw new Error('runtime is closing');
    const projection = this.manifest.settings?.recording?.inspection;
    if (!projection || !Number.isInteger(index) || index < -1 || index >= projection.fields.length)
      throw new Error('unsupported diagnostic projection or field');
    return this.#stage(this.instance, [11, index, 0, 0], {readOnly: true}).output.result;
  }
  async restore(owner, words, {persist, publish} = {}) {
    words = structuredClone(words);
    return this.message(() => this.#restoreState(owner, words, {persist, publish}));
  }
  async #restoreState(owner, words, {persist, publish}) {
    if (!Array.isArray(words) || words.length < 1 || words.length > maximumSnapshotWords || !words.every(i32)
        || (this.sizes[owner - 1] && words.length !== this.sizes[owner - 1])) throw new Error('invalid snapshot');
    const schema = this.manifest.applications.find(app => app.owner === (owner === 1 ? 'match' : 'client')).schema;
    if (words[0] !== schema) throw new Error('invalid snapshot schema');
    const snapshots = new Map(this.stores).set(owner, Int32Array.from(words));
    this.validateState(this.instance, snapshots);
    if (persist) await persist(Object.freeze(words), []);
    this.#commitSnapshot(owner, snapshots.get(owner), true);
    try { if (publish) publish({effects: []}); }
    finally { this.#record('restore', owner, null, [], !!persist); }
  }

  close() {
    return this.#closing ??= this.#enqueue(() => {
      if (this.instance) closeInstance(this.instance);
      if (this.previous) closeInstance(this.previous.instance);
    });
  }
}
