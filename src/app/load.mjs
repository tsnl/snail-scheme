// Links a program compiled one library at a time: the Rust runtime first,
// then each library's module in program order, so every module comes after
// those it imports from. An import names the module that provides it: the
// runtime ("snail.library"), an earlier library, or the host. The loader
// decides nothing else, and works the same in Node and in a browser.

// The runtime reports a panic through its own export, which the platform
// import forwards to once the instance exists. Linked alone, the runtime
// imports more of WASI than a merged program keeps; a host that provides
// only what programs call, as a browser does, answers the rest with ENOSYS.
export async function instantiateRuntime(module, wasiImports) {
  let runtime = null;
  const platform = {'diagnostics/report-error': (pointer, length) => runtime.exports['snail:report-error'](pointer, length)};
  const imports = withStubs(module, {...wasiImports, 'snail.platform': platform}, ['wasi_snapshot_preview1'], () => () => ENOSYS);
  runtime = await WebAssembly.instantiate(module, imports);
  return runtime;
}

const ENOSYS = 52;

// Instantiates the modules in order. A module may replace one already
// linked, as a rebuilt library does; `linked` maps names to instances and is
// updated in place.
export async function linkModules(runtime, modules, host, linked = new Map()) {
  const libraries = new Set(['snail.library', ...linked.keys(), ...modules.map(entry => entry.name)]);
  for (const {name, module} of modules) linked.set(name, await WebAssembly.instantiate(module, moduleImports(runtime, host, linked, libraries, module)));
  return linked;
}

// A module sees the runtime, the modules linked before it under their
// library names, and the host's modules. A library's module holds all of
// its functions, so it may import host services, such as the screen, that
// this host lacks and the program never calls. Such an import links to a
// function that fails if called, as a statically linked program would have
// left it out. A missing import from the runtime or a library's module
// still fails to link.
function moduleImports(runtime, host, linked, libraries, module) {
  const imports = {...host, 'snail.library': runtime.exports};
  for (const [library, instance] of linked) imports[library] = instance.exports;
  const hosted = WebAssembly.Module.imports(module).map(entry => entry.module).filter(from => !libraries.has(from));
  return withStubs(module, imports, hosted, missingHost);
}

const missingHost = (from, name) => () => { throw new Error(`this host does not provide ${from} ${name}`); };

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

// ---- Loading while the program runs ----

// The `wasm` effect of (lofi wasm). A program loads a module from a file,
// linked as its own modules are, after them and the modules it loaded
// before, and takes the functions the module exports. The program waits
// for both, so they are synchronous. `read` gives a file's bytes.
export function wasmImports(runtime, host, linked, read) {
  const loaded = [];
  let staged = [], current = '';
  const take = () => { const taken = staged; staged = []; return taken; };
  return {
    'argument-character': code => { current += String.fromCodePoint(code); },
    'argument-end': () => { staged.push(current); current = ''; },
    load() {
      const [name, file] = take(), module = new WebAssembly.Module(read(file));
      const libraries = new Set(['snail.library', ...linked.keys()]);
      linked.set(name, new WebAssembly.Instance(module, moduleImports(runtime, host, linked, libraries, module)));
      return loaded.push(linked.get(name)) - 1;
    },
    'export-function'(handle) {
      const [name] = take(), value = loaded[handle].exports[name];
      if (typeof value !== 'function') throw new Error(`the module exports no function ${name}`);
      return value;
    },
  };
}

// ---- Running ----

// Runs each module's initialization in program order; the program's own,
// last, returns its status.
export function runModules(linked, names) {
  let status = 0;
  for (const name of names) status = linked.get(name).exports.main();
  return status;
}

// Reads a modules.json and compiles the runtime and every module it names:
// {"runtime": FILE, "modules": [{"name": LIBRARY, "file": FILE}, ...]}, in
// program order. `read` fetches a file's bytes by its path, which may be
// relative to the manifest's.
export async function loadManifest(read, manifest = 'modules.json') {
  const {runtime, modules} = JSON.parse(new TextDecoder().decode(await read(manifest)));
  const compile = async file => WebAssembly.compile(await read(file));
  return {
    runtime: await compile(runtime),
    modules: await Promise.all(modules.map(async ({name, file}) => ({name, file, module: await compile(file)}))),
  };
}
