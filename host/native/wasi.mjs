// Node's WASI methods expect unsigned numbers for preview1's i32 arguments.
// Wasm calls JavaScript with signed i32 values, including addresses above 2 GiB.
// Keep i64 arguments as BigInts: offsets such as fd_seek's may be signed.

// WASI keeps an exit's status where only `start` reads it. Reactors invoke
// their own main, so proc_exit must unwind that invocation explicitly.
export class Exit { constructor(code) { this.code = code; } }

export function exiting(wasi) {
  const imports = wasi.getImportObject();
  const native = Object.fromEntries(Object.entries(imports.wasi_snapshot_preview1).map(([name, fn]) =>
    [name, (...args) => fn(...args.map(value => typeof value === 'number' ? value >>> 0 : value))]));
  imports.wasi_snapshot_preview1 = {...native, proc_exit(code) { throw new Exit(code >>> 0); },
    // uvwasi resolves SYMLINK_FOLLOW before applying CREAT | EXCL. Clear
    // that lookup flag so exclusive creation checks the leaf itself.
    path_open(fd, lookup, path, length, flags, ...rest) {
      return native.path_open(fd, (flags & 5) === 5 ? lookup & ~1 : lookup, path, length, flags, ...rest);
    },
  };
  return {getImportObject: () => imports, initialize: instance => wasi.initialize(instance)};
}
