// The document engine supplies DOM/fetch devices to the shared page host.
import {createDom} from './dom.mjs';
import {createFetch} from './fetch.mjs';
import {loadSave, storeSave, loadSessionSave, storeSessionSave} from './storage.mjs';
import {createRuntime} from './runtime.mjs';
import {startPage, reportApplicationError} from './application.mjs';

// Starts the interface in `container`, answering once its first view is
// shown, or failing with the trap that stopped it.
export async function startInterface({url, container, storageKey, session = false}) {
  const load = () => session ? loadSessionSave(storageKey) : loadSave(storageKey);
  const store = bytes => session ? storeSessionSave(storageKey, bytes) : storeSave(storageKey, bytes);
  const runtime = createRuntime({size: () => [container.clientWidth, container.clientHeight],
    seed: (Math.random() * 65536) | 0, load, store,
    initial: () => [], reportError: reportApplicationError});
  const dom = createDom(container, runtime), requests = createFetch(runtime);
  return startPage({runtime,
    imports: {...runtime.imports, 'snail.runtime.browser.dom': dom.imports, 'snail.runtime.browser.fetch': requests.imports},
    reset() { dom.reset(); requests.reset(); }}, url);
}
