// The browser host for a Lofi application built with (lofi app). It owns no
// game rules: it forwards input and clock ticks to the module, draws the
// frames the module emits through the `screen` effect, and stores saves.

import {createRenderer} from './renderer.mjs';
import {createHud} from './hud.mjs';
import {createPictures} from './pictures.mjs';
import {loadSave, storeSave} from './storage.mjs';
import {instantiateRuntime, linkModules, loadManifest, runModules} from './load.mjs';

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
// writes goes to `print` with its file descriptor. It waits, through
// poll_oneoff, only when standard output refuses a write, which never
// happens here, so waiting returns at once.
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
    poll_oneoff() { return 0; },
  };
}

// ---- Screen effect ----

// Collects one frame from the screen operations and hands it to the
// renderer; collects the HUD, sent only after updates, and hands it to the
// HUD. A batch's style is [opacity, x, z, radius], with a negative radius
// when nothing is hidden. Pictures and the sources they need go to the
// picture store, which both the renderer and the HUD read.
function screenImports(renderer, hud, pictures) {
  let frame = null, batch = null, panels = null, target = null, fieldName = null, picture = null, source = null;
  const styles = [(a, b, c, d) => [1, 0, 0, -1], (a, b, c, d) => [a, 0, 0, -1], (a, b, c, d) => [1, b, c, d]];
  const fields = ['key', 'icon', 'help', 'badge', 'text', 'caption', 'url'];
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
    'picture-begin'(key, version, width, height) {
      if (pictures.has(key, version)) return 1;
      picture = pictures.define(key, version, width, height);
      return 0;
    },
    layer(key, fx, fy, fw, fh, x, y) {
      picture.layers.push({source: key, fx, fy, fw, fh, x, y, swaps: new Map()});
      return pictures.hasSource(key) ? 1 : 0;
    },
    swap(from, to) {
      picture.layers.at(-1).swaps.set(from, to);
    },
    'source-begin'(key, length) {
      source = {key, bytes: new Uint8Array(length), at: 0};
      if (length === 0) pictures.addSource(key, source.bytes);
    },
    // Four bytes per word, little-endian; the last word may be padded.
    'source-word'(word) {
      for (let shift = 0; shift < 32 && source.at < source.bytes.length; shift += 8) source.bytes[source.at++] = (word >>> shift) & 255;
      if (source.at === source.bytes.length) pictures.addSource(source.key, source.bytes);
    },
    'picture-end'() {
      pictures.finish(picture);
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
    surface(...values) {
      batch.items.at(-1).push(...values);
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
      target = {kind, tone, action, argument, control, value, key: '', icon: '', help: '', badge: '', text: '', caption: '', url: '', spans: []};
      panels.at(-1).widgets.push(target);
    },
    'widget-image'(key, x, y, width, height, scale) {
      target.image = {key, x, y, width, height, scale};
    },
    // Fields 7 and 8 each start a span of a text, normal or strong.
    field(which) {
      if (which >= 7) target.spans.push({strong: which === 8, words: ''});
      fieldName = fields[which] ?? null;
    },
    'text-character'(code) {
      if (fieldName) target[fieldName] += String.fromCodePoint(code);
      else target.spans.at(-1).words += String.fromCodePoint(code);
    },
    'hud-end'() {
      hud.update(panels);
    },
  };
}

// ---- Application ----

// The applications running on this page. A development server relinks
// their programs (src/app/reload.mjs).
export const running = [];

// An application is the program it runs, which a development server may
// relink, with the last lines the program wrote to standard error, and the
// page's pictures, renderer, HUD and canvas, which outlive any one program. A page
// that `lofi serve` serves names its program's modules.json in a meta tag,
// and the browser IDE passes one with a `read` that fetches its files from
// the toolchain; a published page loads one linked module from `url`.
export async function startApplication({url, canvas, overlay, storageKey, manifest, read}) {
  const pictures = createPictures();
  const application = {url, canvas, storageKey, exports: null, errors: [], capture: null, pictures,
                       renderer: await createRenderer(canvas, pictures), hud: null, clock: null, program: null};
  application.hud = createHud(overlay, (action, argument) => application.exports.app_input(PRESS, action, argument, 0, 0),
                              (action, argument) => application.exports.app_input(HOVER, action, argument, 0, 0), pictures);
  const modules = manifest ?? document.querySelector('meta[name="lofi-modules"]')?.content;
  application.exports = modules ? await linkProgram(application, modules, read ?? fetchRead(modules)) : await instantiate(application, url);
  await restore(application);
  attachInput(application);
  addEventListener('visibilitychange', () => { if (document.hidden) saveQuietly(application); });
  runClock(application);
  running.push(application);
  return application.exports;
}

async function instantiate(application, url) {
  let exports;
  const imports = {
    wasi_snapshot_preview1: wasiImports(() => exports.memory, printer(application)),
    'snail.screen': screenImports(application.renderer, application.hud, application.pictures),
  };
  ({instance: {exports}} = await WebAssembly.instantiateStreaming(fetch(url), imports));
  exports._initialize();
  exports.main();
  return exports;
}

