// The browser host for a Lofi application built with (lofi app). It owns no
// game rules: it forwards input and clock ticks to the module, draws the
// frames the module emits through the `screen` effect, and stores saves.

import {createRenderer} from './renderer.mjs';
import {createHud} from './hud.mjs';
import {loadSave, storeSave} from './storage.mjs';

// ---- Input encoding ----

// Input kinds and named keys match `decode-input` and the key constants in
// lib/lofi/app.sld.
const KEY_DOWN = 1, KEY_UP = 2, POINTER_MOVE = 3, POINTER_DOWN = 4, POINTER_UP = 5;
const WHEEL = 6, RESIZE = 7, PRESS = 8, TICK = 9;
const namedKeys = {ArrowLeft: 1, ArrowRight: 2, ArrowUp: 3, ArrowDown: 4, Escape: 27, Enter: 13, ' ': 32};

function keyCode(event) {
  if (event.key in namedKeys) return namedKeys[event.key];
  return [...event.key].length === 1 ? event.key.toLowerCase().codePointAt(0) : 0;
}

// ---- WASI ----

// The linked Rust runtime needs only standard output and exit.
function wasiImports(memory) {
  const decoder = new TextDecoder();
  let line = '';
  return {
    fd_write(fd, iovs, count, written) {
      const view = new DataView(memory().buffer);
      let total = 0;
      for (let i = 0; i < count; i++) {
        const pointer = view.getUint32(iovs + 8 * i, true), length = view.getUint32(iovs + 8 * i + 4, true);
        line += decoder.decode(new Uint8Array(memory().buffer, pointer, length));
        total += length;
      }
      const lines = line.split('\n');
      line = lines.pop();
      for (const text of lines) (fd === 2 ? console.error : console.log)(text);
      view.setUint32(written, total, true);
      return 0;
    },
    proc_exit(code) { throw new Error(`application exited with status ${code}`); },
    environ_get() { return 0; },
    environ_sizes_get(count, size) {
      const view = new DataView(memory().buffer);
      view.setUint32(count, 0, true); view.setUint32(size, 0, true);
      return 0;
    },
    fd_close() { return 0; },
    fd_prestat_get() { return 8; },
    fd_prestat_dir_name() { return 8; },
  };
}

// ---- Screen effect ----

// Collects one frame from the screen operations, then hands it to the
// renderer and the HUD.
function screenImports(renderer, hud) {
  let frame = null, batch = null, panel = null, widget = null;
  return {
    'frame-begin'(ex, ey, ez, tx, ty, tz, background) {
      frame = {eye: [ex, ey, ez], target: [tx, ty, tz], background, batches: [], panels: []};
    },
    'batch-begin'(key, version) {
      const cached = renderer.hasBatch(key, version);
      batch = cached ? null : {key, version, items: []};
      frame.batches.push(cached ? {key, version} : batch);
      return cached ? 1 : 0;
    },
    instance(mesh, x, y, z, sx, sy, sz, yaw, color) {
      batch.items.push(mesh, x, y, z, sx, sy, sz, yaw, color);
    },
    'panel-begin'(anchor) {
      panel = {anchor, widgets: []};
      frame.panels.push(panel);
    },
    'widget-begin'(kind, action, value) {
      widget = {kind, action, value, text: ''};
      panel.widgets.push(widget);
    },
    'text-character'(code) {
      widget.text += String.fromCodePoint(code);
    },
    'frame-end'() {
      renderer.draw(frame);
      hud.update(frame.panels);
    },
  };
}

// ---- Application ----

export async function startApplication({url, canvas, overlay, storageKey, tickMilliseconds = 100}) {
  const renderer = await createRenderer(canvas);
  let exports;
  const hud = createHud(overlay, action => exports.app_input(PRESS, action, 0, 0));
  const imports = {
    wasi_snapshot_preview1: wasiImports(() => exports.memory),
    'snail.screen': screenImports(renderer, hud),
  };
  const {instance} = await WebAssembly.instantiateStreaming(fetch(url), imports);
  exports = instance.exports;
  exports._initialize();
  exports.main();
  await restore(exports, storageKey, canvas);
  attachInput(exports, canvas);
  runClock(exports, storageKey, tickMilliseconds);
  return exports;
}

// A save written for another schema traps while loading; start fresh then.
async function restore(exports, storageKey, canvas) {
  const bytes = await loadSave(storageKey);
  if (bytes) {
    try {
      exports.app_load_begin(bytes.length);
      bytes.forEach((byte, index) => exports.app_load_byte(index, byte));
      exports.app_load_end();
      exports.app_input(RESIZE, canvas.clientWidth, canvas.clientHeight, 0);
      return;
    } catch (error) {
      console.warn('discarding an incompatible save:', error.message);
    }
  }
  exports.app_init((Math.random() * 65536) | 0, canvas.clientWidth, canvas.clientHeight);
}

function attachInput(exports, canvas) {
  const send = (kind, a = 0, b = 0, c = 0) => exports.app_input(kind, a | 0, b | 0, c | 0);
  addEventListener('keydown', event => {
    if (event.target instanceof HTMLInputElement) return;
    const code = keyCode(event);
    if (code) { send(KEY_DOWN, code); event.preventDefault(); }
  });
  addEventListener('keyup', event => { const code = keyCode(event); if (code) send(KEY_UP, code); });
  canvas.addEventListener('pointermove', event => send(POINTER_MOVE, event.offsetX, event.offsetY));
  canvas.addEventListener('pointerdown', event => send(POINTER_DOWN, event.offsetX, event.offsetY, event.button));
  canvas.addEventListener('pointerup', event => send(POINTER_UP, event.offsetX, event.offsetY, event.button));
  canvas.addEventListener('wheel', event => { send(WHEEL, Math.sign(event.deltaY)); event.preventDefault(); }, {passive: false});
  canvas.addEventListener('contextmenu', event => event.preventDefault());
  new ResizeObserver(() => send(RESIZE, canvas.clientWidth, canvas.clientHeight)).observe(canvas);
}

// Ticks run at a fixed rate while the page is visible; frames interpolate
// between ticks. The state is saved every few seconds and when hidden.
function runClock(exports, storageKey, tickMilliseconds) {
  let lastTick = performance.now(), ticks = 0;
  const save = () => {
    const length = exports.app_save();
    const bytes = new Uint8Array(length);
    for (let i = 0; i < length; i++) bytes[i] = exports.app_save_byte(i);
    storeSave(storageKey, bytes).catch(error => console.warn('save failed:', error.message));
  };
  setInterval(() => {
    if (document.hidden) return;
    exports.app_input(TICK, 0, 0, 0);
    lastTick = performance.now();
    if (++ticks % 50 === 0) save();
  }, tickMilliseconds);
  addEventListener('visibilitychange', () => { if (document.hidden) save(); });
  const frame = now => {
    exports.app_frame(Math.min(1, (now - lastTick) / tickMilliseconds));
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
}
