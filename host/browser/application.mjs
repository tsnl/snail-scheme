// One loader and replacement transaction for every browser application.
// Engines supply device imports and reset their presentation before each run.
import {createWasi, linkProgram} from './load.mjs';
import {applicationEntry, HIDDEN} from './runtime.mjs';

export const running = [];

// The page's program is linked from its manifest, which the build names
// in the page (a `snail-modules` meta element), or from `url`.
export async function startPage(application, url) {
  Object.assign(application, {program: null, errors: []});
  const manifest = document.querySelector('meta[name="snail-modules"]')?.content ?? url;
  if (!manifest) throw new Error('the page names no program manifest');
  await linkApplication(application, manifest, fetchRead(manifest));
  application.reset();
  application.startup = startCold(application);
  running.push(application);
  addEventListener('visibilitychange', () => { if (document.hidden) application.runtime.send(HIDDEN); });
  await application.startup;
  return application;
}

async function linkApplication(application, manifest, read) {
  const wasi = createWasi({print: printer(application)});
  application.program = await linkProgram(read, manifest, wasi, application.imports,
                                          () => application.runtime.execution.tasks);
}

// Only a cold restoration failure before boot may discard saved bytes.
// A first-frame trap already has a committed state and must stay recoverable.
async function startCold(application) {
  const {runtime, program} = application, entry = applicationEntry(program);
  const run = runtime.start(entry);
  try { await run.ready.promise; }
  catch (error) {
    await run.done;
    if (application.strictRestore) throw error;
    if (run.boot !== null || run.loaded == null) { reportApplicationError(error); return; }
    console.warn('discarding an incompatible save:', error.message);
    application.reset();
    const retry = runtime.start(entry, null, {restore: null});
    try { await retry.ready.promise; }
    catch (error) { await retry.done; reportApplicationError(error); }
  }
}

export function reportApplicationError(error) {
  console.error(error);
  dispatchEvent(new ErrorEvent('error', {message: error.message, error}));
}

// A file's bytes, by its path relative to the manifest's or the module's,
// uncached. A file the server does not have is an error, not its error page.
function fetchRead(base) {
  return async file => {
    const response = await fetch(new URL(file, new URL(base, document.baseURI)), {cache: 'no-store'});
    if (!response.ok) throw new Error(`${response.status} fetching ${file}`);
    return new Uint8Array(await response.arrayBuffer());
  };
}

// Lines the program writes go to the console. The last twenty it writes to
// standard error are kept in `errors`, since they explain a trap: a panic
// prints its message before trapping.
function printer(application) {
  return (fd, text) => {
    if (fd !== 2) { console.log(text); return; }
    console.error(text);
    application.errors.push(text);
    application.errors.splice(0, application.errors.length - 20);
  };
}
