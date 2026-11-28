// The JavaScript side of running `snail-scheme`, the same in Node and in a browser:
// the WASI a module that opens no files needs, the files a program links,
// instantiating a program's module, the WebAssembly operations (snail shell
// wasm) loads modules with, and how `snail-scheme` passes a host strings. It decides nothing about what a program is for: the
// browser host (host.mjs) and host/native/run-snail.mjs build on it.

import {blobPartSize, blobPartsPrefix} from './blob-format.mjs';
export {blobPartSize};

const encoder = new TextEncoder(), decoder = new TextDecoder();

// ---- WASI ----

const EBADF = 8, ENOSYS = 52;

// What a module that opens no files needs of WASI, shaped as Node's WASI
// is, so a host passes either: `getImportObject()` gives the imports, and
// `initialize(instance)` finds the memory and runs the module's
// initialization. The module gets `args`, an empty environment, randomness,
// the clocks, and no preopened directories, which wasi-libc learns from
// EBADF, so every path operation fails before it asks the host. What it
// writes reaches `print(fd, line)` a line at a time; exiting throws.
// `instantiate` answers every other function with ENOSYS.
export function createWasi({args = [], print}) {
  let memory = null;
  const view = () => new DataView(memory.buffer), bytes = (pointer, length) => new Uint8Array(memory.buffer, pointer, length);
  const encoded = args.map(argument => encoder.encode(`${argument}\0`)), lines = new Map();
  const imports = {
    args_sizes_get(count, size) {
      view().setUint32(count, encoded.length, true);
      view().setUint32(size, encoded.reduce((total, argument) => total + argument.length, 0), true);
      return 0;
    },
    args_get(pointers, buffer) {
      for (const argument of encoded) {
        view().setUint32(pointers, buffer, true);
        bytes(buffer, argument.length).set(argument);
        pointers += 4;
        buffer += argument.length;
      }
      return 0;
    },
    environ_sizes_get(count, size) { view().setUint32(count, 0, true); view().setUint32(size, 0, true); return 0; },
    environ_get: () => 0,
    random_get(pointer, length) { crypto.getRandomValues(bytes(pointer, length)); return 0; },
    // Nanoseconds: clock 0 is the time of day, and the others count from
    // when the page started, never backwards.
    clock_time_get(clock, precision, time) {
      view().setBigUint64(time, BigInt(Math.round((clock === 0 ? Date.now() : performance.now()) * 1e6)), true);
      return 0;
    },
    fd_prestat_get: () => EBADF,
    fd_prestat_dir_name: () => EBADF,
    fd_write(fd, iovs, count, written) {
      let total = 0, text = lines.get(fd) ?? '';
      for (let i = 0; i < count; i++) {
        const length = view().getUint32(iovs + 8 * i + 4, true);
        text += decoder.decode(bytes(view().getUint32(iovs + 8 * i, true), length));
        total += length;
      }
      const complete = text.split('\n');
      lines.set(fd, complete.pop());
      for (const line of complete) print(fd, line);
      view().setUint32(written, total, true);
      return 0;
    },
    proc_exit(code) { throw new Error(`the module exited with status ${code}`); },
  };
  return {
    getImportObject: () => ({wasi_snapshot_preview1: imports}),
    initialize(instance) { memory = instance.exports.memory; instance.exports._initialize(); },
  };
}

// Instantiates a compiled module whose WASI imports may be incomplete, as
// createWasi's are: each missing WASI function answers ENOSYS. Any other
// missing import still fails to link.
export function instantiate(module, imports) {
  return WebAssembly.instantiate(module, withStubs(module, imports, ['wasi_snapshot_preview1'], () => () => ENOSYS));
}

// The imports with each missing function of the modules named in `stubbed`
// replaced by what `stub` makes for it.
function withStubs(module, imports, stubbed, stub) {
  const complete = {...imports};
  for (const {module: from, name, kind} of WebAssembly.Module.imports(module)) {
    if (kind !== 'function' || !stubbed.includes(from) || complete[from]?.[name]) continue;
    complete[from] = {...complete[from], [name]: stub(from, name)};
  }
  return complete;
}

