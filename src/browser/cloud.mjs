import {BrowserApplication} from './application.mjs';
import {CloudOutbox} from './cloud-outbox.mjs';

class CloudSession {
  revision = -1; sequence = 1; sending = false;
  constructor(app) { this.app = app; }
  get pending() { return this.outbox?.pending ?? []; }
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
    this.clientKey = `snail.client:${this.app.manifest.settings.id}`;
    const client = sessionStorage.getItem(this.clientKey);
    if (client) this.outbox = new CloudOutbox(this.app.manifest, client);
    const session = await this.post('session', {client});
    this.adopt(session);
    await this.acceptSnapshot(session); this.connect();
    document.addEventListener('visibilitychange', () => {
      if (!this.app.closing) void this.post('presence', {client: this.client, visible: !document.hidden}).catch(error => this.app.note(error.message, 'error'));
    });
  }
  adopt(session) {
    const previous = this.outbox, {pending, discarded} = previous?.reconcile(session) ?? {pending: [], discarded: 0};
    const outbox = previous?.client === session.client ? previous : new CloudOutbox(this.app.manifest, session.client);
    outbox.replace(pending); sessionStorage.setItem(this.clientKey, session.client);
    if (previous && previous !== outbox) previous.replace([]);
    this.outbox = outbox; this.client = session.client;
    this.sequence = pending.length ? pending.at(-1).sequence + 1 : session.next;
    this.rejection = discarded ? 'The colony changed; orders from the previous colony were not sent.' : '';
  }
  describe() {
    if (this.rejection) this.app.note(this.rejection, 'error');
    else if (this.pending.length) this.app.note(`CLOUD · ${this.pending.length} unsaved order(s) · waiting for server · retained across reload in this tab`, 'pending');
    else this.app.note(`CLOUD · Saved on server · revision ${this.revision}`);
  }
  connect() {
    this.events?.close();
    const url = new URL('events', this.app.base); url.searchParams.set('client', this.client);
    this.events = new EventSource(url);
    this.events.onopen = () => this.describe();
    this.events.onmessage = event => this.receive(JSON.parse(event.data));
    this.events.onerror = () => this.app.note('Reconnecting · unsaved orders remain in this tab, including across reload.', 'pending');
  }
  receive(value) {
    if (this.app.closing) return;
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
    this.outbox.append(this.sequence, this.epoch, command); this.sequence++; this.rejection = ''; this.describe();
    // Prediction uses the same Scheme reducer. Only accepted server state is durable.
    try { await this.app.runtime.dispatch(1, command); } catch (error) { this.app.report(error); }
    void this.flush().catch(error => this.app.note(error.message, 'error'));
  }
  async renew(snapshot, retry) {
    if (!retry) this.outbox.replace([]);
    await this.restore(snapshot);
    const renewed = await this.post('session', {client: this.client});
    this.adopt(renewed); await this.restore(renewed); this.connect();
  }
  async recover(error) {
    // The shared UI lane keeps local envelopes behind epoch/sequence renewal.
    const retry = error.message === 'unknown session';
    if (error.body) await this.app.update(() => this.renew(error.body, retry));
    if (error.body && !retry) this.rejection = `Order rejected: ${error.message}. Unsaved orders cleared; server save retained.`;
    if (error.body) this.describe();
    else this.app.note(`Order not acknowledged (${error.message}) · retained in this tab across reload; retrying.`, 'pending');
  }
  async flush() {
    if (this.sending || !this.pending.length || this.app.closing) return; this.sending = true;
    try {
      const order = this.pending[0], result = await this.post('command', order);
      this.outbox.acknowledge(order); await this.acceptSnapshot(result); this.describe();
    } catch (error) { await this.recover(error); }
    finally { this.sending = false; }
    if (this.pending.length && !this.app.closing) setTimeout(() => void this.flush().catch(error => this.app.note(error.message, 'error')), 300);
  }
}
const app = new BrowserApplication(), session = new CloudSession(app);
async function start() {
  try {
    await app.open('cloud'); await session.open();
    if (app.closing) return;
    app.start(session); session.describe(); void session.flush().catch(error => app.note(error.message, 'error'));
  } catch (error) { app.note(`Cannot start: ${error.message}`, 'error'); console.error(error); await app.close(); }
}
const startup = start();
addEventListener('pagehide', () => {
  app.closing = true; session.events?.close();
  void startup.then(() => { session.events?.close(); return app.close(); });
});
addEventListener('pageshow', event => { if (event.persisted) location.reload(); });
