// The browser host for a Lofi application built with (lofi app). It owns no
// game rules: it forwards input and clock ticks to the module, draws the
// frames the module emits through the `screen` effect, and stores saves.

import {createRenderer} from './renderer.mjs';
import {createHud} from './hud.mjs';
import {loadSave, storeSave} from './storage.mjs';

// ---- Input encoding ----

// Input kinds and named keys match `decode-input` and the key constants in
// lib/lofi/app.sld.
const KEY_DOWN = 1, KEY_UP = 2, POINTER_DOWN = 3, POINTER_MOVE = 4, POINTER_UP = 5, POINTER_CANCEL = 6;
const WHEEL = 7, RESIZE = 8, PRESS = 9, HOVER = 10, ELAPSED = 11;
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

// Collects one frame from the screen operations and hands it to the
// renderer; collects the HUD, sent only after updates, and hands it to the
// HUD. A batch's style is [opacity, x, z, radius], with a negative radius
// when nothing is hidden.
function screenImports(renderer, hud) {
  let frame = null, batch = null, panels = null, target = null, fieldName = null;
  const styles = [(a, b, c, d) => [1, 0, 0, -1], (a, b, c, d) => [a, 0, 0, -1], (a, b, c, d) => [1, b, c, d]];
  const fields = ['key', 'icon', 'help', 'badge', 'text', 'caption'];
  return {
    'frame-begin'(background, motion) {
      frame = {background, motion, batches: []};
    },
    camera(ex, ey, ez, tx, ty, tz, kind, value) {
      frame.camera = {eye: [ex, ey, ez], target: [tx, ty, tz], kind, value};
    },
    light(dx, dy, dz, sun, ambient) {
      frame.light = {direction: [dx, dy, dz], sun, ambient};
    },
    'batch-begin'(key, version, style, a, b, c, d) {
      const cached = renderer.hasBatch(key, version);
      batch = {key, version, style: styles[style](a, b, c, d), items: cached ? null : []};
      frame.batches.push(batch);
      return cached ? 1 : 0;
    },
    instance(...values) {
      batch.items.push(values);
    },
    'frame-end'() {
      renderer.draw(frame);
    },
    'hud-begin'() {
      panels = [];
    },
    'panel-begin'(place, corner, column, dismiss) {
      target = {place, corner, column, dismiss, key: '', widgets: []};
      panels.push(target);
    },
    'widget-begin'(kind, tone, action, argument, control, value) {
      target = {kind, tone, action, argument, control, value, key: '', icon: '', help: '', badge: '', text: '', caption: ''};
      panels.at(-1).widgets.push(target);
    },
    field(which) {
      fieldName = fields[which];
    },
    'text-character'(code) {
      target[fieldName] += String.fromCodePoint(code);
    },
    'hud-end'() {
      hud.update(panels);
    },
  };
}

// ---- Application ----

export async function startApplication({url, canvas, overlay, storageKey}) {
  const renderer = await createRenderer(canvas);
  let exports;
  const hud = createHud(overlay, (action, argument) => exports.app_input(PRESS, action, argument, 0, 0),
                        (action, argument) => exports.app_input(HOVER, action, argument, 0, 0));
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
  runClock(exports, storageKey);
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
      exports.app_input(RESIZE, canvas.clientWidth, canvas.clientHeight, 0, 0);
      return;
    } catch (error) {
      console.warn('discarding an incompatible save:', error.message);
    }
  }
  exports.app_init((Math.random() * 65536) | 0, canvas.clientWidth, canvas.clientHeight);
}

// Wheel deltas arrive in pixels, lines or pages; the application gets pixels.
function wheelPixels(event) {
  return Math.round(event.deltaY * [1, 16, innerHeight][event.deltaMode]);
}

function attachInput(exports, canvas) {
  const send = (kind, a = 0, b = 0, c = 0, d = 0) => exports.app_input(kind, a | 0, b | 0, c | 0, d | 0);
  addEventListener('keydown', event => {
    if (event.target instanceof HTMLInputElement || (event.target instanceof HTMLButtonElement && (event.key === 'Enter' || event.key === ' '))) return;
    const code = keyCode(event);
    if (code) { send(KEY_DOWN, code); event.preventDefault(); }
  });
  addEventListener('keyup', event => { const code = keyCode(event); if (code) send(KEY_UP, code); });
  canvas.addEventListener('pointerdown', event => {
    canvas.setPointerCapture?.(event.pointerId);
    send(POINTER_DOWN, event.pointerId, event.offsetX, event.offsetY, event.button);
  });
  canvas.addEventListener('pointermove', event => send(POINTER_MOVE, event.pointerId, event.offsetX, event.offsetY));
  canvas.addEventListener('pointerup', event => send(POINTER_UP, event.pointerId, event.offsetX, event.offsetY));
  canvas.addEventListener('pointercancel', event => send(POINTER_CANCEL, event.pointerId));
  canvas.addEventListener('wheel', event => { send(WHEEL, wheelPixels(event)); event.preventDefault(); }, {passive: false});
  canvas.addEventListener('contextmenu', event => event.preventDefault());
  new ResizeObserver(() => send(RESIZE, canvas.clientWidth, canvas.clientHeight)).observe(canvas);
}

// Each display frame first reports the time since the last, up to a quarter
// of a second, then draws. Hidden pages draw no frames, so no time passes
// for them. The state is saved every five seconds and when hidden.
function runClock(exports, storageKey) {
  let last = performance.now(), lastSave = last;
  const save = () => {
    const length = exports.app_save();
    const bytes = new Uint8Array(length);
    for (let i = 0; i < length; i++) bytes[i] = exports.app_save_byte(i);
    storeSave(storageKey, bytes).catch(error => console.warn('save failed:', error.message));
  };
  addEventListener('visibilitychange', () => { if (document.hidden) save(); });
  const frame = now => {
    exports.app_input(ELAPSED, Math.round(Math.min(250, Math.max(0, now - last))), 0, 0, 0);
    last = now;
    exports.app_frame();
    if (now - lastSave > 5000) { lastSave = now; save(); }
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(now => { last = now; frame(now); });
}
