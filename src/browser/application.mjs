// Shared browser presentation and client-owner transitions. A session supplies
// the concrete authoritative submission: local durable commit or cloud request.
import {ReducerRuntime} from '../application/runtime.mjs';
import {createRenderer} from '../webgpu/quads.mjs';
import {createSceneRenderer} from '../webgpu/scene.mjs';
import {BrowserInput, parseInputSettings} from './input.mjs';
import {DomUi} from '../ui/dom.mjs';

export class BrowserApplication {
  runtime = new ReducerRuntime(); base = new URL('../../', import.meta.url);
  generation = ''; dirty = true; reloadTicket = 0; localWork = 0; updates = Promise.resolve(); closing = false;
  constructor() {
    this.canvas = document.querySelector('canvas'); this.status = document.querySelector('[data-status]');
    this.connection = document.querySelector('[data-connection]');
    const root = document.querySelector('[data-ui]');
    if (root) {
      this.ui = new DomUi(root, action => this.uiCommand(action));
      this.uiResize = new ResizeObserver(([entry]) => {
        this.runtime.uiBridge.resize(entry.contentRect.width, entry.contentRect.height); this.dirty = true;
      });
      this.uiResize.observe(root);
    }
  }
  get revision() { return this.session?.revision ?? -1; }
  get pending() { return this.session?.pending ?? []; }
  note(text, state = 'quiet') {
    if (this.connection.textContent !== text) this.connection.textContent = text;
    this.connection.dataset.state = state;
  }
  update(operation) {
    // Browser operations may await network renewal or GPU preparation. They
    // call into the runtime FIFO; runtime messages never wait on this lane.
    if (this.closing) return Promise.reject(new Error('Browser application is closing'));
    const result = this.updates.then(operation); this.updates = result.catch(() => {}); return result;
  }
  async open(target) {
    this.target = target;
    await this.reload();
  }
  async reload() {
    const ticket = ++this.reloadTicket;
    const next = await (await fetch(new URL('manifest.json', this.base), {cache: 'no-store'})).json();
    if (next.target !== this.target) throw new Error(`Expected a ${this.target} package`);
    if (next.generation === this.generation) return;
    this.session?.checkManifest(next);
    if (this.rendererKind && this.rendererKind !== (next.settings.renderer ?? 'quads'))
      throw new Error('renderer changes require a page reload');
    if (!this.renderer && next.settings.renderer !== 'dom') {
      const create = next.settings.renderer === 'scene3d' ? createSceneRenderer : createRenderer;
      this.renderer = await create(this.canvas, error => this.note(error.message));
      this.rendererKind = next.settings.renderer ?? 'quads';
    }
    await this.prepareGeneration(next, ticket);
  }
  async prepareGeneration(next, ticket) {
    const settings = parseInputSettings(next.settings);
    const [bytes, source] = await Promise.all([fetch(new URL(next.module, this.base)).then(r => r.arrayBuffer()),
      fetch(new URL(next.shader, this.base)).then(r => r.text())]);
    const candidate = this.runtime.prepare(new Uint8Array(bytes), next);
    try {
      const pipeline = await this.renderer?.prepare(source);
      await this.update(() => this.install(candidate, pipeline, settings, ticket));
    } catch (error) { this.runtime.discard(candidate); throw error; }
  }
  async install(candidate, pipeline, settings, ticket) {
    if (ticket !== this.reloadTicket) { this.runtime.discard(candidate); return; }
    await this.runtime.replace(candidate); this.renderer?.replace(pipeline);
    this.manifest = this.runtime.manifest; this.generation = this.manifest.generation;
    this.inputSettings = this.viewport ? {...settings, width: this.viewport[0], height: this.viewport[1]} : settings;
    await this.runtime.initialize(1); await this.runtime.initialize(2); this.dirty = true;
    this.note(`LIVE · ${this.pending.length ? `${this.pending.length} unsaved orders retained in this tab` : 'state preserved'} · ${this.generation.slice(0, 7)}`,
      this.pending.length ? 'pending' : 'quiet');
  }
  start(session) {
    this.session = session;
    this.input = new BrowserInput(this.canvas, () => this.inputSettings, (binding, args) => this.local(binding, args));
    if (this.manifest.settings.viewportHandler) {
      this.viewportResize = new ResizeObserver(() => this.resizeViewport());
      this.viewportResize.observe(this.canvas); this.resizeViewport();
    }
    requestAnimationFrame(time => this.frame(time));
    globalThis.snailApp = this; // Executable browser diagnostics.
  }
  local(binding, args = []) {
    const command = this.runtime.command('client', binding, args.slice()); this.localWork++;
    return this.update(() => this.localTransition(command)).catch(error => this.report(error)).finally(() => this.localWork--);
  }
  uiCommand({owner, command}) {
    this.localWork++;
    return this.update(() => owner === 2 ? this.localTransition(command) : this.session.submit(command))
      .then(() => { this.dirty = true; return true; })
      .catch(error => { this.report(error); return false; }).finally(() => this.localWork--);
  }
  resizeViewport() {
    const rect = this.canvas.getBoundingClientRect();
    const width = Math.max(1, Math.floor(rect.width)), height = Math.max(1, Math.floor(rect.height));
    if (this.viewport?.[0] === width && this.viewport?.[1] === height) return;
    this.viewport = [width, height]; this.inputSettings = {...this.inputSettings, width, height};
    const scale = Math.min(devicePixelRatio || 1, 2);
    this.canvas.width = Math.round(width * scale); this.canvas.height = Math.round(height * scale);
    void this.local(this.manifest.settings.viewportHandler, [width, height]);
  }
  async localTransition(command) {
    const result = await this.runtime.dispatch(2, command);
    for (const effect of result.effects) {
      if (effect.kind === 'send' && effect.owner === 1) await this.session.submit(this.runtime.effectCommand(effect));
      else if (effect.kind === 'notice') this.note(effect.text);
    }
    this.dirty = true;
  }
  acceptSnapshot(snapshot) { return this.session.acceptSnapshot(snapshot); }
  reconcileGeneration() {
    if (this.manifest && this.generation !== this.runtime.manifest.generation) {
      this.manifest = this.runtime.manifest; this.generation = this.manifest.generation; this.renderer?.rollback();
      const settings = parseInputSettings(this.manifest.settings);
      this.inputSettings = this.viewport ? {...settings, width: this.viewport[0], height: this.viewport[1]} : settings;
      this.dirty = true;
    }
  }
  report(error) {
    this.reconcileGeneration(); this.dirty = true;
    this.note(`Transition rejected; committed state retained: ${error.message}`, 'error');
  }
  frame(time) {
    if (this.closing) return;
    this.reconcileGeneration();
    if (!this.localWork) this.input.frame(time);
    else this.input.time = time; // Never accumulate held-input catch-up behind a save.
    if (this.dirty && !document.hidden) {
      try { this.draw(); } catch (error) { this.report(error); }
    }
    requestAnimationFrame(next => this.frame(next));
  }
  draw() {
    const presentation = this.runtime.view();
    this.renderer?.draw(presentation.scene ?? presentation.quads, this.inputSettings.width, this.inputSettings.height);
    this.ui?.render(presentation.ui);
    this.status.textContent = presentation.label; this.dirty = false;
  }
  async close() {
    this.closing = true;
    this.uiResize?.disconnect();
    this.viewportResize?.disconnect();
    await this.updates; // UI work already accepted may still submit to the runtime.
    await this.runtime.close();
    await this.renderer?.close();
  }
}
