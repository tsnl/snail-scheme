// A tab retains unsaved orders, not an authoritative match snapshot. The server's
// sequence and epoch decide which orders remain eligible after a page reload.
import {parseCommand, protocolContract} from '../application/runtime.mjs';

// ---- Stored data becomes a typed, immutable queue before it can be sent ----

function envelope(manifest, client, value) {
  if (value?.client !== client || !Number.isSafeInteger(value.sequence) || value.sequence < 1
      || typeof value.epoch !== 'string' || !value.epoch || value.epoch.length > 80)
    throw new Error('Invalid retained order; the stored queue has been kept.');
  const {handler, args} = parseCommand(manifest, 'match', value.command);
  if (!manifest.settings.remoteHandlers.includes(handler.binding)) throw new Error('Retained order is authority-only.');
  return Object.freeze({client, sequence: value.sequence, epoch: value.epoch,
    command: Object.freeze({handler: handler.id, args: Object.freeze([...args])})});
}
function readQueue(source, manifest, client, contract) {
  if (source === null) return [];
  const saved = JSON.parse(source);
  if (saved?.format !== 1 || saved.contract !== contract || !Array.isArray(saved.pending))
    throw new Error('Retained orders need the previous compatible package; the stored queue has been kept.');
  const pending = saved.pending.map(value => envelope(manifest, client, value));
  if (pending.some((value, index) => index > 0 && value.sequence !== pending[index - 1].sequence + 1))
    throw new Error('Retained order sequence has a gap; the stored queue has been kept.');
  return pending;
}

export class CloudOutbox {
  constructor(manifest, client, storage = sessionStorage) {
    this.manifest = manifest; this.client = client; this.storage = storage;
    this.key = `snail.outbox:${manifest.settings.id}:${client}`;
    this.contract = JSON.stringify([protocolContract(manifest), manifest.settings.runMarker ?? null]);
    this.pending = Object.freeze(readQueue(storage.getItem(this.key), manifest, client, this.contract));
  }
  replace(pending) {
    // Persist before admitting a prediction or forgetting an acknowledgement.
    // A failed write leaves both the old memory queue and stored record intact.
    if (pending.length) this.storage.setItem(this.key, JSON.stringify({format: 1, contract: this.contract, pending}));
    else this.storage.removeItem(this.key);
    this.pending = Object.freeze([...pending]);
  }
  append(sequence, epoch, command) {
    if (this.pending.length && sequence !== this.pending.at(-1).sequence + 1) throw new Error('Pending order sequence must be contiguous.');
    const value = envelope(this.manifest, this.client, {client: this.client, sequence, epoch, command});
    this.replace([...this.pending, value]);
    return value;
  }
  acknowledge(value) {
    if (this.pending[0] !== value) throw new Error('Acknowledgement does not match the first retained order.');
    this.replace(this.pending.slice(1));
  }
  reconcile(session) {
    // The server reuses every live session UUID. A fresh UUID therefore means
    // a restarted authority has no committed history for this old identity;
    // its former process cannot still accept an in-flight first command.
    const sameClient = session.client === this.client;
    if (!sameClient && this.pending.length && this.pending[0].sequence !== 1)
      throw new Error('Server lost this player history; retained orders have been kept.');
    const remaining = sameClient ? this.pending.filter(value => value.sequence >= session.next) : this.pending;
    if (remaining.some(value => value.epoch !== session.epoch)) return {pending: [], discarded: remaining.length};
    if (remaining.length && remaining[0].sequence !== session.next)
      throw new Error('Server and retained order sequences disagree; the stored queue has been kept.');
    return {pending: remaining.map(value => envelope(this.manifest, session.client, {...value, client: session.client})), discarded: 0};
  }
}
