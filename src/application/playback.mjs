// Snapshot playback has its own Wasm heap and Client. It never routes effects,
// runs World commands, or receives a persistence function.
import {ReducerRuntime} from './runtime.mjs';
import {compatibleRecording} from './recording.mjs';

export class SnapshotPlayback {
  runtime = new ReducerRuntime();
  static async open(bytes, manifest, recording, client) {
    if (!compatibleRecording(recording, manifest)) throw new Error('Recording schema or endpoint contract is incompatible with this renderer');
    const playback = new SnapshotPlayback(); playback.recording = recording;
    try { await playback.initialize(bytes, manifest, client); return playback; }
    catch (error) { await playback.close(); throw error; }
  }
  async initialize(bytes, manifest, client) {
    await this.runtime.replace(this.runtime.prepare(bytes, manifest));
    await this.runtime.initialize(1); await this.runtime.initialize(2);
    if (client) await this.runtime.restore(2, client);
    await this.seek(this.recording.last);
    const settings = manifest.settings.recording;
    this.cameraHandlers = new Set(settings?.cameraHandlers ?? []);
    if (settings?.prepareCamera) await this.runtime.dispatch(2, this.runtime.command('client', settings.prepareCamera));
  }
  async seek(sequence) {
    const words = this.recording.snapshot(sequence);
    await this.runtime.restore(1, Array.from(words));
    this.sequence = sequence; this.entry = this.recording.entry(sequence); return this.entry;
  }
  async camera(command) {
    const handler = this.runtime.manifest.applications.find(app => app.owner === 'client').handlers.find(value => value.id === command.handler);
    if (!this.cameraHandlers.has(handler?.binding)) return;
    await this.runtime.dispatch(2, command); // All returned effects are deliberately discarded.
  }
  inspect() {
    const projection = this.runtime.manifest.settings.recording?.inspection;
    if (!projection || this.runtime.inspect(-1) !== projection.version) throw new Error('No compatible diagnostic projection');
    return Object.fromEntries(projection.fields.map((field, index) => [field, this.runtime.inspect(index)]));
  }
  close() { return this.runtime.close(); }
}
