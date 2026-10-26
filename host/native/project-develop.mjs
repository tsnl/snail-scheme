// One project, one compiler worker, one disk observer. The parent owns attempts
// and accepts completed directories; the worker owns successful compiler caches.
import {lstatSync, mkdirSync, mkdtempSync, readdirSync, realpathSync, rmSync} from 'node:fs';
import {basename, join, sep} from 'node:path';
import {Worker} from 'node:worker_threads';
import {applicationProcess} from './application-process.mjs';
import {discardProject, publishProject} from './project.mjs';
import {watchProject} from './watch.mjs';

export class UnknownRunTarget extends Error {
  constructor(name) { super(`unknown accepted run target: ${name}`); }
}

const within = (directory, path) => path === directory || path.startsWith(directory.endsWith(sep) ? directory : directory + sep);

// Source libraries and declared entry/public paths are build inputs. Arbitrary
// data reads by a producer are not tracked yet; manual Build reruns producers.
function inputPath(root, project, description, path) {
  if (path === join(project, 'project.datum')) return true;
  if ((within(project, path) || within(join(root, 'src'), path) || within(join(root, 'guest'), path))
      && path.endsWith('.sld')) return true;
  if (within(join(root, 'host/browser'), path)) return true;
  return description?.builds.some(target => {
    const entry = join(project, target.entry), publicPath = target.public && join(project, target.public);
    return within(path, entry) || (publicPath && (within(publicPath, path) || within(path, publicPath)));
  }) ?? false;
}

// Atomically reserve a namespace before the worker can create generations.
// Sibling generation names preserve the builder's basename-only output links.
function reserve(project) {
  const build = join(project, 'build');
  if (lstatSync(build, {throwIfNoEntry: false})?.isSymbolicLink()) throw new Error(`project build directory cannot be a symbolic link: ${build}`);
  mkdirSync(build, {recursive: true});
  return mkdtempSync(join(build, '.lofi-attempt-'));
}

