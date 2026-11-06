// The browser host for a Snail-Core application built with (snail shell app). It owns no
// game rules: DOM listeners queue events; the loop runs as a Snail-Core task,
// presents through the `screen` effect, and waits on storage by ticket.

import {createRenderer} from './renderer.mjs';
import {createHud} from './hud.mjs';
import {createPictures} from './pictures.mjs';
import {loadSave, storeSave} from './storage.mjs';
import {createRuntime} from './runtime.mjs';
import {startPage, reportApplicationError} from './application.mjs';

// ---- Input encoding ----

// Input kinds and named keys match `decode-input` and the key constants in
// src/snail/shell/app.sld.
const KEY_DOWN = 1, KEY_UP = 2, POINTER_DOWN = 3, POINTER_MOVE = 4, POINTER_UP = 5, POINTER_CANCEL = 6;
const WHEEL = 7, RESIZE = 8, PRESS = 9, HOVER = 10;
const namedKeys = {ArrowLeft: 1, ArrowRight: 2, ArrowUp: 3, ArrowDown: 4, Escape: 27, Enter: 13, ' ': 32};

function keyCode(event) {
  if (event.key in namedKeys) return namedKeys[event.key];
  return [...event.key].length === 1 ? event.key.toLowerCase().codePointAt(0) : 0;
}

// ---- Screen effect ----

// The `screen` effect of src/snail/shell/app.sld, in three parts: frames for the
// renderer, pictures for the picture store, which the renderer and the HUD
// both read, and the HUD. A test passes its own renderer, picture store and
// HUD, each with just what its part calls.
export function screenImports(renderer, pictures, hud) {
  return {...frameImports(renderer), ...pictureImports(pictures), ...hudImports(hud)};
}

// Collects one frame and hands it to the renderer, which may already hold
// a batch's instances. A batch's style is [opacity, x, z, radius], with a
// negative radius when nothing is hidden, from the solid, translucent or
// revealed style that `render-batch` in src/snail/shell/app.sld numbers 0, 1, 2.
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
// `render-widget` in src/snail/shell/app.sld numbers them; fields 7 and 8 each
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

export async function startApplication({url, canvas, overlay, storageKey}) {
  const pictures = createPictures(), renderer = await createRenderer(canvas, pictures);
  const runtime = createRuntime({size: () => [canvas.clientWidth, canvas.clientHeight], seed: (Math.random() * 65536) | 0,
    load: () => loadSave(storageKey), store: bytes => storeSave(storageKey, bytes),
    frames: {request: requestAnimationFrame.bind(globalThis), cancel: cancelAnimationFrame.bind(globalThis)},
    initial: () => [[8, canvas.clientWidth, canvas.clientHeight], [11, 0]],
    reportError: reportApplicationError});
  const hud = createHud(overlay, (action, argument) => runtime.send(PRESS, action, argument),
                        (action, argument) => runtime.send(HOVER, action, argument), pictures);
  attachInput(canvas, runtime);
  return startPage({runtime,
    imports: {...runtime.imports, 'snail.runtime.browser.screen': screenImports(renderer, pictures, hud)},
    reset() { renderer.forget(); pictures.forget(); }}, url);
}

// Wheel deltas arrive in pixels, lines or pages; the application gets pixels.
function wheelPixels(event) {
  return Math.round(event.deltaY * [1, 16, innerHeight][event.deltaMode]);
}

function attachInput(canvas, runtime) {
  const send = (kind, a = 0, b = 0, c = 0, d = 0) => runtime.send(kind, a | 0, b | 0, c | 0, d | 0);
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
