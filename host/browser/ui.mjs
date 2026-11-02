// The browser host for a document interface built with `define-ui`
// (src/snail/shell/ui/page.sld): host.mjs's application host without the
// canvas, renderer and HUD. The interface's root task runs `run-ui` over
// the container's document (dom.mjs), polls the event queue its listeners
// fire into, and stores its save when the page is hidden; its commands ask
// the server through fetch.mjs. Live reload is host.mjs's alone for now:
// this host loads a release build's program.wasm.

import {createDom} from './dom.mjs';
import {createFetch} from './fetch.mjs';
import {loadSave, storeSave} from './storage.mjs';
import {createWasi, instantiate, linkedFileImports, runMain} from './load.mjs';
import {createRuntime, applicationEntry, HIDDEN} from './runtime.mjs';

// Starts the interface in `container`, answering once its first view is
// shown, or failing with the trap that stopped it.
export async function startInterface({url, container, storageKey}) {
  const runtime = createRuntime({size: () => [container.clientWidth, container.clientHeight],
    seed: (Math.random() * 65536) | 0, load: () => loadSave(storageKey), store: bytes => storeSave(storageKey, bytes),
    reportError: reportInterfaceError});
  const dom = createDom(container, runtime), requests = createFetch(runtime);
  const program = await instantiateInterface(url, {...runtime.imports, 'snail.runtime.browser.dom': dom.imports,
    'snail.runtime.browser.fetch': requests.imports}, () => runtime.execution.tasks);
  addEventListener('visibilitychange', () => { if (document.hidden) runtime.send(HIDDEN); });
  await startCold(runtime, () => { dom.reset(); requests.reset(); }, applicationEntry(program));
  return {runtime, program};
}

async function instantiateInterface(url, imports, tasks) {
  const wasi = createWasi({print: (fd, text) => (fd === 2 ? console.error : console.log)(text)});
  const module = await WebAssembly.compileStreaming(fetch(url));
  const linked = linkedFileImports(fetchRead(url), module, tasks);
  const instance = await instantiate(module, {...wasi.getImportObject(), ...imports, ...linked});
  wasi.initialize(instance);
  runMain(instance.exports);
  return instance;
}

// As host.mjs starts an application: only a save that fails to restore
// before boot is discarded, and the interface starts again from `init`.
async function startCold(runtime, reset, entry) {
  const run = runtime.start(entry);
  try { await run.ready.promise; return; }
  catch (error) {
    await run.done;
    if (run.boot !== null || run.loaded == null) throw error;
    console.warn('discarding an incompatible save:', error.message);
  }
  reset();
  const retry = runtime.start(entry, null, {restore: null});
  try { await retry.ready.promise; }
  catch (error) { await retry.done; throw error; }
}

function reportInterfaceError(error) {
  console.error(error);
  dispatchEvent(new ErrorEvent('error', {message: error.message, error}));
}

function fetchRead(base) {
  return async file => {
    const response = await fetch(new URL(file, new URL(base, location.href)), {cache: 'no-store'});
    if (!response.ok) throw new Error(`${response.status} fetching ${file}`);
    return new Uint8Array(await response.arrayBuffer());
  };
}