// Sweep unpublished namespaces only after a reply relinquishes the attempt or
// the worker exits. Publication consumes ownership even when it partly fails.
function abandon(project, attempt) {
  let names;
  try { names = readdirSync(join(project, 'build')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; names = []; }
  for (const name of names) {
    if (name.startsWith(attempt.prefix)) rmSync(join(project, 'build', name), {recursive: true, force: true});
  }
  rmSync(attempt.reservation, {recursive: true, force: true});
}

export function developProject({root, project, tools}) {
  root = realpathSync(root); project = realpathSync(project);
  mkdirSync(join(root, 'build/lofi-run'), {recursive: true});
  const directory = mkdtempSync(join(root, 'build/lofi-run/project-'));
  const files = watchProject({roots: [project, join(root, 'src'), join(root, 'guest'), join(root, 'host/browser')],
    exclude: [join(project, 'build'), join(project, '.git'), join(root, 'build')]});
  let worker;
  try {
    worker = new Worker(new URL('./project-worker.mjs', import.meta.url), {
      workerData: {root, project, tools, directory}, name: 'lofi-project-compiler',
      resourceLimits: {maxYoungGenerationSizeMb: 384},
    });
  } catch (error) { void files.close(); rmSync(directory, {recursive: true, force: true}); throw error; }

  const listeners = new Set(), runs = new Map(), ready = Promise.withResolvers(), exited = Promise.withResolvers();
  // One epoch numbers every attempt, the job sent to the worker, the reply it
  // returns, and the publication that results, so a late or duplicate reply is
  // recognized by comparing numbers rather than by tracking which is current.
  // Subscribers see it as `id`, both the current attempt's and the published
  // build's; those are the same counter.
  let epoch = 0, attempt = null, published = null, description = null;
  // Why an attempt is or is not wanted: `dirty` an input changed since the
  // last one started, `initialized` the first disk reconciliation finished,
  // `diskFailed` the last one did not, so disk cannot be trusted yet.
  let dirty = true, initialized = false, diskFailed = false;
  let phase = 'starting', diagnostics = [], timer = null, closing = null, finishing = null;

  // What a subscriber sees, read from the live state rather than copied into a
  // record kept beside it. Subscribers are trusted host code and must not
  // throw; subscribing delivers the current value.
  function snapshot() {
    return {phase, id: epoch, diagnostics, published, worker: worker.threadId,
      runs: [...runs].map(([name, run]) => ({...run.owner.status, wanted: run.wanted,
        available: launchable(name)}))};
  }

  function notify() {
    for (const listener of listeners) listener(snapshot());
  }

  function report(next, messages = []) {
    phase = next; diagnostics = messages;
    notify();
  }

  function launchable(name) {
    return published?.description.runs.some(target => target.name === name) ?? false;
  }

  function launch(name) {
    const definition = published?.description.runs.find(target => target.name === name);
    if (!definition) return null;
    const target = published.targets.find(target => target.name === definition.build);
    return {identity: JSON.stringify([definition.build, target.digest, definition.args]),
      request: {build: published.id, entry: join(target.directory, 'modules.json'), args: definition.args}};
  }

  // Remember the last issued intent, not the observed PID. A terminal child
  // is not retried, and callbacks cannot enqueue the same replacement twice.
  function reconcileRun(name, run) {
    if (closing) return;
    const next = run.wanted ? launch(name) : null, identity = next?.identity ?? null;
    if (identity === run.issued) return;
    run.issued = identity;
    run.owner.request(next?.request ?? null);
  }

  function acceptRuns() {
    for (const {name} of published.description.runs) {
      if (runs.has(name)) continue;
      const owner = applicationProcess({root, target: name});
      runs.set(name, {owner, wanted: false, issued: null});
      owner.subscribe(value => { if (value.attempt && !closing) notify(); });
    }
    // Commit all removals before callbacks can issue controls. Retain each
    // owner until shutdown, so a reintroduced name cannot overlap its child.
    for (const [name, run] of runs) if (!launch(name)) run.wanted = false;
    for (const [name, run] of runs) reconcileRun(name, run);
  }

  function requiredRun(name, available = true) {
    if (closing) throw new Error('project development is closed');
    const run = runs.get(name);
    if (!run || (available && !launch(name))) throw new UnknownRunTarget(name);
    return run;
  }

  function startRun(name) {
    const run = requiredRun(name);
    if (run.wanted) return;
    run.wanted = true;
    reconcileRun(name, run); notify();
  }

  function stopRun(name) {
    const run = requiredRun(name, false);
    if (!run.wanted) return;
    run.wanted = false;
    reconcileRun(name, run); notify();
  }

  function restartRun(name) {
    const run = requiredRun(name);
    run.wanted = true; run.issued = null;
    reconcileRun(name, run); notify();
  }

  function schedule() {
    clearTimeout(timer);
    if (!closing && initialized && !attempt && dirty) timer = setTimeout(start, 40);
  }

  function requestBuild() {
    if (closing) return;
    dirty = true;
    schedule();
  }

  files.subscribe(event => {
    if (event.kind === 'uncertain') {
      if (diskFailed && !event.error) requestBuild();
      return; // Reconciliation, not uncertainty itself, establishes a change.
    }
    for (const path of event.kind === 'changed' ? event.paths : [event.path]) {
      attempt?.paths.add(path);
      if (inputPath(root, project, description, path)) requestBuild();
    }
  });

  function start() {
    timer = null;
    if (closing || attempt || !dirty) return;
    dirty = false; diskFailed = false; epoch++;
    report('building'); // Previous errors disappear before this attempt starts.
    if (closing) return;
    try {
      const reservation = reserve(project), prefix = basename(reservation) + '-';
      attempt = {reservation, prefix, paths: new Set(), owned: true};
      worker.postMessage({kind: 'build', epoch, prefix});
    } catch (error) { fatal(error); }
  }

  async function complete(result) {
    const current = attempt, built = epoch;
    if (!current || result.epoch !== built) throw new Error('unexpected compiler attempt result');
    if (result.description) description = result.description; // Retain even a failed build's parsed inputs.
    let messages = result.diagnostics;
    try { await files.reconcile(); }
    catch (error) { diskFailed = true; messages = [{severity: 'error', message: error.message}]; }
    const superseded = dirty || [...current.paths].some(path => inputPath(root, project, description, path));
    if (superseded) dirty = true;
    if (result.candidate) {
      if (closing || superseded || diskFailed) discardProject(result.candidate);
      else {
        current.owned = false; // publishProject consumes even a partially published failure.
        try { publishProject(result.candidate); published = {id: built, ...result.candidate}; }
        catch (error) { messages = [{severity: 'error', message: error.message}]; }
      }
    }
    if (current.owned) abandon(project, current);
    else rmSync(current.reservation, {recursive: true, force: true});
    attempt = null;
    if (!closing && published?.id === built) acceptRuns();
    if (!closing) report(superseded ? 'superseded' : messages.length ? 'failed' : 'succeeded', superseded ? [] : messages);
    schedule();
  }

  function fatal(error) {
    if (closing) return;
    report('fatal', [{severity: 'error', message: error.message}]);
    void close().catch(() => {}); // Explicit close() callers still receive cleanup errors.
  }

  worker.on('message', result => {
    if (result.kind === 'ready') { ready.resolve(); return; }
    finishing = complete(result).catch(fatal).finally(() => { finishing = null; });
  });
  worker.on('error', error => { ready.reject(error); fatal(error); });
  worker.on('exit', code => {
    exited.resolve();
    const error = new Error(`compiler worker exited with status ${code}`);
    ready.reject(error);
    if (!closing) fatal(error);
  });

  // A worker message cannot interrupt synchronous Wasm or native IO. Request
  // graceful close, then termination; cleanup waits for actual worker exit.
  // Blocking OS operations can delay exit. This is not a shutdown deadline.
  function close() {
    if (closing) return closing;
    clearTimeout(timer);
    worker.postMessage({kind: 'close'});
    const timeout = setTimeout(() => { void worker.terminate(); }, 2000);
    closing = Promise.resolve().then(async () => {
      const results = await Promise.allSettled([files.close(), exited.promise,
        ...[...runs.values()].map(run => run.owner.close())]);
      clearTimeout(timeout);
      await finishing;
      let failure = results.find(result => result.status === 'rejected')?.reason;
      try {
        if (attempt?.owned) abandon(project, attempt);
        else if (attempt) rmSync(attempt.reservation, {recursive: true, force: true});
      } catch (error) { failure ??= error; }
      try { rmSync(directory, {recursive: true, force: true}); }
      catch (error) { failure ??= error; }
      listeners.clear();
      if (failure) throw failure;
    });
    return closing;
  }

  void (async () => {
    await ready.promise;
    if (closing) return;
    try { await files.reconcile(); }
    catch (error) {
      if (closing) return;
      diskFailed = true; report('failed', [{severity: 'error', message: error.message}]);
    }
    if (closing) return;
    initialized = true;
    if (!diskFailed) schedule();
  })().catch(fatal);

  return {
    files,
    get status() { return snapshot(); },
    requestBuild,
    startRun,
    stopRun,
    restartRun,
    subscribe(listener) {
      if (closing) throw new Error('project development is closed');
      listeners.add(listener); listener(snapshot());
      return () => listeners.delete(listener);
    },
    close,
  };
}