// A program compiled one library at a time: the runtime, then each module
// in program order (load.mjs). The application keeps the instances, so a
// rebuilt module and those after it can be relinked.
async function linkProgram(application, manifest, read) {
  const loaded = await loadManifest(read, manifest);
  let runtime = null;
  runtime = await instantiateRuntime(loaded.runtime, {wasi_snapshot_preview1: wasiImports(() => runtime.exports.memory, printer(application))});
  runtime.exports._initialize();
  const host = {'snail.screen': screenImports(application.renderer, application.hud, application.pictures)};
  const linked = await linkModules(runtime, loaded.modules, host);
  runModules(linked, loaded.modules.map(entry => entry.name));
  application.program = {manifest, read, runtime, host, linked};
  return linked.get(loaded.modules.at(-1).name).exports;
}

// A file's bytes, by its path relative to the manifest's, uncached.
function fetchRead(manifest) {
  return async file => new Uint8Array(await (await fetch(new URL(file, new URL(manifest, location.href)), {cache: 'no-store'})).arrayBuffer());
}

// Lines the program writes go to the console. The last twenty it writes to
// standard error are kept in `errors`, since they explain a trap: a panic
// prints its message before trapping. While a relink runs, they are also
// captured for its error.
function printer(application) {
  return (fd, text) => {
    if (fd !== 2) { console.log(text); return; }
    console.error(text);
    application.errors.push(text);
    application.errors.splice(0, application.errors.length - 20);
    application.capture?.push(text);
  };
}

// ---- Saves ----

function saveBytes(exports) {
  const length = exports.app_save();
  return Uint8Array.from({length}, (_, index) => exports.app_save_byte(index));
}

// Restores a save into a program, then reports the screen's size, which
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

// Stores the running program's save, resolving once it is stored.
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

// ---- Relinking ----

// After a build changed the module of library `from`, that module and every
// module after it, which may import from it, are linked again from the new
// modules.json, in program order, and initialized: their globals start
// over. The state passes to the new program (`takeState`); the renderer
// forgets the batches the old one drew, and the picture store its pictures
// and sources. If the new program cannot take the state, the old one keeps
// running and the error carries what was printed; `fresh` starts the new
// program over instead. A clock that stopped when the old program trapped
// starts again.
export async function relinkModules(application, from, {fresh = false} = {}) {
  application.capture = [];
  try {
    const next = await linkFrom(application.program, from);
    takeState(next.exports, application, fresh);
    application.renderer.forget();
    application.pictures.forget();
    Object.assign(application, {exports: next.exports});
    application.program.linked = next.linked;
  } catch (error) {
    throw new Error(application.capture.join('\n') || error.message);
  } finally {
    application.capture = null;
  }
  if (!application.clock) runClock(application);
}

// Keeps the instances of the modules before `from`, which cannot import
// from it, and links the rest anew.
async function linkFrom(program, from) {
  const {modules: entries} = JSON.parse(new TextDecoder().decode(await program.read(program.manifest)));
  const start = Math.max(0, entries.findIndex(entry => entry.name === from));
  const kept = new Map(entries.slice(0, start).map(entry => [entry.name, program.linked.get(entry.name)]));
  const modules = await Promise.all(entries.slice(start).map(async entry => ({...entry, module: await WebAssembly.compile(await program.read(entry.file))})));
  const linked = await linkModules(program.runtime, modules, program.host, kept);
  runModules(linked, modules.map(entry => entry.name));
  return {linked, exports: linked.get(entries.at(-1).name).exports};
}

// The state passes as it is while its types are unchanged; a state of
// another type, which adopting reports, passes through the save instead.
function takeState(next, application, fresh) {
  const {canvas} = application;
  if (fresh) startFresh(next, canvas);
  else if (next.app_adopt(application.exports.app_state()) === 0) next.app_input(RESIZE, canvas.clientWidth, canvas.clientHeight, 0, 0);
  else loadBytes(next, saveBytes(application.exports), canvas);
}

// Wheel deltas arrive in pixels, lines or pages; the application gets pixels.
function wheelPixels(event) {
  return Math.round(event.deltaY * [1, 16, innerHeight][event.deltaMode]);
}

function attachInput(application) {
  const {canvas} = application;
  const send = (kind, a = 0, b = 0, c = 0, d = 0) => application.exports.app_input(kind, a | 0, b | 0, c | 0, d | 0);
  // A key held with Ctrl, Alt or Meta belongs to the browser, so shortcuts
  // such as reloading keep working; Shift travels with the key. Keys typed
  // into a field, such as the IDE's editor, stay there.
  addEventListener('keydown', event => {
    if (event.ctrlKey || event.altKey || event.metaKey) return;
    if (event.target.closest?.('input, textarea, select') || (event.target instanceof HTMLButtonElement && (event.key === 'Enter' || event.key === ' '))) return;
    const code = keyCode(event);
    if (code) { send(KEY_DOWN, code, event.shiftKey ? 1 : 0); event.preventDefault(); }
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
