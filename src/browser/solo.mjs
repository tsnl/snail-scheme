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
    const saved = await this.store.load();
    this.local = await LocalState.open(runtime, {saved,
      commit: (snapshot, expected) => this.store.commit(snapshot, expected), publish: output => this.publish(output)});
    if (!saved && manifest.settings.randomSeed) await this.local.submit(this.seedCommand());
    if (manifest.settings.recording && manifest.settings.recording.enabled !== false) {
      const {BrowserRecording} = await import('./recording.mjs');
      this.app.recording = new BrowserRecording(this.app, this);
    }
  }
  seedCommand() {
    const {handler, minimum, maximum} = this.app.manifest.settings.randomSeed;
    const span = maximum - minimum + 1;
    if (!Number.isSafeInteger(minimum) || !Number.isSafeInteger(maximum) || minimum < -2147483648 ||
        maximum > 2147483647 || span < 1 || span > 4294967296)
      throw new Error('randomSeed requires a bounded I32 interval');
    const limit = 4294967296 - (4294967296 % span), sample = new Uint32Array(1);
    do { crypto.getRandomValues(sample); } while (sample[0] >= limit);
    return this.app.runtime.command('match', handler, [minimum + sample[0] % span]);
  }
  checkManifest(next) {
    if (next.settings.id !== this.identity || saveContract(next) !== this.contract
        || JSON.stringify(next.saveService) !== this.saveService)
      throw new Error('incompatible solo save contract; previous code and save retained');
  }
  publish(output) {
    this.app.dirty = true;
    this.app.queueEffects(output.effects);
  }
  async submit(command) {
    try {
      const {settings} = this.app.manifest;
      const reset = command.handler === this.app.runtime.command('match', settings.reset).handler ||
        (settings.randomSeed && command.handler === this.app.runtime.command('match', settings.randomSeed.handler, [0]).handler);
      if (settings.randomSeed && command.handler === this.app.runtime.command('match', settings.reset).handler)
        command = this.seedCommand();
      const result = await this.local.submit(command);
      // Queue after the caller's client transition; awaiting this lane here
      // would deadlock that transition while it waits for its match effect.
      if (reset && settings.resetPresentation && this.app.input) void this.app.local(settings.resetPresentation);
      if (this.faulted) { this.faulted = false; this.startClock(); }
      this.app.note(`SOLO · saved on this browser · revision ${this.revision}`); return result;
    } catch (error) {
      this.stopClock(); await this.recordFailure(error);
      throw error; // Presentation reads the clock state after the admitted tail drains.
    }
  }
  async recordFailure(error) {
    if (!error.reproduction) return;
    try { await this.store.recordFailure(error.reproduction); }
    catch (diagnosticError) { console.error('Could not retain transition diagnostic', diagnosticError); }
  }
  stopClock() { this.faulted = true; clearTimeout(this.timer); }
  startClock() {
    // A manual retry may finish while an earlier tick is still settling.
    if (this.stopping || this.faulted || this.ticking || this.app.recording?.replaying || this.app.recording?.opening) return;
    clearTimeout(this.timer); this.timer = setTimeout(() => void this.tick(), this.app.manifest.settings.tickMilliseconds);
  }
  async tick() {
    this.ticking = true;
    try {
      if (!this.stopping && !this.faulted && !document.hidden && !this.app.recording?.replaying && !this.app.recording?.opening)
        await this.local.submit(this.app.runtime.command('match', this.app.manifest.settings.tick));
    } catch (error) {
      this.stopClock(); await this.recordFailure(error); this.app.report(error);
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
    app.start(session);
    // Restore local presentation only after the saved World is installed.
    if (app.manifest.settings.resetPresentation) {
      await app.local(app.manifest.settings.resetPresentation); await app.drainUpdates();
    }
    session.startClock(); void session.reload();
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
