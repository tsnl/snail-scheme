import {BrowserApplication} from './application.mjs';
import {LocalState} from '../application/local.mjs';
import {acquireWriter, openStore, saveContract} from '../application/indexeddb.mjs';

class SoloSession {
  stopping = false; faulted = false;
  constructor(app) { this.app = app; }
  get revision() { return this.local.revision; }
  async open() {
    const {manifest, runtime} = this.app;
    this.identity = manifest.settings.id; this.contract = saveContract(manifest);
    this.saveService = JSON.stringify(manifest.saveService);
    this.release = await acquireWriter(manifest.settings.id);
    this.store = await openStore(manifest);
    this.local = await LocalState.open(runtime, {saved: await this.store.load(),
      commit: (snapshot, expected) => this.store.commit(snapshot, expected), publish: output => this.publish(output)});
  }
  checkManifest(next) {
    if (next.settings.id !== this.identity || saveContract(next) !== this.contract
        || JSON.stringify(next.saveService) !== this.saveService)
      throw new Error('incompatible solo save contract; previous code and save retained');
  }
  publish(output) {
    this.app.dirty = true;
    for (const effect of output.effects) if (effect.kind === 'notice') this.app.note(effect.text);
  }
  async submit(command) {
    try {
      const result = await this.local.submit(command);
      if (this.faulted) { this.faulted = false; this.startClock(); }
      this.app.note(`SOLO · saved on this browser · revision ${this.revision}`); return result;
    } catch (error) { this.stopClock(); throw new Error(`${error.message}; clock stopped. Retry the action or reload.`, {cause: error}); }
  }
  stopClock() { this.faulted = true; clearTimeout(this.timer); }
  startClock() {
    // A manual retry may finish while an earlier tick is still settling.
    if (this.stopping || this.faulted || this.ticking) return;
    clearTimeout(this.timer); this.timer = setTimeout(() => void this.tick(), this.app.manifest.settings.tickMilliseconds);
  }
  async tick() {
    this.ticking = true;
    try {
      if (!this.stopping && !this.faulted && !document.hidden)
        await this.local.submit(this.app.runtime.command('match', this.app.manifest.settings.tick));
    } catch (error) {
      this.stopClock(); this.app.report(new Error(`${error.message}; clock stopped. Retry an action or reload.`, {cause: error}));
    }
    finally { this.ticking = false; this.startClock(); }
  }
  async reload() {
    try { await this.app.reload(); }
    catch (error) { this.app.note(`Reload rejected; previous code stays live: ${error.message}`); }
    finally { if (!this.stopping) this.reloading = setTimeout(() => void this.reload(), 1000); }
  }
  close() {
    if (this.closed) return this.closed;
    this.stopping = true; clearTimeout(this.timer); clearTimeout(this.reloading);
    this.closed = this.drain(); return this.closed;
  }
  async drain() {
    this.saves?.close(); await this.app.close(); this.store?.close(); await this.release?.();
  }
}
const app = new BrowserApplication(), session = new SoloSession(app);
async function start() {
  try {
    await app.open('solo'); await session.open();
    if (session.stopping) { await session.close(); return; }
    app.start(session); session.startClock(); void session.reload();
    app.note(`SOLO · saved on this browser · ${app.manifest.settings.renderer === 'dom' ? 'DOM' : 'WebGPU'}`);
    if (app.manifest.saveService) {
      const {RemoteSaves} = await import('../application/remote-saves.mjs');
      if (!session.stopping) session.saves = new RemoteSaves(app, session);
    }
  } catch (error) { app.note(`Cannot start: ${error.message}`); console.error(error); await session.close(); }
}
const startup = start();
addEventListener('pagehide', () => {
  app.closing = true; // Stop UI admission even while startup cleanup is deferred.
  session.stopping = true; clearTimeout(session.timer); clearTimeout(session.reloading);
  void startup.then(() => session.close()); // Also handles leaving during asynchronous open.
});
addEventListener('pageshow', event => { if (event.persisted) location.reload(); });
