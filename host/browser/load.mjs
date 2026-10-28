// The JavaScript side of running Snail-Core, the same in Node and in a browser:
// the WASI a module that opens no files needs, the files a program links,
// linking a program compiled one library at a time and relinking it from a
// rebuilt library, how Snail-Core passes a host strings and commands, and
// reading what the development loop tells pages. It decides nothing about
// what a program is for: the browser host (host.mjs), the development loop's
// hosts and host/native/run-snail.mjs build on it.

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

// A module asks for each file it links, `link-bytes` in (snail shell
// resource), by importing a function from "snail.runtime.link" named for the file,
// which answers the file's handle. The host reads every file a module
// names before it instantiates the module, from resources/NAME beside the
// payload, so reading one is a synchronous lookup on both hosts, and a
// payload whose file cannot be read fails to load, not when the program
// first reads it. Handles index `files`, which only grows: a module
// instantiated again reads its files again, so it sees them as they are
// now, while a module kept linked keeps the bytes it was linked with.
async function linkImports(read, modules, files) {
  const names = [...new Set(modules.flatMap(module => WebAssembly.Module.imports(module)
    .filter(entry => entry.module === 'snail.runtime.link').map(entry => entry.name)))];
  const handles = await Promise.all(names.map(async name => files.push(await readLinked(read, name)) - 1));
  return Object.fromEntries(names.map((name, index) => [name, () => handles[index]]));
}

async function readLinked(read, name) {
  try { return new Uint8Array(await read(`resources/${name}`)); }
  catch (error) { throw new Error(`cannot read the linked file ${name}: ${error.message}`, {cause: error}); }
}

// The `resource` effect of (snail shell resource): a file's length and its
// bytes, by handle.
function resourceImports(files) {
  return {length: handle => files[handle].length, byte: (handle, index) => files[handle][index]};
}

// What a single linked module needs for the files it links, read through
// `read` by their paths beside the payload.
export async function linkedFileImports(read, module) {
  const files = [];
  return {'snail.runtime.link': await linkImports(read, [module], files), 'snail.runtime.resource': resourceImports(files)};
}

// ---- Linking ----

// A program compiled one library at a time is named by its modules.json:
// {"runtime": FILE, "modules": [{"name": LIBRARY, "file": FILE}, ...]}, in
// program order.
function readModules(bytes) {
  return JSON.parse(decoder.decode(bytes));
}

// Links the program a modules.json names: the Rust runtime, initialized
// through `wasi`, then each library's module in program order, so every
// module comes after those it imports from. `read` gives a file's bytes by
// its path, which may be relative to the manifest's. The modules'
// initializations wait for runProgram, so the caller can keep the program
// first. A program is the runtime instance, the host's imports, each
// library's instance by name, the library names in program order, and the
// files its modules link, read before any of them is instantiated.
export async function linkProgram(read, manifest, wasi, host) {
  const {runtime, modules} = readModules(await read(manifest));
  const [runtimeModule, compiled] = await Promise.all([compileFile(read, runtime), compileModules(read, modules)]);
  const program = {read, manifest, runtime: await instantiateRuntime(runtimeModule, wasi), host, linked: new Map(),
                   names: modules.map(entry => entry.name), files: [], links: {}};
  await linkModules(program, compiled);
  return program;
}

// Runs each module's initialization in program order; the program's own,
// last, returns its status.
export function runProgram(program, names = program.names) {
  let status = 0;
  for (const name of names) status = program.linked.get(name).exports.main();
  return status;
}

// What the program's own module, the last, exports.
export function programExports(program) {
  return program.linked.get(program.names.at(-1)).exports;
}

const compileFile = async (read, file) => WebAssembly.compile(await read(file));

function compileModules(read, modules) {
  return Promise.all(modules.map(async ({name, file}) => ({name, module: await compileFile(read, file)})));
}

// The runtime reports a panic through its own export, which the platform
// import forwards to once the instance exists.
async function instantiateRuntime(module, wasi) {
  let runtime = null;
  const platform = {'diagnostics/report-error': (pointer, length) => runtime.exports['snail:report-error'](pointer, length)};
  runtime = await instantiate(module, {...wasi.getImportObject(), 'snail.platform': platform});
  wasi.initialize(runtime);
  return runtime;
}