// ---- Linked files ----

// A module asks for each file it links, `link-file` in (snail shell
// resource), by importing a function from "snail.runtime.link" named for
// the SHA-256 of the file's bytes (plus its length and part width for multipart files).
// The import answers a handle. The host reads the file from the
// program's store the first time a task asks for
// its bytes, and keeps them, so a file the program never reads is never
// fetched. Handles index `files`, one for each digest the program has
// linked, which only grows. The bytes under a digest never change, so a
// module linked again shares the handles, and the bytes, of the files it
// still links, while an edited file is a new digest, read from the store
// of the build that links it. `read` gives an object's bytes by digest.
function linkImports(read, modules, files) {
  const names = [...new Set(modules.flatMap(module => WebAssembly.Module.imports(module)
    .filter(entry => entry.module === 'snail.runtime.link').map(entry => entry.name)))];
  const known = new Map(files.map((file, handle) => [file.name, handle]));
  const handles = names.map(name => {
    if (!known.has(name)) return files.push({name, read, bytes: null}) - 1;
    files[known.get(name)].read = read;
    return known.get(name);
  });
  return Object.fromEntries(names.map((name, index) => [name, () => handles[index]]));
}

async function readLinked({name, read}) {
  try {
    const [digest, size, width, ...extra] = name.split(':');
    if (extra.length) throw new Error('invalid linked blob descriptor');
    if (width !== undefined && Number(width) !== blobPartSize) throw new Error('unknown blob part size');
    return new Uint8Array(await read(digest, size === undefined ? undefined : Number(size)));
  }
  catch (error) { throw new Error(`cannot read the linked file ${name}: ${error.message}`, {cause: error}); }
}

// Reads an object by its digest from store/ beside the program, sharded by
// the digest's first two hex digits, as every build lays out its store
// (the builder's "Linked files").
export const objectPath = digest => `store/sha256/${digest.slice(0, 2)}/${digest}`;
export const partPath = (digest, index) => `store/${blobPartsPrefix}/${digest.slice(0, 2)}/${digest}/${index}`;

// The import or resource catalog gives the length. Each numbered part has
// exactly its portion of that length, including a full-sized final part.
export async function readBlobParts(digest, size, read) {
  const width = blobPartSize;
  if (!/^[0-9a-f]{64}$/.test(digest) || !Number.isSafeInteger(size) || size <= width || size > 0x7fffffff)
    throw new Error('invalid multipart blob identity or byte length');
  let bytes;
  for (let offset = 0, index = 0; offset < size; offset += width, index++) {
    const length = Math.min(size - offset, width);
    const raw = await read(partPath(digest, index), length, offset, index);
    const part = ArrayBuffer.isView(raw) ? new Uint8Array(raw.buffer, raw.byteOffset, raw.byteLength) : new Uint8Array(raw);
    if (part.length !== length) throw new Error(`part ${index} of ${digest}: expected ${length} bytes, received ${part.length}`);
    bytes ??= new Uint8Array(size);
    bytes.set(part, offset);
  }
  return bytes;
}

export function readStoredBlob(read, digest, size, width) {
  return size === undefined ? read(objectPath(digest)) : readBlobParts(digest, size, path => read(path), width);
}

export async function matchesDigest(bytes, digest) {
  const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return Array.from(hash, byte => byte.toString(16).padStart(2, '0')).join('') === digest;
}

const objectReader = read => async (digest, size, width) => {
  const bytes = await readStoredBlob(read, digest, size, width);
  if (size !== undefined && globalThis.crypto?.subtle && !await matchesDigest(bytes, digest))
    throw new Error('multipart blob did not match SHA-256 ' + digest);
  return bytes;
};

