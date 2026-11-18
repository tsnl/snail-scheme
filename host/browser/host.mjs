// The browser host for a `snail-scheme` application built with (snail shell app). It owns no
// game rules: DOM listeners queue events; the loop runs as a `snail-scheme` task,
// draws on the canvas through the `gpu` effect, shows its HUD in the overlay
// through the `dom` effect, reads files through the `fetch` effect, takes the files its user
// drops or picks through `files`, and
// waits on storage by ticket.

import {createDom} from './dom.mjs';
import {createGpu} from './gpu.mjs';
import {createFetch} from './fetch.mjs';
import {createFiles} from './files.mjs';
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

// ---- Application ----

export async function startApplication({url, canvas, overlay, storageKey}) {
  const runtime = createRuntime({size: () => [canvas.clientWidth, canvas.clientHeight], seed: (Math.random() * 65536) | 0,
    load: () => loadSave(storageKey), store: bytes => storeSave(storageKey, bytes),
    frames: {request: requestAnimationFrame.bind(globalThis), cancel: cancelAnimationFrame.bind(globalThis)},
    initial: () => [[8, canvas.clientWidth, canvas.clientHeight], [11, 0]],
    reportError: reportApplicationError});
  const dom = createDom(overlay, runtime), gpu = createGpu(canvas, runtime), requests = createFetch(runtime);
  const files = createFiles(runtime);
  attachInput(canvas, runtime);
  return startPage({runtime,
    imports: {...runtime.imports, 'snail.runtime.browser.dom': dom.imports, 'snail.runtime.gpu': gpu.imports,
      'snail.runtime.browser.fetch': requests.imports, 'snail.runtime.browser.files': files.imports},
    reset() { dom.reset(); gpu.reset(); requests.reset(); files.reset(); }}, url);
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
