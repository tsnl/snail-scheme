// Authority admission and durable publication share the runtime's message lane.
// SHA-256 receipts use Web Crypto so the same authority can host a browser store.
const encoder = new TextEncoder();
async function digest(value) {
  const bytes = await crypto.subtle.digest('SHA-256', encoder.encode(JSON.stringify(value)));
  return Array.from(new Uint8Array(bytes), byte => byte.toString(16).padStart(2, '0')).join('');
}
function savedMetadata(saved) {
  const copy = structuredClone(saved);
  if (!Number.isSafeInteger(copy.revision) || copy.revision < 0 || typeof copy.epoch !== 'string'
      || !copy.clients || typeof copy.clients !== 'object') throw new Error('invalid durable owner metadata');
  return freezeMetadata(copy);
}
function freezeMetadata(value) {
  if (value && typeof value === 'object') { Object.values(value).forEach(freezeMetadata); Object.freeze(value); }
  return value;
}

export class Authority {
  revision = 0; epoch = crypto.randomUUID(); clients = Object.freeze({}); log = [];
  constructor(runtime, {saved, commit = () => {}, publish = () => {}, resetHandler, runMarker} = {}) {
    if (saved !== undefined) throw new Error('restore durable state with await Authority.open');
    this.runtime = runtime; this.commit = commit; this.publish = publish; this.resetHandler = resetHandler; this.runMarker = runMarker;
    if (runMarker !== undefined && (!Number.isInteger(runMarker) || runMarker < 1 || runMarker >= runtime.snapshot(1).length))
      throw new Error('invalid run marker snapshot offset');
  }
  static async open(runtime, {saved, ...options} = {}) {
    const authority = new Authority(runtime, options);
    if (saved) {
      saved = savedMetadata(saved);
      await runtime.restore(1, saved.state);
      authority.revision = saved.revision; authority.epoch = saved.epoch; authority.clients = saved.clients;
    }
    return authority;
  }
  snapshot() { return {revision: this.revision, epoch: this.epoch, state: this.runtime.snapshot(1)}; }
  async submit(envelope, {internal = false} = {}) {
    envelope = structuredClone(envelope); // Later caller edits cannot rewrite an admitted request.
    return this.runtime.message(dispatch => {
      // The clock takes its sequence/epoch at admission, after any queued reset.
      if (internal) envelope = {...envelope, epoch: this.epoch, sequence: (this.clients[envelope.client]?.sequence ?? 0) + 1};
      return this.accept(envelope, dispatch, internal);
    });
  }
  async accept(envelope, dispatch, internal) {
    const {client, sequence, epoch, command} = envelope;
    if (typeof client !== 'string' || client.length > 80 || !Number.isSafeInteger(sequence) || sequence < 1)
      throw new Error('invalid command envelope');
    const fingerprint = await digest([epoch, command?.handler, command?.args]);
    const duplicate = this.receipt(envelope, fingerprint);
    if (duplicate) return duplicate;
    const record = {revision: this.revision + 1, client, sequence, handler: command.handler, args: command.args};
    const entry = {...record, digest: await digest(record), internal};
    return this.transition(envelope, fingerprint, entry, dispatch);
  }
  receipt({client, sequence, epoch}, fingerprint) {
    const prior = Object.hasOwn(this.clients, client) ? this.clients[client] : undefined;
    if (prior && sequence < prior.sequence) throw new Error('sequence already consumed; receipt expired');
    if (prior && sequence === prior.sequence) {
      if (prior.fingerprint !== fingerprint) throw new Error('request identity reused with a different payload');
      return {duplicate: true, receipt: prior.receipt, ...this.snapshot()};
    }
    if (epoch !== this.epoch) throw new Error('stale match epoch');
    if (sequence !== (prior?.sequence ?? 0) + 1) throw new Error('out-of-order command sequence');
  }
  async transition(envelope, fingerprint, entry, dispatch) {
    const marker = this.runMarker === undefined ? undefined : this.runtime.snapshot(1)[this.runMarker];
    let next;
    await dispatch(1, envelope.command, {
      persist: (state, effects) => {
        next = this.prepareCommit(state, effects, envelope, fingerprint, entry, marker);
        return this.commit(next.durable, this.revision);
      },
      publish: () => this.publishCommit(next),
    });
    return next.snapshot;
  }
  prepareCommit(state, effects, {client, sequence, command}, fingerprint, entry, marker) {
    const reset = this.runMarker === undefined ? command.handler === this.resetHandler : state[this.runMarker] !== marker;
    const epoch = reset ? crypto.randomUUID() : this.epoch, revision = entry.revision;
    const receipt = Object.freeze({revision, epoch});
    const clients = Object.freeze({...this.clients, [client]: Object.freeze({sequence, fingerprint, receipt})});
    const snapshot = Object.freeze({state, revision, epoch});
    const durable = Object.freeze({...snapshot, clients}), log = [...this.log.slice(-511), entry];
    const notifications = [{type: 'snapshot', ...snapshot}, ...effects.map(effect => ({type: 'effect', revision, effect}))];
    return {durable, snapshot, log, notifications};
  }
  publishCommit({durable, log, notifications}) {
    // These assignments and the runtime's snapshot publication are one turn.
    // Observer failures retain the receipt, so retry never reruns the reducer.
    this.revision = durable.revision; this.epoch = durable.epoch; this.clients = durable.clients; this.log = log;
    for (const notification of notifications) this.publish(notification);
  }
}
