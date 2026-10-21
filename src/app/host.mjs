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

// The linked Rust runtime needs only standard output and exit. Each line it
// writes goes to `print` with its file descriptor.
function wasiImports(memory, print) {
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
      for (const text of lines) print(fd, text);
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

// The applications running on this page. A development server replaces
// their modules (src/app/reload.mjs).
export const running = [];

// An application is the module it runs, which `replaceModule` may swap,
// with the last lines that module wrote to standard error, and the page's
// renderer, HUD and canvas, which outlive any one module.
export async function startApplication({url, canvas, overlay, storageKey}) {
  const application = {url, canvas, storageKey, exports: null, errors: [], renderer: await createRenderer(canvas), hud: null, clock: null};
  application.hud = createHud(overlay, (action, argument) => application.exports.app_input(PRESS, action, argument, 0, 0),
                              (action, argument) => application.exports.app_input(HOVER, action, argument, 0, 0));
  application.exports = await instantiate(application, url, application.errors);
  await restore(application);
  attachInput(application);
  addEventListener('visibilitychange', () => { if (document.hidden) saveQuietly(application); });
  runClock(application);
  running.push(application);
  return application.exports;
}

// Every instance has its own WASI imports, which read its own memory, so a
// new module can start while the old one still runs.
async function instantiate(application, url, errors) {
  let exports;
  const imports = {
    wasi_snapshot_preview1: wasiImports(() => exports.memory, printer(errors)),
    'snail.screen': screenImports(application.renderer, application.hud),
  };
  ({instance: {exports}} = await WebAssembly.instantiateStreaming(fetch(url), imports));
  exports._initialize();
  exports.main();
  return exports;
}

// Lines a module writes go to the console. The last twenty it writes to
// standard error are also kept in `errors`, since they explain a trap: a
// panic prints its message before trapping.
function printer(errors) {
  return (fd, text) => {
    if (fd !== 2) { console.log(text); return; }
    console.error(text);
    errors.push(text);
    errors.splice(0, errors.length - 20);
  };
}

// ---- Saves ----

function saveBytes(exports) {
  const length = exports.app_save();
  return Uint8Array.from({length}, (_, index) => exports.app_save_byte(index));
}

// Restores a save into a module, then reports the screen's size, which
// saves leave out. A save written for another schema traps.
function loadBytes(exports, bytes, canvas) {
  exports.app_load_begin(bytes.length);
  bytes.forEach((byte, index) => exports.app_load_byte(index, byte));
  exports.app_load_end();
  exports.app_input(RESIZE, canvas.clientWidth, canvas.clientHeight, 0, 0);
}

function startFresh(exports, canvas) {
  exports.app_init((Math.random() * 65536) | 0, canvas.clientWidth, canvas.clientHeight);
}

// Stores the running module's save, resolving once it is stored.
export function saveApplication(application) {
  return storeSave(application.storageKey, saveBytes(application.exports));
}

function saveQuietly(application) {
  saveApplication(application).catch(error => console.warn('save failed:', error.message));
}

// A save written for another schema traps while loading; start fresh then.
async function restore(application) {
  const bytes = await loadSave(application.storageKey);
  if (bytes) {
    try {
      loadBytes(application.exports, bytes, application.canvas);
      return;
    } catch (error) {
      console.warn('discarding an incompatible save:', error.message);
    }
  }
  startFresh(application.exports, application.canvas);
}

// ---- Replacing the module ----

// Swaps in a rebuilt module while the page keeps running: the old module's
// save restores into the new one, so the state survives while every
// function changes. The renderer's batches were drawn by the old module, so
// it forgets them. If the new module cannot take over the save, because
// its Save type changed or restoring it panics, the old module keeps
// running and the error carries what the new one printed; `fresh` starts
// the new module over instead. A clock that stopped when the old module
// trapped starts again.
export async function replaceModule(application, url, {fresh = false} = {}) {
  const errors = [];
  try {
    const next = await instantiate(application, url, errors);
    if (fresh) startFresh(next, application.canvas);
    else loadBytes(next, saveBytes(application.exports), application.canvas);
    application.renderer.forget();
    Object.assign(application, {exports: next, errors});
  } catch (error) {
    throw new Error(errors.join('\n') || error.message);
  }
  if (!application.clock) runClock(application);
}

// Wheel deltas arrive in pixels, lines or pages; the application gets pixels.
function wheelPixels(event) {
  return Math.round(event.deltaY * [1, 16, innerHeight][event.deltaMode]);
}

function attachInput(application) {
  const {canvas} = application;
  const send = (kind, a = 0, b = 0, c = 0, d = 0) => application.exports.app_input(kind, a | 0, b | 0, c | 0, d | 0);
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
// for them. The state is saved every five seconds. A module that traps
// stops the clock, keeping the state from before the update that trapped,
// until a replacement module starts it again.
function runClock(application) {
  let last = performance.now(), lastSave = last;
  const frame = now => {
    advance(application, Math.round(Math.min(250, Math.max(0, now - last))));
    last = now;
    if (now - lastSave > 5000) { lastSave = now; saveQuietly(application); }
    application.clock = requestAnimationFrame(frame);
  };
  application.clock = requestAnimationFrame(now => { last = now; frame(now); });
}

// One display frame: time passes, then the module draws.
function advance(application, milliseconds) {
  try {
    application.exports.app_input(ELAPSED, milliseconds, 0, 0, 0);
    application.exports.app_frame();
  } catch (error) {
    application.clock = null;
    throw error;
  }
}
