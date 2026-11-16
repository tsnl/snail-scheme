// The browser host for a `snail-scheme` application built with (snail shell app). It owns no
// game rules: DOM listeners queue events; the loop runs as a `snail-scheme` task,
// presents through the `screen` effect, shows its HUD in the overlay through
// the `dom` effect, and waits on storage by ticket.

import {createRenderer} from './renderer.mjs';
import {createDom} from './dom.mjs';
import {createPictures} from './pictures.mjs';
import {loadSave, storeSave} from './storage.mjs';
import {createRuntime} from './runtime.mjs';
import {startPage, reportApplicationError} from './application.mjs';

// ---- Input encoding ----

// Input kinds and named keys match `decode-input` and the key constants in
// src/snail/shell/app.sld.
const KEY_DOWN = 1, KEY_UP = 2, POINTER_DOWN = 3, POINTER_MOVE = 4, POINTER_UP = 5, POINTER_CANCEL = 6;
const WHEEL = 7, RESIZE = 8;
const namedKeys = {ArrowLeft: 1, ArrowRight: 2, ArrowUp: 3, ArrowDown: 4, Escape: 27, Enter: 13, ' ': 32};

function keyCode(event) {
  if (event.key in namedKeys) return namedKeys[event.key];
  return [...event.key].length === 1 ? event.key.toLowerCase().codePointAt(0) : 0;
}

// ---- Screen effect ----

// The `screen` effect of src/snail/shell/app.sld, in two parts: frames for the
// renderer, and pictures for the picture store, which the renderer reads
// and the HUD's images show. A test passes its own renderer and picture
// store, each with just what its part calls.
export function screenImports(renderer, pictures) {
  return {...frameImports(renderer), ...pictureImports(pictures)};
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
  let picture = null, source = null, url = [];
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
    // A picture's address, answered a scalar at a time.
    'picture-url'(key) {
      url = [...pictures.url(key)];
      return url.length;
    },
    'picture-url-scalar': index => url[index].codePointAt(0),
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
  const dom = createDom(overlay, runtime);
  attachInput(canvas, runtime);
  return startPage({runtime,
    imports: {...runtime.imports, 'snail.runtime.browser.screen': screenImports(renderer, pictures),
              'snail.runtime.browser.dom': dom.imports},
    reset() { renderer.forget(); pictures.forget(); dom.reset(); }}, url);
}

// Wheel deltas arrive in pixels, lines or pages; the application gets pixels.
function wheelPixels(event) {
  return Math.round(event.deltaY * [1, 16, innerHeight][event.deltaMode]);
}

function attachInput(canvas, runtime) {
  const send = (kind, a = 0, b = 0, c = 0, d = 0) => runtime.send(kind, a | 0, b | 0, c | 0, d | 0);
  // A key held with Ctrl, Alt or Meta belongs to the browser, so shortcuts
  // such as reloading keep working; Shift travels with the key. Keys typed
  // into a field stay there.
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
