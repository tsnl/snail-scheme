// One disk observer for compiler and editor subscribers. Native notifications
// are hints; metadata reconciliation discovers ordinary missed changes. No file
// contents, build scheduling or compiler-interest rules live here.
import {lstatSync, watch} from 'node:fs';
import {lstat, readdir} from 'node:fs/promises';
import {join, resolve, sep} from 'node:path';

function within(directory, path) {
  return path === directory || path.startsWith(directory.endsWith(sep) ? directory : directory + sep);
}

// Directories use identity only: an excluded child's write must not invalidate
// its parent through directory timestamps. Symlinks are recorded, not followed.
function fingerprint(stat) {
  const identity = `${stat.mode}:${stat.dev}:${stat.ino}`;
  return stat.isDirectory() ? identity : `${identity}:${stat.size}:${stat.mtimeNs}:${stat.ctimeNs}`;
}

// Subscribe synchronously after construction, then await reconcile(). Watches
// are installed before the first inventory read. Later subscribers obtain their
// initial files from the file service, not a replayed watcher history.
export function watchProject({roots, exclude = []}) {
  const excluded = exclude.map(path => resolve(path));
  const ignored = path => excluded.some(directory => within(directory, path));
  const paths = [...new Set(roots.map(path => resolve(path)))].filter(path => !ignored(path));
  const watched = paths.filter(path => !paths.some(other => other !== path && within(other, path)))
    .map(path => ({path, handle: null, identity: null}));
  const subscribers = new Set(), failed = new Set();
  let inventory = new Map(), scanning = null, closed = false;

  function emit(event) {
    if (!closed) for (const subscriber of subscribers) subscriber(event);
  }

  function detach(root) {
    const handle = root.handle;
    root.handle = null; root.identity = null;
    handle?.close();
  }

  function background() { void reconcile().catch(() => {}); }

  function attach(root) {
    let stat;
    try { stat = lstatSync(root.path, {bigint: true, throwIfNoEntry: false}); } catch { return; }
    const identity = stat?.isDirectory() ? `${stat.dev}:${stat.ino}` : null;
    if (root.identity !== identity) detach(root);
    if (!identity || root.handle) return;
    try {
      const handle = watch(root.path, {recursive: true}, (_event, name) => {
        const path = name ? resolve(root.path, String(name)) : root.path;
        if (closed || root.handle !== handle || ignored(path)) return;
        emit(name ? {kind: 'hint', path} : {kind: 'uncertain', path: root.path});
        background();
      });
      root.handle = handle; root.identity = identity;
      const lost = () => {
        if (root.handle !== handle) return; // Expected close or an older handle.
        detach(root);
        emit({kind: 'uncertain', path: root.path});
        // The periodic scan retries, avoiding a tight loop of watch failures.
      };
      handle.on('error', lost);
      handle.on('close', lost);
    } catch { /* Periodic reconciliation remains useful without native watches. */ }
  }

  async function collect(path, next) {
    if (closed || ignored(path)) return;
    let stat;
    try { stat = await lstat(path, {bigint: true}); }
    catch (error) { if (error.code === 'ENOENT') return; throw error; }
    if (stat.isDirectory()) {
      let names;
      try { names = await readdir(path); }
      catch (error) { if (error.code === 'ENOENT') return; throw error; }
      next.set(path, fingerprint(stat));
      for (const name of names) await collect(join(path, name), next);
    } else next.set(path, fingerprint(stat));
  }

  async function scan() {
    const next = new Map(), failures = new Map();
    for (const root of watched) {
      if (closed) throw new Error('the project watcher is closed');
      attach(root);
      try { await collect(root.path, next); }
      catch (error) { failures.set(root.path, error); }
    }
    if (closed) throw new Error('the project watcher is closed');
    for (const [path, error] of failures) {
      if (!failed.has(path)) emit({kind: 'uncertain', path, error: error.message});
      failed.add(path);
    }
    if (failures.size) throw new Error(`cannot reconcile ${failures.keys().next().value}`, {cause: failures.values().next().value});
    const paths = [...new Set([...inventory.keys(), ...next.keys()])].filter(path => inventory.get(path) !== next.get(path));
    inventory = next;
    if (paths.length) emit({kind: 'changed', paths});
    for (const path of failed) emit({kind: 'uncertain', path}); // Recovery may unblock a caller.
    failed.clear();
  }

  // A caller during a scan receives the next fresh scan, shared with other
  // waiters. Later notifications do not extend that promise until global quiet.
  async function reconcile() {
    const preceding = scanning;
    if (preceding) await preceding.catch(() => {});
    if (closed) throw new Error('the project watcher is closed');
    return scanning ??= scan().finally(() => { scanning = null; });
  }

  for (const root of watched) attach(root);
  const timer = setInterval(background, 1000);
  timer.unref();
  return {
    subscribe(subscriber) {
      if (closed) throw new Error('the project watcher is closed');
      subscribers.add(subscriber);
      return () => subscribers.delete(subscriber);
    },
    reconcile,
    async close() {
      closed = true;
      clearInterval(timer);
      subscribers.clear();
      for (const root of watched) detach(root);
      await scanning?.catch(() => {});
      inventory.clear(); failed.clear();
    },
  };
}
