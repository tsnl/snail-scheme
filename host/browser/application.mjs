// One loader and replacement transaction for every browser application.
// Engines supply device imports and reset their presentation before each run.
import {createWasi, instantiate, linkedFileImports, linkProgram, relinkProgram} from './load.mjs';
import {applicationEntry, HIDDEN} from './runtime.mjs';

export const running = [];

export async function startPage(application, url) {
  Object.assign(application, {program: null, errors: [], capture: null});
  const modules = document.querySelector('meta[name="snail-modules"]')?.content;
  if (modules) await linkApplication(application, modules, fetchRead(modules));
  else await instantiateApplication(application, url);
  application.reset();
  application.startup = startCold(application);
  running.push(application);
  addEventListener('visibilitychange', () => { if (document.hidden) application.runtime.send(HIDDEN); });
  await application.startup;
  return application;
}

async function instantiateApplication(application, url) {
  const wasi = createWasi({print: printer(application)});
  const module = await WebAssembly.compileStreaming(fetch(url));
  const linked = linkedFileImports(fetchRead(url), module, () => application.runtime.execution.tasks);
  const instance = await instantiate(module, {...wasi.getImportObject(), ...application.imports, ...linked});
  wasi.initialize(instance);
  application.program = instance;
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

// ---- Relinking ----

// A full page reload first lets every loop save and return.
export function saveAll() {
  return Promise.all(running.map(async application => { await application.startup; return application.runtime.stop(); }));
}

// `manifest` is the modules.json of the build to relink from, which the
// reload client names; each program reads its files relative to it from
// then on.
export async function relinkAll(from, fresh, manifest) {
  for (const application of running) await relinkApplication(application, from, fresh, manifest);
}

// No Snail-Core stack remains while modules relink. Keep the old program and its
// immutable handover until the candidate finishes its initial presentation.
// Rejected migration restarts the old entry; host resources outlive both.
async function relinkApplication(application, from, fresh, manifest) {
  await application.startup;
  const {runtime, program: previous} = application;
  application.capture = [];
  const {state, saved} = await runtime.stop();
  try {
    const program = await relinkProgram(previous, from, manifest, fetchRead(manifest));
    application.reset();
    const run = runtime.start(applicationEntry(program), fresh ? null : state, {restore: fresh ? null : saved});
    await run.ready.promise;
    application.program = program;
  } catch (error) {
    await runtime.execution.done;
    application.reset();
    const rollback = runtime.start(applicationEntry(previous), state, {restore: saved});
    try { await rollback.ready.promise; } catch { await rollback.done; }
    throw new Error(application.capture.join('\n') || error.message);
  } finally {
    application.capture = null;
  }
}
