// The browser host for a Lofi application built with (lofi app). It owns no
// game rules: it forwards input and clock ticks to the module, draws the
// frames the module emits through the `screen` effect, and stores saves.

import {createRenderer} from './renderer.mjs';
import {createHud} from './hud.mjs';
import {createPictures} from './pictures.mjs';
import {loadSave, storeSave} from './storage.mjs';
import {createWasi, instantiate, linkProgram, programExports, relinkProgram, runProgram} from './load.mjs';

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

// ---- Screen effect ----

// The `screen` effect of lib/lofi/app.sld, in three parts: frames for the
// renderer, pictures for the picture store, which the renderer and the HUD
// both read, and the HUD. A test passes its own renderer, picture store and
// HUD, each with just what its part calls.
export function screenImports(renderer, pictures, hud) {
  return {...frameImports(renderer), ...pictureImports(pictures), ...hudImports(hud)};
}

// Collects one frame and hands it to the renderer, which may already hold
// a batch's instances. A batch's style is [opacity, x, z, radius], with a
// negative radius when nothing is hidden, from the solid, translucent or
// revealed style that `render-batch` in lib/lofi/app.sld numbers 0, 1, 2.
function frameImports(renderer) {
  let frame = null, batch = null;
  const styles = [(a, b, c, d) => [1, 0, 0, -1], (a, b, c, d) => [a, 0, 0, -1], (a, b, c, d) => [1, b, c, d]];
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
    surface(...values) {
      batch.items.at(-1).push(...values);
    },
    'frame-end'() {
      renderer.draw(frame);
    },
  };
}

// Pictures and the sources they need go to the picture store, which may
// already hold them.
function pictureImports(pictures) {
  let picture = null, source = null;
  return {
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
  };
}

// Collects the HUD, which the program sends only after updates, and hands
// its panels to the HUD. A widget's strings arrive by field, numbered as
// `render-widget` in lib/lofi/app.sld numbers them; fields 7 and 8 each
// start a span of a text, normal or strong.
function hudImports(hud) {
  let panels = null, target = null, fieldName = null;
  const fields = ['key', 'icon', 'help', 'badge', 'text', 'caption', 'url'];
  return {
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

// The applications running on this page, which the pages that relink, the
// ones `lofi serve` serves and the IDE's preview, relink and save together.
export const running = [];

// An application is the program it runs, which may be relinked, with the
// last lines the program wrote to standard error, and the page's pictures,
// renderer, HUD and canvas, which outlive any one program. `manifest` names
// a program compiled one library at a time, whose files `read` gives: a
// page that `lofi serve` serves names its modules.json in a meta tag, and
// the browser IDE passes one with a `read` that fetches from its toolchain.
// Without one the page is published, and loads one linked module from
// `url`, which a manifest makes the page ignore.
export async function startApplication({url, canvas, overlay, storageKey, manifest, read}) {
  const pictures = createPictures();
  const application = {canvas, storageKey, program: null, exports: null, errors: [], capture: null, pictures,
                       renderer: await createRenderer(canvas, pictures), hud: null, clock: null};
  application.hud = createHud(overlay, (action, argument) => application.exports.app_input(PRESS, action, argument, 0, 0),
                              (action, argument) => application.exports.app_input(HOVER, action, argument, 0, 0), pictures);
  const modules = manifest ?? document.querySelector('meta[name="lofi-modules"]')?.content;
  if (modules) await linkApplication(application, modules, read ?? fetchRead(modules));
  else await instantiateApplication(application, url);
  await restore(application);
  attachInput(application);
  addEventListener('visibilitychange', () => { if (document.hidden) saveQuietly(application); });
  runClock(application);
  running.push(application);
}

function applicationScreen(application) {
  return {'snail.screen': screenImports(application.renderer, application.pictures, application.hud)};
}

async function instantiateApplication(application, url) {
  const wasi = createWasi({print: printer(application)});
  const instance = await instantiate(await WebAssembly.compileStreaming(fetch(url)), {...wasi.getImportObject(), ...applicationScreen(application)});
  wasi.initialize(instance);
  instance.exports.main();
  application.exports = instance.exports;
}

// The application keeps the linked program (load.mjs), so a rebuilt module
// and those after it can be relinked.
async function linkApplication(application, manifest, read) {
  const wasi = createWasi({print: printer(application)});
  application.program = await linkProgram(read, manifest, wasi, applicationScreen(application));
  runProgram(application.program);
  application.exports = programExports(application.program);
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

function save(application) {
  return storeSave(application.storageKey, saveBytes(application.exports));
}

// Stores every application's save, resolving once all are stored.
export function saveAll() {
  return Promise.all(running.map(save));
}

function saveQuietly(application) {
  save(application).catch(error => console.warn('save failed:', error.message));
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

// After a build changed the module of library `from`, each application's
// program is relinked from it (load.mjs), one application at a time.
export async function relinkAll(from, fresh) {
  for (const application of running) await relinkApplication(application, from, fresh);
}

// The state passes to the new program (`takeState`); the renderer forgets
// the batches the old one drew, and the picture store its pictures and
// sources. If the new program cannot take the state, the old one keeps
// running and the error carries what was printed; `fresh` starts the new
// program over instead. A clock that stopped when the old program trapped
// starts again.
async function relinkApplication(application, from, fresh) {
  application.capture = [];
  try {
    const program = await relinkProgram(application.program, from);
    takeState(programExports(program), application.exports, application.canvas, fresh);
    application.renderer.forget();
    application.pictures.forget();
    Object.assign(application, {program, exports: programExports(program)});
  } catch (error) {
    throw new Error(application.capture.join('\n') || error.message);
  } finally {
    application.capture = null;
  }
  if (!application.clock) runClock(application);
}

// The state passes as it is while its type is unchanged, which adopting
// tests structurally; a state of another type passes through the save,
// which traps when its schema changed too. Returns how the state passed.
export function takeState(next, previous, canvas, fresh) {
  if (fresh) {
    startFresh(next, canvas);
    return 'fresh';
  }
  if (next.app_adopt(previous.app_state()) === 0) {
    next.app_input(RESIZE, canvas.clientWidth, canvas.clientHeight, 0, 0);
    return 'adopted';
  }
  loadBytes(next, saveBytes(previous), canvas);
  return 'saved';
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
  // A hidden canvas, as in a closed dock, keeps its last size.
  new ResizeObserver(() => { if (canvas.clientWidth && canvas.clientHeight) send(RESIZE, canvas.clientWidth, canvas.clientHeight); }).observe(canvas);
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
