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

// Instantiates the modules in order. Each sees the runtime, the modules
// before it under their library names, and the host's modules. A module may
// replace one already linked, as a rebuilt library does; `linked` maps
// names to instances and is updated in place.
// A library's module holds all of its functions, so it may import host
// services, such as the screen, that this host lacks and the program never
// calls. Such an import links to a function that fails if called, as a
// statically linked program would have left it out. A missing import from
// the runtime or a library's module still fails to link.
export async function linkModules(runtime, modules, host, linked = new Map()) {
  const libraries = new Set(['snail.library', ...linked.keys(), ...modules.map(entry => entry.name)]);
  for (const {name, module} of modules) {
    const imports = {...host, 'snail.library': runtime.exports};
    for (const [library, instance] of linked) imports[library] = instance.exports;
    const hosted = WebAssembly.Module.imports(module).map(entry => entry.module).filter(from => !libraries.has(from));
    linked.set(name, await WebAssembly.instantiate(module, withStubs(module, imports, hosted, missingHost)));
  }
  return linked;
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

// Runs each module's initialization in program order; the program's own,
// last, returns its status.
export function runModules(linked, names) {
  let status = 0;
  for (const name of names) status = linked.get(name).exports.main();
  return status;
}

// Reads modules.json and compiles every module it names. `read` fetches a
// file's bytes by its name relative to the manifest.
export async function loadManifest(read) {
  const manifest = JSON.parse(new TextDecoder().decode(await read('modules.json')));
  const compile = async file => WebAssembly.compile(await read(file));
  return {
    runtime: await compile(manifest.runtime),
    modules: await Promise.all(manifest.modules.map(async name => ({name, module: await compile(`${name}.wasm`)}))),
  };
}
