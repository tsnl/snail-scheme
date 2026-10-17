// Browser platform bindings only. Scheme owns both the immutable client model
// and all game transitions; the authority owns accepted world revisions.
import {ReducerRuntime} from '../application/runtime.mjs';
import {createRenderer} from '../webgpu/quads.mjs';
import {BrowserInput, parseInputSettings} from './input.mjs';

const canvas = document.querySelector('canvas'), status = document.querySelector('[data-status]');
const connection = document.querySelector('[data-connection]');
const runtime = new ReducerRuntime(), pending = [];
let manifest, renderer, session, input, inputSettings, revision = -1, epoch, sequence = 1, sending = false, generation = '', dirty = true, reloadTicket = 0;
let updates = Promise.resolve(), localWork = 0;
const post = async (path, value) => {
  const response = await fetch(path, {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify(value)});
  const body = await response.json(); if (!response.ok) throw Object.assign(new Error(body.error), {body}); return body;
};
function note(text) { connection.textContent = text; }
function update(operation) {
  const result = updates.then(operation);
  updates = result.catch(() => {});
  return result;
}
async function loadGeneration() {
  const ticket = ++reloadTicket;
  const next = await (await fetch('/manifest.json', {cache: 'no-store'})).json();
  if (next.generation === generation) return;
  const nextInput = parseInputSettings(next.settings);
  const [bytes, source] = await Promise.all([fetch(`/${next.module}`).then(r => r.arrayBuffer()), fetch(`/${next.shader}`).then(r => r.text())]);
  const candidate = runtime.prepare(new Uint8Array(bytes), next);
  let pipeline;
  try {
    pipeline = await renderer.prepare(source);
    await update(async () => {
      if (ticket !== reloadTicket) { runtime.discard(candidate); return; }
      await runtime.replace(candidate);
      renderer.replace(pipeline); manifest = next; generation = next.generation; inputSettings = nextInput;
      await runtime.initialize(1); await runtime.initialize(2); dirty = true;
      note(`LIVE · ${pending.length ? `${pending.length} pending` : 'state preserved'} · ${generation.slice(0, 7)}`);
    });
  }
  catch (error) { runtime.discard(candidate); throw error; }
}
function applySnapshot(snapshot) {
  snapshot = structuredClone(snapshot);
  return update(() => restoreSnapshot(snapshot));
}
async function restoreSnapshot(snapshot) {
  if (snapshot.revision < revision) return;
  await runtime.restore(1, snapshot.state); revision = snapshot.revision; epoch = snapshot.epoch; dirty = true;
}
async function renewSession(snapshot) {
  pending.length = 0; await restoreSnapshot(snapshot);
  const renewed = await post('/session', {client: session.client});
  await restoreSnapshot(renewed); sequence = renewed.next;
}
function local(binding, args = []) {
  const command = runtime.command('client', binding, args.slice());
  localWork++;
  return update(() => localTransition(command)).catch(reportTransitionFailure).finally(() => localWork--);
}
async function localTransition(command) {
  const result = await runtime.dispatch(2, command);
  for (const effect of result.effects) {
    if (effect.kind === 'send' && effect.owner === 1) {
      const command = runtime.effectCommand(effect);
      pending.push({client: session.client, sequence: sequence++, epoch, command});
      // Speculation uses exactly the same Scheme reducer; accepted server state
      // replaces it on reply. No prediction is persisted as authoritative data.
      try { await runtime.dispatch(1, command); } catch (error) { reportTransitionFailure(error); }
    } else if (effect.kind === 'notice') note(effect.text);
  }
  dirty = true; void flush().catch(error => note(error.message));
}
function reconcileGeneration() {
  if (generation !== runtime.manifest.generation) {
    manifest = runtime.manifest; generation = manifest.generation; renderer.rollback();
    inputSettings = parseInputSettings(manifest.settings);
    dirty = true;
  }
}
function reportTransitionFailure(error) {
  reconcileGeneration();
  dirty = true; note(`Transition rejected; committed state retained: ${error.message}`);
}
async function flush() {
  if (sending || !pending.length) return; sending = true;
  try {
    const result = await post('/command', pending[0]); pending.shift(); await applySnapshot(result);
    note(`LIVE · revision ${revision} · ${pending.length} pending`);
  } catch (error) {
    if (error.body) {
      // Admission stays behind renewal, so no new local envelope can reuse an
      // old sequence or be discarded by a later queue reset.
      await update(() => renewSession(error.body));
    }
    note(`${error.message} · ${error.body ? 'session renewed' : 'pending commands retained for retry'}`);
  } finally { sending = false; }
  if (pending.length) setTimeout(() => void flush().catch(error => note(error.message)), 300);
}
function frame(time) {
  if (manifest) reconcileGeneration(); // Query recovery completes at a later runtime boundary.
  if (!localWork) input?.frame(time);
  else if (input) input.time = time; // Slow work never builds a catch-up queue of held movement.
  if (manifest && session && !document.hidden) {
    if (dirty) {
      try {
        const presentation = runtime.view(); renderer.draw(presentation.quads, manifest.settings.width, manifest.settings.height);
        status.textContent = presentation.label; dirty = false;
      } catch (error) { reportTransitionFailure(error); }
    }
  }
  requestAnimationFrame(frame);
}
async function start() {
  renderer = await createRenderer(canvas, error => note(error.message)); await loadGeneration();
  session = await post('/session', {client: sessionStorage.getItem('snail.client')});
  sessionStorage.setItem('snail.client', session.client); sequence = session.next; await applySnapshot(session);
  const events = new EventSource(`/events?client=${encodeURIComponent(session.client)}`);
  events.onmessage = event => {
    const value = JSON.parse(event.data);
    if (value.type === 'snapshot') void applySnapshot(value).catch(reportTransitionFailure);
    else if (value.type === 'reload') void loadGeneration().catch(error => note(`Reload rejected; previous code stays live: ${error.message}`));
    else if (value.type === 'reload-error' || value.type === 'error') note(`Previous code stays live: ${value.error}`);
  };
  events.onerror = () => note('Reconnecting · local selection and pending commands retained');
  input = new BrowserInput(canvas, () => inputSettings, local);
  document.addEventListener('visibilitychange', () => void post('/presence', {client: session.client, visible: !document.hidden}));
  requestAnimationFrame(frame);
  // Deliberately exposed diagnostics for executable browser integration checks.
  globalThis.snailApp = {runtime, local, pending, reload: loadGeneration, acceptSnapshot: applySnapshot, renderer,
    get revision() { return revision; }, get generation() { return generation; }, get session() { return session; }};
  note(`CONNECTED · player ${session.client.slice(0, 6)} · WebGPU`);
}
start().catch(error => { note(`Cannot start: ${error.message}`); console.error(error); });
