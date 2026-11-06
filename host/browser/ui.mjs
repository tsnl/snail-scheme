// The browser host for a document interface built with `define-ui`
// (src/snail/shell/ui/page.sld): host.mjs's application host without the
// canvas, renderer and HUD. The interface's root task runs `run-ui` over
// the container's document (dom.mjs), polls the event queue its listeners
// fire into, and stores its save when the page is hidden; its commands ask
// the server through fetch.mjs. A refresh request checkpoints the interface
// and navigates only after recovery storage succeeds.

import {createDom} from './dom.mjs';
import {createFetch} from './fetch.mjs';
import {loadSave, storeSave, loadSessionSave, storeSessionSave} from './storage.mjs';
import {createWasi, instantiate, linkedFileImports, runMain} from './load.mjs';
import {createRuntime, applicationEntry, HIDDEN} from './runtime.mjs';

// Starts the interface in `container`, answering once its first view is
// shown, or failing with the trap that stopped it.
export async function startInterface({url, container, storageKey, session = false, strictRestore = false}) {
  let refreshing = false, deferred = false, composing = false;
  const load = () => session ? loadSessionSave(storageKey) : loadSave(storageKey);
  const store = bytes => session ? storeSessionSave(storageKey, bytes) : storeSave(storageKey, bytes);
  const runtime = createRuntime({size: () => [container.clientWidth, container.clientHeight],
    seed: (Math.random() * 65536) | 0, load, store,
    reportError: reportInterfaceError});
  const dom = createDom(container, runtime, {refresh: () => void refresh()}), requests = createFetch(runtime);
  const program = await instantiateInterface(url, {...runtime.imports, 'snail.runtime.browser.dom': dom.imports,
    'snail.runtime.browser.fetch': requests.imports}, () => runtime.execution.tasks);
  addEventListener('visibilitychange', () => { if (document.hidden) runtime.send(HIDDEN); });
  await startCold(runtime, () => { dom.reset(); requests.reset(); }, applicationEntry(program), strictRestore);

  // Navigation transfers ownership only after the stopped root task's final
  // checkpoint is durably stored. Stop drains queued input; inert prevents
  // further edits while asynchronous storage is outstanding. Wait for the
  // final composition input before freezing an IME editor.
  const compositionEnded = new Set();
  container.addEventListener('compositionstart', () => { composing = true; }, true);
  container.addEventListener('compositionend', () => {
    composing = false;
    for (const done of compositionEnded) done();
    compositionEnded.clear();
  }, true);
  async function refresh() {
    if (refreshing) return;
    if (deferred) { dispatchEvent(new Event('snail-refresh-failed')); return; }
    refreshing = true;
    do {
      if (composing) await new Promise(resolve => compositionEnded.add(resolve));
      await new Promise(resolve => setTimeout(resolve, 0));
    } while (composing);
    container.inert = true;
    const block = event => { event.preventDefault(); event.stopImmediatePropagation(); };
    for (const type of ['keydown', 'beforeinput', 'click']) addEventListener(type, block, true);
    let stopped;
    try {
      stopped = await runtime.stop();
      if (stopped.error) throw stopped.error;
      if (stopped.saved == null) throw new Error('the interface did not provide a recovery checkpoint');
      // The ordinary background checkpoint tolerates storage failures. An
      // intentional navigation requires an explicit successful write.
      await store(stopped.saved);
      dom.allowUnload();
      location.reload();
    } catch (error) {
      deferred = true;
      if (stopped?.saved != null) {
        dom.reset(); requests.reset();
        // Reconstruct from the application's save, so canceled commands do
        // not leave in-flight flags or dead handles in the resumed model.
        const restarted = runtime.start(applicationEntry(program), null, {restore: stopped.saved});
        await restarted.ready.promise;
      }
      const notice = document.createElement('div');
      notice.role = 'alert';
      notice.textContent = `Refresh deferred; your edits are still open. ${error.message}`;
      const retry = document.createElement('button');
      retry.textContent = 'Retry refresh';
      retry.onclick = () => { notice.remove(); deferred = false; void refresh(); };
      notice.append(' ', retry);
      container.before(notice);
      refreshing = false;
      container.inert = false;
      dispatchEvent(new Event('snail-refresh-failed'));
      for (const type of ['keydown', 'beforeinput', 'click']) removeEventListener(type, block, true);
    }
  }
  return {runtime, program, refresh};
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
async function startCold(runtime, reset, entry, strictRestore) {
  const run = runtime.start(entry);
  try { await run.ready.promise; return; }
  catch (error) {
    await run.done;
    if (strictRestore || run.boot !== null || run.loaded == null) throw error;
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
    const response = await fetch(new URL(file, new URL(base, document.baseURI)), {cache: 'no-store'});
    if (!response.ok) throw new Error(`${response.status} fetching ${file}`);
    return new Uint8Array(await response.arrayBuffer());
  };
}
