// The `hints` effect of src/snail/shell/watch.sld: Node's recursive watch
// of a tree, as a hint that something under it changed. A hint carries no
// path, so a watch only remembers whether one came since the last wait took
// it. A watch that fails is closed, and its program's periodic inventory
// carries on without it.
import {watch} from 'node:fs';
import {resolve, sep} from 'node:path';

const within = (directory, path) => path === directory || path.startsWith(directory + sep);

export function createHints() {
  const watches = new Map();
  let next = 0;

  function hinted(entry) {
    entry.hinted = true;
    const wake = entry.waiting;
    entry.waiting = null;
    wake?.(1);
  }

  function close(id) {
    const entry = watches.get(id);
    if (!entry) return;
    watches.delete(id);
    entry.handle.close();
    entry.waiting?.(0);
  }

  // `watch ROOT EXCLUDED...` answers the watch's number, or -1; `unwatch`
  // takes the number.
  const commands = {
    watch([root, ...excluded]) {
      const ignored = excluded.map(path => resolve(path));
      let handle;
      try { handle = watch(root, {recursive: true}); } catch { return -1; }
      const id = next++, entry = {handle, hinted: false, waiting: null};
      handle.on('change', (_event, name) => {
        if (name === null || !ignored.some(directory => within(directory, resolve(root, String(name))))) hinted(entry);
      });
      handle.on('error', () => close(id));
      watches.set(id, entry);
      return id;
    },
    unwatch(_, id) { close(id); return 0; },
  };

  // A wait answers 1 at once for a hint it has not taken, and otherwise
  // waits for the next; 0 once the watch is closed or the run ends.
  function waits(tasks) {
    return {
      'start-hint'(ticket, id) {
        tasks.start(Number(ticket), signal => new Promise(answer => {
          const entry = watches.get(id);
          if (!entry) return answer(0);
          if (entry.hinted) { entry.hinted = false; return answer(1); }
          entry.waiting = value => { entry.hinted = false; answer(value); };
          signal.addEventListener('abort', () => answer(0), {once: true});
        }), value => value);
      },
      'finish-hint': ticket => tasks.finish(Number(ticket)),
    };
  }

  return {commands, waits, shutdown() { for (const id of [...watches.keys()]) close(id); }};
}