// The names only a host or the runtime gives a module: the runtime
// interfaces, `snail.runtime.…`, and the Rust support module. A library
// linked under one would take the place of what every module imports from
// there, so none may be.
export const hostProvided = name => name.startsWith('snail.runtime.') || name === 'snail.core.support';

// Instantiates the modules in order into the program's instances, where a
// module may take the place of one of the same name, once the files they
// link are read.
async function linkModules(program, modules) {
  const reserved = modules.find(entry => hostProvided(entry.name));
  if (reserved) throw new Error(`no library may be linked as ${reserved.name}, which the host provides`);
  program.links = await linkImports(program.read, modules.map(entry => entry.module), program.files);
  const libraries = new Set(['snail.core.support', ...program.linked.keys(), ...modules.map(entry => entry.name)]);
  for (const {name, module} of modules) program.linked.set(name, await WebAssembly.instantiate(module, moduleImports(program, libraries, module)));
}

// A module sees the runtime, the modules linked before it under their
// library names, and the host's modules. A library's module holds all of
// its functions, so it may import host services, such as the screen, that
// this host lacks and the program never calls. Such an import links to a
// function that fails if called, as a statically linked program would have
// left it out. A missing import from the runtime or a library's module
// still fails to link.
function moduleImports(program, libraries, module) {
  const imports = {...program.host, 'snail.core.support': program.runtime.exports, 'snail.runtime.link': program.links ?? {},
                   'snail.runtime.resource': resourceImports(program.files ?? [])};
  for (const [library, instance] of program.linked) imports[library] = instance.exports;
  const hosted = WebAssembly.Module.imports(module).map(entry => entry.module).filter(from => !libraries.has(from));
  return withStubs(module, imports, hosted, missingHost);
}

const missingHost = (from, name) => () => { throw new Error(`this host does not provide ${from} ${name}`); };

// ---- Relinking ----

// Links the program again from library `from`, by its modules.json as it
// is now. The modules before `from` cannot import from it, so their
// instances stay; `from` and every module after it are linked anew, reading
// the files they link again, and initialized, so their globals start over.
// Returns the new program and leaves the old one as it was, so a relink that
// fails leaves it running.
export async function relinkProgram(program, from) {
  const {modules} = readModules(await program.read(program.manifest));
  const start = Math.max(0, modules.findIndex(entry => entry.name === from));
  const kept = modules.slice(0, start).map(entry => [entry.name, program.linked.get(entry.name)]);
  const next = {...program, linked: new Map(kept), names: modules.map(entry => entry.name)};
  const relinked = await compileModules(program.read, modules.slice(start));
  await linkModules(next, relinked);
  runProgram(next, relinked.map(entry => entry.name));
  return next;
}

// ---- Loading while the program runs ----

// The `wasm` effect of (snail shell wasm), which reads the files and decides
// what to link; the host only does what it cannot. `compile` takes the
// bytes of a module, `namespace` makes an empty namespace, `instantiate`
// links a module in one under a library name and runs its main, and
// `has-export` and `export-function` find what an instance exports by name.
// Namespace 0 is the program's own, its linked modules; a name already
// there is refused, since the modules that import it keep the instance they
// have. Another namespace holds a plugin's modules: each sees the modules
// before it there, then the runtime and the host's modules, as a
// child-first class loader resolves, and none of the files the program
// links, so a plugin that links files cannot read them yet. A failure
// answers a negative code, which (snail shell wasm) names; a trap in a
// module's main still ends the program, and a main cannot wait.
// The program waits for each operation, so they are synchronous.
// `program()` gives the program that loads, which the host links after
// making these imports.
const INVALID_MODULE = -1, NAME_TAKEN = -1, LINK_FAILED = -2;

