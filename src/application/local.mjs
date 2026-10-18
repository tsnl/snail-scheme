// One browser owns game state. A transition becomes visible only after its
// IndexedDB write completes; presentation state shares the runtime's FIFO.
export class LocalState {
  revision = 0;
  constructor(runtime, {commit = () => {}, publish = () => {}} = {}) {
    this.runtime = runtime; this.commit = commit; this.publish = publish;
  }
  static async open(runtime, {saved, ...options} = {}) {
    const local = new LocalState(runtime, options);
    if (saved) {
      if (!Number.isSafeInteger(saved.revision) || saved.revision < 0) throw new Error('Invalid saved revision');
      await runtime.restore(1, saved.state); local.revision = saved.revision;
    }
    return local;
  }
  snapshot() { return {revision: this.revision, state: this.runtime.snapshot(1)}; }
  transaction() {
    let checkpoint;
    return {
      persist: state => {
        checkpoint = Object.freeze({revision: this.revision + 1, state});
        return this.commit(checkpoint, this.revision);
      },
      publish: output => { this.revision = checkpoint.revision; this.publish(output); },
    };
  }
  submit(command) { return this.runtime.dispatch(1, command, this.transaction()); }
  restore(state) { return this.runtime.restore(1, state, this.transaction()); }
}
