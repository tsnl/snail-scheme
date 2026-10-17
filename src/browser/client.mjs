// Browser platform bindings only. Scheme owns both the immutable client model
// and all game transitions; the authority owns accepted world revisions.
import {ReducerRuntime} from '../application/runtime.mjs';
import {createRenderer} from '../webgpu/quads.mjs';

const canvas = document.querySelector('canvas'), status = document.querySelector('[data-status]');
const connection = document.querySelector('[data-connection]');
const runtime = new ReducerRuntime(), pending = [];
let manifest, renderer, session, revision = -1, epoch, sequence = 1, sending = false, generation = '', dirty = true, reloadTicket = 0;
const post = async (path, value) => {
  const response = await fetch(path, {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify(value)});
  const body = await response.json(); if (!response.ok) throw Object.assign(new Error(body.error), {body}); return body;
};
function note(text) { connection.textContent = text; }
async function loadGeneration() {
  const ticket = ++reloadTicket;
  const next = await (await fetch('/manifest.json', {cache: 'no-store'})).json();
  if (next.generation === generation) return;
  const [bytes, source] = await Promise.all([fetch(`/${next.module}`).then(r => r.arrayBuffer()), fetch(`/${next.shader}`).then(r => r.text())]);
  const candidate = runtime.prepare(new Uint8Array(bytes), next);
  let pipeline;
  try {
    pipeline = await renderer.prepare(source);
    if (ticket !== reloadTicket) { runtime.discard(candidate); return; }
    runtime.replace(candidate);
  }
  catch (error) { runtime.discard(candidate); throw error; }
  renderer.replace(pipeline); manifest = next; generation = next.generation;
  runtime.initialize(1); runtime.initialize(2); dirty = true;
  note(`LIVE · ${pending.length ? `${pending.length} pending` : 'state preserved'} · ${generation.slice(0, 7)}`);
}
function applySnapshot(snapshot) {
  if (snapshot.revision < revision) return;
  runtime.restore(1, snapshot.state); revision = snapshot.revision; epoch = snapshot.epoch; dirty = true;
}
function local(binding, args = []) {
  let result;
  try { result = runtime.dispatch(2, runtime.command('client', binding, args)); }
  catch (error) { reportTransitionFailure(error); return; }
  for (const effect of result.effects) {
    if (effect.kind === 'send' && effect.owner === 1) {
      const command = runtime.effectCommand(effect);
      pending.push({client: session.client, sequence: sequence++, epoch, command});
      // Speculation uses exactly the same Scheme reducer; accepted server state
      // replaces it on reply. No prediction is persisted as authoritative data.
      try { runtime.dispatch(1, command); } catch (error) { reportTransitionFailure(error); }
    } else if (effect.kind === 'notice') note(String.fromCodePoint(...effect.chars));
  }
  dirty = true; void flush();
}
function reportTransitionFailure(error) {
  if (generation !== runtime.manifest.generation) {
    manifest = runtime.manifest; generation = manifest.generation; renderer.rollback();
  }
  dirty = true; note(`Transition rejected; committed state retained: ${error.message}`);
}
async function flush() {
  if (sending || !pending.length) return; sending = true;
  try {
    const result = await post('/command', pending[0]); pending.shift(); applySnapshot(result);
    note(`LIVE · revision ${revision} · ${pending.length} pending`);
  } catch (error) {
    if (error.body) {
      pending.length = 0; applySnapshot(error.body);
      const renewed = await post('/session', {client: session.client}); sequence = renewed.next;
    }
    note(`${error.message} · pending commands retained for retry`);
  } finally { sending = false; }
  if (pending.length) setTimeout(flush, 300);
}
function point(event) {
  const rect = canvas.getBoundingClientRect(), {width, height, cellSize, pointer} = manifest.settings;
  local(pointer.move, [Math.floor((event.clientX - rect.left) / rect.width * width / cellSize),
    Math.floor((event.clientY - rect.top) / rect.height * height / cellSize)]);
}
function installInput() {
  canvas.addEventListener('pointermove', point);
  canvas.addEventListener('pointerdown', event => {
    event.preventDefault(); canvas.focus(); point(event); local(manifest.settings.pointer.confirm);
  });
  document.addEventListener('keydown', event => {
    const command = manifest.settings.keys[event.key]; if (command) { event.preventDefault(); local(command[0], command.slice(1)); }
  });
  for (const button of document.querySelectorAll('[data-handler]')) button.addEventListener('click', () =>
    local(button.dataset.handler, button.dataset.args ? JSON.parse(button.dataset.args) : []));
  document.addEventListener('visibilitychange', () => void post('/presence', {client: session.client, visible: !document.hidden}));
}
let buttons = [], lastPad = 0;
function frame(time) {
  if (manifest && session && !document.hidden) {
    const pad = navigator.getGamepads?.()[0];
    if (pad) {
      for (const [index, command] of Object.entries(manifest.settings.controller ?? {})) {
        const down = pad.buttons[index]?.pressed;
        if (down && (!buttons[index] || (Number(index) >= 12 && time - lastPad > 160))) { local(command[0], command.slice(1)); lastPad = time; }
      }
      buttons = pad.buttons.map(button => button.pressed);
    }
    if (dirty) {
      const presentation = runtime.view(); renderer.draw(presentation.quads, manifest.settings.width, manifest.settings.height);
      status.textContent = presentation.label; dirty = false;
    }
  }
  requestAnimationFrame(frame);
}
async function start() {
  renderer = await createRenderer(canvas, error => note(error.message)); await loadGeneration();
  session = await post('/session', {client: sessionStorage.getItem('snail.client')});
  sessionStorage.setItem('snail.client', session.client); sequence = session.next; applySnapshot(session);
  const events = new EventSource(`/events?client=${encodeURIComponent(session.client)}`);
  events.onmessage = event => {
    const value = JSON.parse(event.data);
    if (value.type === 'snapshot') applySnapshot(value);
    else if (value.type === 'reload') void loadGeneration().catch(error => note(`Reload rejected; previous code stays live: ${error.message}`));
    else if (value.type === 'reload-error' || value.type === 'error') note(`Previous code stays live: ${value.error}`);
  };
  events.onerror = () => note('Reconnecting · local selection and pending commands retained');
  installInput(); requestAnimationFrame(frame);
  // Deliberately exposed diagnostics for executable browser integration checks.
  globalThis.snailApp = {runtime, local, pending, reload: loadGeneration, acceptSnapshot: applySnapshot, renderer,
    get revision() { return revision; }, get generation() { return generation; }, get session() { return session; }};
  note(`CONNECTED · player ${session.client.slice(0, 6)} · WebGPU`);
}
start().catch(error => { note(`Cannot start: ${error.message}`); console.error(error); });
