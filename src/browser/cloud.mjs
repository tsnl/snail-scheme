import {BrowserApplication} from './application.mjs';

class CloudSession {
  pending = []; revision = -1; sequence = 1; sending = false;
  constructor(app) { this.app = app; }
  checkManifest(next) {
    if (next.settings.id !== this.app.manifest.settings.id || next.settings.runMarker !== this.app.manifest.settings.runMarker)
      throw new Error('incompatible application identity or run marker');
  }
  async post(path, value) {
    const response = await fetch(new URL(path, this.app.base), {method: 'POST',
      headers: {'content-type': 'application/json'}, body: JSON.stringify(value)});
    const body = await response.json();
    if (!response.ok) throw Object.assign(new Error(body.error), {body}); return body;
  }
  async open() {
    const key = `snail.client:${this.app.manifest.settings.id}`;
    const session = await this.post('session', {client: sessionStorage.getItem(key)});
    this.client = session.client; this.sequence = session.next; sessionStorage.setItem(key, this.client);
    await this.acceptSnapshot(session); this.connect();
  }
  connect() {
    const url = new URL('events', this.app.base); url.searchParams.set('client', this.client);
    this.events = new EventSource(url);
    this.events.onmessage = event => this.receive(JSON.parse(event.data));
    this.events.onerror = () => this.app.note('Reconnecting · local selection and pending commands retained');
    document.addEventListener('visibilitychange', () => void this.post('presence', {client: this.client, visible: !document.hidden}).catch(error => this.app.note(error.message)));
  }
  receive(value) {
    if (value.type === 'snapshot') void this.acceptSnapshot(value).catch(error => this.app.report(error));
    else if (value.type === 'reload') void this.app.reload().catch(error => this.app.note(`Reload rejected; previous code stays live: ${error.message}`));
    else if (value.type === 'reload-error' || value.type === 'error') this.app.note(`Previous code stays live: ${value.error}`);
  }
  acceptSnapshot(snapshot) {
    snapshot = structuredClone(snapshot); return this.app.update(() => this.restore(snapshot));
  }
  async restore(snapshot) {
    if (snapshot.revision < this.revision) return;
    await this.app.runtime.restore(1, snapshot.state); this.revision = snapshot.revision; this.epoch = snapshot.epoch; this.app.dirty = true;
  }
  async submit(command) {
    this.pending.push({client: this.client, sequence: this.sequence++, epoch: this.epoch, command});
    // Prediction uses the same Scheme reducer. Only accepted server state is durable.
    try { await this.app.runtime.dispatch(1, command); } catch (error) { this.app.report(error); }
    void this.flush().catch(error => this.app.note(error.message));
  }
  async renew(snapshot) {
    this.pending.length = 0; await this.restore(snapshot);
    const renewed = await this.post('session', {client: this.client});
    await this.restore(renewed); this.sequence = renewed.next;
  }
  async recover(error) {
    // The shared UI lane keeps local envelopes behind epoch/sequence renewal.
    if (error.body) await this.app.update(() => this.renew(error.body));
    this.app.note(`${error.message} · ${error.body ? 'session renewed' : 'pending commands retained for retry'}`);
  }
  async flush() {
    if (this.sending || !this.pending.length || this.app.closing) return; this.sending = true;
    try {
      const result = await this.post('command', this.pending[0]); this.pending.shift(); await this.acceptSnapshot(result);
      this.app.note(`CLOUD · revision ${this.revision} · ${this.pending.length} pending`);
    } catch (error) { await this.recover(error); }
    finally { this.sending = false; }
    if (this.pending.length) setTimeout(() => void this.flush().catch(error => this.app.note(error.message)), 300);
  }
}
const app = new BrowserApplication();
try {
  await app.open('cloud'); const session = new CloudSession(app); await session.open(); app.start(session);
  app.note(`CLOUD · player ${session.client.slice(0, 6)} · server save · WebGPU`);
} catch (error) { app.note(`Cannot start: ${error.message}`); console.error(error); await app.close(); }
