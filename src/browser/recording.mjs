import {RunRecording, recordingLimits} from '../application/recording.mjs';
import {SnapshotPlayback} from '../application/playback.mjs';

function button(label, key, action) {
  const node = document.createElement('button'); node.type = 'button'; node.textContent = label;
  node.dataset.recording = key; node.addEventListener('click', action); return node;
}
function download(blob, filename) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a'); link.href = url; link.download = filename; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

// Host diagnostics appear only beside Pause or during read-only playback.
// The live recording and saved colony remain separate from imported history.
export class BrowserRecording {
  opening = false; replaying = false; playing = false; playEpoch = 0; request = 0;
  constructor(app, session) {
    this.app = app; this.session = session;
    this.recording = RunRecording.start(app.runtime, {revision: () => session.revision});
    app.runtime.recording = this.recording; this.createControls();
  }
  createControls() {
    this.root = document.createElement('section'); this.root.className = 'snail-recording'; this.root.hidden = true;
    this.root.setAttribute('aria-label', 'Game recording'); this.message = document.createElement('p');
    this.message.setAttribute('role', 'status'); this.actions = document.createElement('div'); this.actions.className = 'snail-recording-actions';
    this.toggle = button('Recording on', 'record', () => this.toggleRecording());
    this.replayButton = button('Replay', 'replay', () => this.run(() => this.replay()));
    this.exportButton = button('Export dump', 'export', () => this.export());
    this.importButton = button('Open dump', 'import', () => this.file.click());
    this.actions.append(this.toggle, this.replayButton, this.exportButton, this.importButton);
    this.createPlaybackControls(); this.createFileInput();
    this.root.append(this.message, this.actions, this.playbackControls, this.file); document.body.append(this.root);
    const css = document.createElement('link'); css.rel = 'stylesheet'; css.href = new URL('./recording.css', import.meta.url); document.head.append(css);
  }
  createPlaybackControls() {
    this.playbackControls = document.createElement('div'); this.playbackControls.hidden = true;
    this.slider = document.createElement('input'); this.slider.type = 'range'; this.slider.step = 1;
    this.slider.setAttribute('aria-label', 'Recorded transition'); this.slider.dataset.recording = 'position';
    this.slider.addEventListener('input', () => { this.pause(); this.run(() => this.seek(Number(this.slider.value))); });
    this.playButton = button('Play', 'play', () => this.playing ? this.pause() : this.play());
    this.closeButton = button('Return to colony', 'close', () => this.run(() => this.exit()));
    this.playbackControls.append(this.slider, this.playButton, this.closeButton);
  }
  createFileInput() {
    this.file = document.createElement('input'); this.file.type = 'file'; this.file.accept = '.snailrun'; this.file.hidden = true;
    this.file.addEventListener('change', () => this.run(async () => {
      const file = this.file.files[0]; if (!file) return;
      if (file.size > recordingLimits.fileBytes) throw new Error('Recording exceeds the 72 MiB file limit');
      await this.replay(RunRecording.import(await file.arrayBuffer())); this.file.value = '';
    }));
  }
  run(operation) { return Promise.resolve().then(operation).catch(error => { this.message.textContent = error.message; this.error = error.message; }); }
  toggleRecording() {
    if (this.recording.enabled) this.recording.stop(); else this.recording.resume(this.app.runtime);
    this.app.dirty = true;
  }
  export() {
    const recording = this.playback?.recording ?? this.recording;
    download(recording.exportBlob(), `${this.app.manifest.settings.id}-${recording.startedAt.replaceAll(':', '-')}.snailrun`);
  }
  async replay(recording = this.recording) {
    const request = ++this.request; this.opening = true; this.pause(); clearTimeout(this.session.timer); this.app.dirty = true;
    try {
      // Reverse replies join the browser lane after a durable World commit.
      // Drain them while routing still targets live Client, then switch owners.
      await this.app.drainUpdates(); await this.app.runtime.message(() => {}); await this.app.drainUpdates();
      if (request === this.request) await this.app.update(() => this.openPlayback(recording, request));
    } finally {
      if (request === this.request) { this.opening = false; this.app.dirty = true; if (!this.replaying) this.session.startClock(); }
    }
  }
  async openPlayback(recording, request) {
    if (request !== this.request) return;
    this.replaying = true;
    try {
      const bytes = new Uint8Array(await (await fetch(new URL(this.app.manifest.module, this.app.base))).arrayBuffer());
      const next = await SnapshotPlayback.open(bytes, this.app.manifest, recording, this.app.runtime.snapshot(2));
      if (request !== this.request) { await next.close(); return; }
      await this.playback?.close();
      if (request !== this.request) { await next.close(); return; }
      this.playback = next; this.error = '';
      const rect = this.app.ui?.root.getBoundingClientRect(); if (rect) next.runtime.uiBridge.resize(rect.width, rect.height);
      if (this.app.viewport) await next.camera(next.runtime.command('client', this.app.manifest.settings.viewportHandler, this.app.viewport));
      this.app.input.reset(); this.app.dirty = true;
    } catch (error) { if (!this.playback) { this.replaying = false; this.session.startClock(); } throw error; }
  }
  seek(sequence) {
    return this.app.update(async () => { await this.playback.seek(sequence); this.app.dirty = true; });
  }
  play() {
    if (!this.playback) return;
    this.playing = true; this.playButton.textContent = 'Stop'; void this.advance(++this.playEpoch);
  }
  async advance(epoch) {
    if (!this.playing || !this.playback || epoch !== this.playEpoch) return;
    if (this.playback.sequence >= this.playback.recording.last) { this.pause(); return; }
    try { await this.seek(this.playback.sequence + 1); }
    catch (error) { this.error = error.message; this.pause(); }
    if (this.playing && epoch === this.playEpoch)
      this.timer = setTimeout(() => void this.advance(epoch), this.app.manifest.settings.tickMilliseconds);
  }
  pause() { this.playing = false; this.playEpoch++; clearTimeout(this.timer); this.playButton.textContent = 'Play'; }
  exit() { this.request++; this.opening = false; return this.app.update(() => this.closePlayback()); }
  async closePlayback() {
    this.pause(); await this.playback?.close(); this.playback = undefined; this.replaying = false;
    this.app.input.reset(); this.app.dirty = true; this.session.startClock();
  }
  render() {
    const menu = this.app.ui?.nodes.has(this.app.manifest.settings.recording.menuKey);
    this.root.hidden = !menu && !this.replaying && !this.opening; this.playbackControls.hidden = !this.playback;
    if (this.app.ui) this.app.ui.root.inert = this.replaying || this.opening;
    if (this.session.saves) this.session.saves.controls.inert = this.replaying || this.opening;
    if (this.root.hidden) return;
    for (const control of [this.toggle, this.replayButton, this.importButton, this.playButton, this.slider]) control.disabled = this.opening;
    this.toggle.hidden = this.replaying; this.replayButton.hidden = this.replaying;
    this.toggle.textContent = this.recording.enabled ? 'Recording on' : 'Record again';
    if (this.opening) this.message.textContent = 'Opening recording…';
    else if (this.playback) this.renderPosition();
    else this.message.textContent = this.error || this.retentionText(this.recording);
  }
  retentionText(recording) {
    const stats = recording.stats(), bytes = (stats.wordBytes + stats.metadataBytes) / 1048576;
    const start = stats.dropped ? `Earlier ${stats.dropped} entries removed. ` : 'From this page’s checkpoint. ';
    return `${start}${stats.entries} states · ${bytes.toFixed(1)} MiB. ${stats.reason}`;
  }
  renderPosition() {
    const playback = this.playback, recording = playback.recording;
    this.slider.min = recording.first; this.slider.max = recording.last; this.slider.value = playback.sequence;
    const generation = playback.entry.generation.slice(0, 7), renderer = this.app.generation.slice(0, 7);
    const run = playback.entry.run === null ? '' : `Run ${playback.entry.run} · `;
    this.message.textContent = this.error || `${run}Replay ${playback.sequence - recording.first + 1}/${recording.length} · read only · recorded ${generation}, renderer ${renderer}. ${recording.dropped ? 'Start truncated.' : 'From page checkpoint.'}`;
  }
  async close() { this.pause(); await this.playback?.close(); this.recording.stop(); this.root.remove(); }
}
