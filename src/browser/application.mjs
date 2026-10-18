// Shared browser presentation and client-owner transitions. A session supplies
// local durable game transitions. All simulation runs in this browser.
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
  note(text, state = 'quiet') {
    if (this.connection.textContent !== text) this.connection.textContent = text;
    this.connection.dataset.state = state;
  }
  update(operation) {
    // Browser operations may await network renewal or GPU preparation. They
    // call into the runtime FIFO; runtime messages never wait on this lane.
    if (this.closing) return Promise.reject(new Error('Browser application is closing'));
    return this.continueUpdate(operation);
  }
  continueUpdate(operation) {
    // Work emitted by an admitted transition also drains during close.
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
    this.applySettings(settings);
    await this.runtime.initialize(1); await this.runtime.initialize(2); this.dirty = true;
    this.note(`LIVE · state preserved · ${this.generation.slice(0, 7)}`);
  }
  applySettings(settings) {
    this.inputSettings = this.viewport ? {...settings, width: this.viewport[0], height: this.viewport[1]} : settings;
    this.canvas.style.imageRendering = settings.renderScale < 1 ? 'pixelated' : '';
    if (this.viewport) this.resizeViewport();
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
    // The returned promise includes outgoing durable World orders. Reverse
    // Client effects enter the FIFO after publication and run in later turns.
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
    const scale = (devicePixelRatio || 1) * this.inputSettings.renderScale;
    const changed = this.viewport?.[0] !== width || this.viewport?.[1] !== height;
    if (!changed && this.viewportScale === scale) return;
    // Only the backing buffer uses physical pixels. Input, camera and DOM keep CSS units.
    this.viewportScale = scale;
    const pixelsWide = Math.max(1, Math.round(width * scale)), pixelsHigh = Math.max(1, Math.round(height * scale));
    if (this.canvas.width !== pixelsWide) this.canvas.width = pixelsWide;
    if (this.canvas.height !== pixelsHigh) this.canvas.height = pixelsHigh;
    this.dirty = true;
    if (!changed) return;
    this.viewport = [width, height]; this.inputSettings = {...this.inputSettings, width, height};
    void this.local(this.manifest.settings.viewportHandler, [width, height]);
  }
  async localTransition(command) {
    const result = await this.runtime.dispatch(2, command);
    this.dirty = true; // The committed Client can show progress while World saves.
    await this.routeEffects(result.effects);
    this.dirty = true;
  }
  queueEffects(effects) {
    // Publication runs inside the runtime FIFO. Never await this browser lane
    // there: its current Client turn may be waiting for that durable commit.
    for (const effect of effects)
      void this.continueUpdate(() => this.deliverEffect(effect)).catch(error => this.report(error));
  }
  async deliverEffect(effect) {
    if (effect.kind === 'notice') this.note(effect.text);
    else if (effect.owner === 1) await this.session.submit(this.runtime.effectCommand(effect));
    else await this.localTransition(this.runtime.effectCommand(effect));
  }
  async routeEffects(effects) {
    const failures = [];
    for (const effect of effects) {
      if (effect.kind === 'send' && effect.owner === 1) {
        try { await this.session.submit(this.runtime.effectCommand(effect)); }
        catch (error) { failures.push(error); }
      } else this.queueEffects([effect]);
    }
    // Authored settlement messages still run when a preceding save fails.
    if (failures.length) void this.continueUpdate(() => this.report(failures.length === 1 ? failures[0]
      : new AggregateError(failures, failures.map(error => error.message).join('; '))));
    this.dirty = true;
  }
  reconcileGeneration() {
    if (this.manifest && this.generation !== this.runtime.manifest.generation) {
      this.manifest = this.runtime.manifest; this.generation = this.manifest.generation; this.renderer?.rollback();
      this.applySettings(parseInputSettings(this.manifest.settings));
      this.dirty = true;
    }
  }
  report(error) {
    this.reconcileGeneration(); this.dirty = true;
    const clock = this.session?.faulted ? '; clock stopped. Retry the action or reload.' : '';
    this.note(`Transition rejected; committed state retained: ${error.message}${clock}`, 'error');
  }
  frame(time) {
    if (this.closing) return;
    this.reconcileGeneration();
    if (this.viewport && this.viewportScale !== (devicePixelRatio || 1) * this.inputSettings.renderScale) this.resizeViewport();
    if (!this.localWork) this.input.frame(time);
    else this.input.time = time; // Never accumulate held-input catch-up behind a save.
    const elapsed = this.animationTime === undefined ? 0 : Math.max(0, Math.min(50, Math.round(time - this.animationTime)));
    this.animationTime = time;
    if (this.animateClient && !this.localWork && !document.hidden && elapsed && this.manifest.settings.animationHandler)
      void this.local(this.manifest.settings.animationHandler, [elapsed]);
    if (this.dirty && !document.hidden) {
      try { this.draw(); } catch (error) { this.report(error); }
    } else if (!document.hidden) this.renderer?.animate?.(time);
    requestAnimationFrame(next => this.frame(next));
  }
  draw() {
    const presentation = this.runtime.view();
    this.animateClient = !!presentation.scene?.requestFrame;
    this.renderer?.draw(presentation.scene ?? presentation.quads, this.inputSettings.width, this.inputSettings.height);
    this.ui?.render(presentation.ui);
    this.status.textContent = presentation.label; this.dirty = false;
  }
  async close() {
    this.closing = true;
    this.uiResize?.disconnect();
    this.viewportResize?.disconnect();
    await this.drainUpdates();
    // A clock save can publish replies independently of a browser operation.
    await this.runtime.message(() => {});
    await this.drainUpdates();
    await this.runtime.close();
    await this.renderer?.close();
  }
  async drainUpdates() {
    let pending;
    do { pending = this.updates; await pending; } while (pending !== this.updates);
  }
}