// The `Resources` capability of (snail shell resource): a task starts reading a
// file by handle under its ticket (tasks.mjs), finishes the ticket for
// the file's length, and then reads the bytes held until the next finish.
// A file that cannot be read traps the task that finishes it.
function resourceImports(files, tasks) {
  let held = new Uint8Array();
  return {
    read(ticket, handle) {
      const file = files[handle];
      const pending = file.bytes ??= readLinked(file).catch(error => { file.bytes = null; throw error; });
      tasks().start(Number(ticket), () => pending, bytes => { held = bytes; return bytes.length; });
    },
    finish: ticket => tasks().finish(Number(ticket)),
    byte: index => held[index],
  };
}

// The tasks of a host that runs none, for a program that never reads a
// file it links.
const noTasks = () => { throw new Error('this host runs no tasks to read a linked file in'); };

// What a single linked module needs for the files it links, objects of
// store/ beside it, read through `read` by their paths beside the payload
// in the tasks `tasks` gives.
export function linkedFileImports(read, module, tasks = noTasks, readObject = objectReader(read)) {
  const files = [];
  return {'snail.runtime.link': linkImports(readObject, [module], files), 'snail.runtime.resource': resourceImports(files, tasks)};
}

// ---- Linking ----

// Links a build's program, NAME.wasm: one module holding the runtime and
// every library, initialized through `wasi`, whose files are objects of
// store/ beside it, read in the tasks `tasks` gives. Its own exports are
// the runtime's and the program's. A missing WASI function answers ENOSYS.
// The module holds every function of its libraries, so it may import host
// services, such as the screen, that this host lacks and the program never
// calls: such an import links to a function that fails if called.
export async function linkModule(read, name, wasi, host, tasks = noTasks, readObject) {
  const module = await WebAssembly.compile(await read(name));
  const imports = {...wasi.getImportObject(), ...host, ...linkedFileImports(read, module, tasks, readObject)};
  const hosted = WebAssembly.Module.imports(module).map(entry => entry.module).filter(hostProvided);
  const runtime = await instantiate(module, withStubs(module, imports, hosted, missingHost));
  wasi.initialize(runtime);
  return {runtime, exports: runtime.exports, host};
}

// The modules a host gives a program: the runtime's interfaces.
const hostProvided = name => name.startsWith('snail.runtime.') || name === 'snail.core.support';

const missingHost = (from, name) => () => { throw new Error(`this host does not provide ${from} ${name}`); };

// Starts the program's main as the first task of the run's scheduler, which
// the run's turns then run. Linking a library never executes source code.
export function runMain(exports, tasks) {
  if (!exports.main) throw new Error('the program has no main function');
  exports.main(tasks.owner);
}

// ---- Host commands ----


// A foreign Bytes argument borrows staging memory: a little-endian u32
// length at `address` and that many bytes after it. Own its bytes before
// any await or another Wasm call can overwrite or grow the buffer.
export function byteSnapshot(memory, address) {
  const pointer = address >>> 0, buffer = memory.buffer;
  const length = new DataView(buffer).getUint32(pointer, true);
  return new Uint8Array(buffer, pointer + 4, length).slice();
}

// The same bytes in place, without a copy: for a consumer that copies or
// reads them before it returns, as WebGPU's writes and TextDecoder do.
export function byteView(memory, address) {
  const pointer = address >>> 0, buffer = memory.buffer;
  const length = new DataView(buffer).getUint32(pointer, true);
  return new Uint8Array(buffer, pointer + 4, length);
}

// Strings `snail-scheme` sends a character at a time, each ended by
// `argument-end`; `take` gives those sent since it last took them.
export function stagedStrings() {
  let staged = [], current = '';
  return {
    imports: {
      'argument-character': code => { current += String.fromCodePoint(code); },
      'argument-end': () => { staged.push(current); current = ''; },
    },
    take() { const taken = staged; staged = []; return taken; },
  };
}
