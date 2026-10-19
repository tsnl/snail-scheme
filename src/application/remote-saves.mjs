// Optional, explicit checkpoint transfer. Network I/O never owns the reducer
// lane. Loading validates and durably replaces state in one local transition.
import {readRecord, saveContract} from './indexeddb.mjs';

export class RemoteSaves {
  constructor(app, session) {
    this.app = app; this.session = session;
    this.url = new URL(app.manifest.settings.id, new URL(app.manifest.saveService.url, app.base));
    this.controller = new AbortController(); this.etag = undefined;
    this.controls = document.createElement('section'); this.controls.className = 'remote-saves';
    this.controls.setAttribute('aria-label', 'Online saves');
    this.saveButton = this.button('Save online', () => this.save());
    this.loadButton = this.button('Load online', () => this.load());
    this.status = document.createElement('span'); this.status.setAttribute('role', 'status');
    this.status.textContent = 'Automatic saves stay on this browser.';
    this.controls.append(this.status); document.body.append(this.controls);
  }
  button(label, operation) {
    const button = document.createElement('button'); button.textContent = label;
    button.addEventListener('click', () => void this.run(operation)); this.controls.append(button); return button;
  }
  async run(operation) {
    if (this.busy || this.app.recording?.replaying || this.app.recording?.opening) return;
    this.busy = true; this.saveButton.disabled = this.loadButton.disabled = true;
    try { await operation(); }
    catch (error) { if (!this.controller.signal.aborted) this.status.textContent = `${error.message} Local progress is saved.`; }
    finally { this.busy = false; this.saveButton.disabled = this.loadButton.disabled = false; }
  }
  async request(options) {
    const response = await fetch(this.url, {...options, signal: AbortSignal.any([this.controller.signal, AbortSignal.timeout(10000)]),
      credentials: 'same-origin', cache: 'no-store'});
    if (response.status === 412) throw new Error('The online save changed. Load it before saving again.');
    if (response.status === 404) throw new Error('No online save yet.');
    if (!response.ok) throw new Error(`Online save service returned ${response.status}.`);
    return response;
  }
  async save() {
    // Capture a committed checkpoint without waiting on, or blocking, gameplay.
    const record = this.session.store.record(this.session.local.snapshot());
    const response = await this.request({method: 'PUT', headers: {'content-type': 'application/json',
      ...(this.etag ? {'if-match': this.etag} : {'if-none-match': '*'})}, body: JSON.stringify(record)});
    this.etag = response.headers.get('etag'); this.status.textContent = 'Checkpoint saved online.';
  }
  async load() {
    const response = await this.request({method: 'GET'}), record = await response.json();
    const snapshot = readRecord(record, this.app.manifest.settings.id, saveContract(this.app.manifest));
    if (!snapshot) throw new Error('Invalid online checkpoint.');
    const accepted = await this.app.update(async () => {
      if (this.app.recording?.replaying || this.app.recording?.opening)
        throw new Error('Return to the colony before loading an online checkpoint.');
      if (!confirm('Replace this browser’s colony with the online checkpoint?')) return false;
      await this.session.local.restore(snapshot.state);
      // Already inside the browser lane: apply the configured import hook
      // directly, after durability, without waiting on a nested app.local.
      if (this.app.manifest.settings.resetPresentation)
        await this.app.localTransition(this.app.runtime.command('client', this.app.manifest.settings.resetPresentation));
      return true;
    });
    if (!accepted) return;
    this.etag = response.headers.get('etag'); this.status.textContent = 'Online checkpoint loaded and saved on this browser.';
  }
  close() { this.controller.abort(); this.controls.remove(); }
}
