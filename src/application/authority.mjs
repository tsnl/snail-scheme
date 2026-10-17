// A single authority serializes one owner's command stream. Persistence is a
// synchronous compare-and-swap boundary; effect delivery follows the commit.
import {createHash, randomUUID} from 'node:crypto';

export class Authority {
  revision = 0; epoch = randomUUID(); clients = {}; log = [];
  constructor(runtime, {saved, commit = () => {}, publish = () => {}, resetHandler} = {}) {
    this.runtime = runtime; this.commit = commit; this.publish = publish; this.resetHandler = resetHandler;
    if (saved) {
      if (!Number.isSafeInteger(saved.revision) || saved.revision < 0 || typeof saved.epoch !== 'string'
          || !saved.clients || typeof saved.clients !== 'object') throw new Error('invalid durable owner metadata');
      runtime.restore(1, saved.state);
      this.revision = saved.revision; this.epoch = saved.epoch; this.clients = saved.clients;
    }
  }
  snapshot() { return {revision: this.revision, epoch: this.epoch, state: this.runtime.snapshot(1)}; }
  submit(envelope, {internal = false} = {}) {
    const {client, sequence, epoch, command} = envelope;
    if (typeof client !== 'string' || client.length > 80 || !Number.isSafeInteger(sequence) || sequence < 1)
      throw new Error('invalid command envelope');
    const fingerprint = createHash('sha256').update(JSON.stringify([epoch, command?.handler, command?.args])).digest('hex');
    const prior = Object.hasOwn(this.clients, client) ? this.clients[client] : undefined;
    if (prior && sequence < prior.sequence) throw new Error('sequence already consumed; receipt expired');
    if (prior && sequence === prior.sequence) {
      if (prior.fingerprint !== fingerprint) throw new Error('request identity reused with a different payload');
      return {duplicate: true, receipt: prior.receipt, ...this.snapshot()};
    }
    if (epoch !== this.epoch) throw new Error('stale match epoch');
    if (sequence !== (prior?.sequence ?? 0) + 1) throw new Error('out-of-order command sequence');
    const revision = this.revision + 1, nextEpoch = command.handler === this.resetHandler ? randomUUID() : this.epoch;
    const clients = {...this.clients, [client]: {sequence, fingerprint, receipt: {revision, epoch: nextEpoch}}};
    const record = {revision, client, sequence, handler: command.handler, args: command.args};
    const digest = createHash('sha256').update(JSON.stringify(record)).digest('hex');
    const result = this.runtime.dispatch(1, command, {persist: state => {
      this.commit({state: Array.from(state), revision, epoch: nextEpoch, clients}, this.revision);
    }});
    this.revision = revision; this.epoch = nextEpoch; this.clients = clients;
    this.log.push({...record, digest, internal}); if (this.log.length > 512) this.log.shift();
    const committed = this.snapshot();
    this.publish({type: 'snapshot', ...committed}); // Observers can only see committed state.
    for (const effect of result.effects) this.publish({type: 'effect', revision, effect});
    return committed;
  }
}