export function wasmImports(program) {
  const modules = [], instances = [], namespaces = [], strings = stagedStrings();
  const namespace = handle => (handle === 0 ? program().linked : namespaces[handle - 1]);
  return {
    ...strings.imports,
    compile(address) {
      try { return modules.push(new WebAssembly.Module(byteSnapshot(program().runtime.exports.memory, address))) - 1; }
      catch (error) { if (error instanceof WebAssembly.CompileError) return INVALID_MODULE; throw error; }
    },
    namespace: () => namespaces.push(new Map()),
    instantiate(handle, module) {
      const [name] = strings.take(), linked = namespace(handle);
      if (linked.has(name) || hostProvided(name)) return NAME_TAKEN;
      const instance = linkedInstance(handle === 0 ? program() : {...program(), linked, links: {}, files: []}, modules[module]);
      if (!instance) return LINK_FAILED;
      linked.set(name, instance);
      instance.exports.main?.();
      return instances.push(instance) - 1;
    },
    'has-export': instance => typeof instances[instance].exports[strings.take()[0]] === 'function',
    'export-function': instance => instances[instance].exports[strings.take()[0]],
  };
}

// An instance of the module, linked as a module of `program` is, or null
// if an import has no provider of its type.
function linkedInstance(program, module) {
  try { return new WebAssembly.Instance(module, moduleImports(program, new Set(['snail.core.support', ...program.linked.keys()]), module)); }
  catch (error) { if (error instanceof WebAssembly.LinkError || error instanceof TypeError) return null; throw error; }
}

// ---- Host commands ----

// Snail-Core passes a host strings a character at a time, each ended by
// `argument-end`. A command's strings are its name and its arguments:
// `command` calls the function `commands` has under the name with the
// arguments and a number, and answers with its result, or 0. The `develop`
// effect of src/snail/shell/develop.sld and the `page` effect of
// host/browser/reload.sld are bound this way.
export function commandImports(commands) {
  const strings = stagedStrings();
  return {
    ...strings.imports,
    command(number) {
      const [name, ...args] = strings.take();
      if (!Object.hasOwn(commands, name)) throw new Error(`this host has no command ${name}`);
      return commands[name](args, number) ?? 0;
    },
  };
}

// A foreign Bytes argument borrows staging memory: a little-endian u32
// length at `address` and that many bytes after it. Own its bytes before
// any await or another Wasm call can overwrite or grow the buffer.
export function byteSnapshot(memory, address) {
  const pointer = address >>> 0, buffer = memory.buffer;
  const length = new DataView(buffer).getUint32(pointer, true);
  return new Uint8Array(buffer, pointer + 4, length).slice();
}

function stagedStrings() {
  let staged = [], current = '';
  return {
    imports: {
      'argument-character': code => { current += String.fromCodePoint(code); },
      'argument-end': () => { staged.push(current); current = ''; },
    },
    take() { const taken = staged; staged = []; return taken; },
  };
}

// ---- Events and manifests ----

// The development loop tells pages about builds in Scheme data: `(building
// M)`, `(built MILLISECONDS M)` or `(failed "MESSAGE" M)`, where M is the
// manifest of the latest build that succeeded, `(files ("NAME" "DIGEST")
// ...) (modules ("LIBRARY" "FILE") ...)`: each file a page loads with its
// digest, and the modules in program order. The reload client reads these
// itself (host/browser/reload.sld); JavaScript reads them here, a manifest as
// {files, modules}, each a list of pairs.
export function readEvent(text) {
  const [[kind, ...fields]] = readData(text);
  return {kind, milliseconds: kind === 'built' ? Number(fields[0]) : null, message: kind === 'failed' ? fields[0] : null,
          manifest: manifestOf(fields.slice(-2))};
}

export function readManifest(text) {
  return manifestOf(readData(text));
}

// A manifest as the reload client reads it.
export function manifestText({files, modules}) {
  const quoted = text => `"${text.replace(/["\\]/g, '\\$&').replace(/\n/g, '\\n')}"`;
  const pairs = entries => entries.map(([a, b]) => ` (${quoted(a)} ${quoted(b)})`).join('');
  return `(files${pairs(files)}) (modules${pairs(modules)})`;
}

function manifestOf([[, ...files], [, ...modules]]) {
  return {files, modules};
}

// Lists, string literals and other atoms, as nested arrays of strings.
function readData(text) {
  const stack = [[]];
  for (const [token] of text.matchAll(/[()]|"(?:[^"\\]|\\.)*"|[^\s()"]+/g)) {
    if (token === '(') stack.push([]);
    else if (token === ')') stack.at(-2).push(stack.pop());
    else stack.at(-1).push(token.startsWith('"') ? token.slice(1, -1).replace(/\\(.)/g, (_, c) => (c === 'n' ? '\n' : c)) : token);
  }
  return stack[0];
}
