// The document engine supplies DOM/fetch devices to the shared page host.
import {createDom} from './dom.mjs';
import {createFetch} from './fetch.mjs';
import {loadSave, storeSave, loadSessionSave, storeSessionSave} from './storage.mjs';
import {createRuntime, applicationEntry} from './runtime.mjs';
import {startPage, reportApplicationError} from './application.mjs';

// Starts the interface in `container`, answering once its first view is
// shown, or failing with the trap that stopped it.
export async function startInterface({url, container, storageKey, session = false, strictRestore = false}) {
  let refreshing = false, deferred = false, composing = false;
  const load = () => session ? loadSessionSave(storageKey) : loadSave(storageKey);
  const store = bytes => session ? storeSessionSave(storageKey, bytes) : storeSave(storageKey, bytes);
  const runtime = createRuntime({size: () => [container.clientWidth, container.clientHeight],
    seed: (Math.random() * 65536) | 0, load, store,
    initial: () => [], reportError: reportApplicationError});
  const dom = createDom(container, runtime, {refresh: () => void refresh()}), requests = createFetch(runtime);
  const application = await startPage({runtime, strictRestore,
    imports: {...runtime.imports, 'snail.runtime.browser.dom': dom.imports, 'snail.runtime.browser.fetch': requests.imports},
    reset() { dom.reset(); requests.reset(); }}, url);

  // Navigation leaves the page only after the stopped root task's final
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
        const restarted = runtime.start(applicationEntry(application.program), null, {restore: stopped.saved});
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
      // Without saved bytes or a replacement, the stopped run still owns
      // the checkpoint that a later source repair must recover.
    }
  }
  application.refresh = refresh;
  return application;
}
