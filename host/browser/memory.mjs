// The host cannot make an integer pointer a Wasm GC root. Keep explicit roots
// for handovers, and restore shadow frames when a trap leaves an invocation.

const invocations = [];
export function callingRuntime() { return invocations.at(-1); }
export function rawExports(exports) { return rawViews.get(exports) ?? exports; }

export function invoke(runtime, fn, ...args) {
  if (!runtime?.['snail:gc/checkpoint']) return fn(...args);
  const depth = runtime['snail:gc/checkpoint']();
  invocations.push(runtime);
  let failure;
  try { return fn(...args); }
  catch (error) { failure = error; throw error; }
  finally {
    invocations.pop();
    try { runtime['snail:gc/restore'](depth); }
    catch (error) { if (!failure) throw error; }
  }
}

// The compiler engine only forwards code references between its own runtime
// and the program it loads. Recreate the descriptor in the receiving heap;
// an address from the engine must never be scanned or dereferenced there.
// Both loaders retain their instances for this entire run.
export function transferCode(runtime, value) {
  const source = values.get(value) ?? {runtime: callingRuntime(), address: value};
  if (!runtime?.['snail:gc/code-new'] || source.runtime === runtime) return managedValue(runtime, source.address);
  const index = new DataView(source.runtime.memory.buffer).getUint32((source.address >>> 0) + 8, true);
  return installCode(runtime, source.runtime.__indirect_function_table.get(index));
}

export function installCode(runtime, fn) {
  const table = runtime.__indirect_function_table, free = runtime['snail:gc/free-code']();
  const index = free || table.grow(1, fn);
  if (free) table.set(index, fn);
  return managedValue(runtime, runtime['snail:gc/code-new'](index, 0, 0));
}

const views = new WeakMap();
const rawViews = new WeakMap();
// A host may retain an exported function after its module is retired. Its
// module owner is then a host root, just as an ordinary returned value is.
const functionOwners = new WeakMap();
export function hostExports(exports, runtime = exports) {
  exports = rawViews.get(exports) ?? exports;
  runtime = rawViews.get(runtime) ?? runtime;
  runtime = exports['snail:gc/checkpoint'] ? exports : runtime;
  if (!runtime?.['snail:gc/checkpoint']) return exports;
  let byRuntime = views.get(exports);
  if (!byRuntime) views.set(exports, byRuntime = new WeakMap());
  if (!byRuntime.has(runtime)) {
    const owner = managedValue(runtime, exports['snail:gc/module-roots']?.value ?? 0);
    const view = Object.fromEntries(Object.entries(exports).map(([name, value]) =>
      [name, typeof value === 'function' && (!name.startsWith('snail:') || exports[`snail:abi/${name}`]) ?
        hostFunction(runtime, value, exports[`snail:abi/${name}`], owner) : value]));
    rawViews.set(view, exports);
    byRuntime.set(runtime, view);
  }
  return byRuntime.get(runtime);
}

function hostFunction(runtime, fn, describe, owner) {
  const wrapped = describedFunction(runtime, fn, describe);
  if (owner) functionOwners.set(wrapped, owner);
  return wrapped;
}

function describedFunction(runtime, fn, describe) {
  if (!describe) return (...args) => invoke(runtime, fn, ...args);
  const params = Array.from({length: fn.length}, (_, i) => describe(i)), result = describe(-1);
  return (...args) => {
    const raw = params.map((type, i) => type ? checkedPointer(runtime, args[i], type) : args[i]);
    const value = invoke(runtime, fn, ...raw);
    if (result && !runtime['snail:gc/host-check'](value, Number(result >> 32n), Number(result & 0xffffffffn))) {
      throw new TypeError('the host returned an incompatible managed value');
    }
    return result ? managedValue(runtime, value) : value;
  };
}

const values = new WeakMap(), handles = new WeakMap();
const released = new FinalizationRegistry(({runtime, root, address}) => {
  runtime['snail:gc/release-roots'](root);
  const cache = handles.get(runtime);
  if (!cache?.get(address)?.deref()) cache?.delete(address);
});

// Identity is stable while a host holds a value. The weak cache does not keep
// that value alive; its registered cell is released when the host collects it.
// Foreign callback adapters unwrap the same private record before returning to
// Wasm. Public calls accept opaque handles and validate their logical type.
export function managedValue(runtime, address) {
  runtime = rawViews.get(runtime) ?? runtime;
  if (!runtime?.['snail:gc/roots']) return address;
  if (!address) return null;
  address >>>= 0;
  let cache = handles.get(runtime);
  if (!cache) handles.set(runtime, cache = new Map());
  const existing = cache.get(address)?.deref();
  if (existing) return existing;
  const root = runtime['snail:gc/roots'](1);
  new DataView(runtime.memory.buffer).setUint32(root >>> 0, address, true);
  const value = Object.freeze({});
  values.set(value, {runtime, address});
  cache.set(address, new WeakRef(value));
  released.register(value, {runtime, root, address});
  return value;
}

function checkedPointer(runtime, value, type) {
  const flags = Number(type & 0xffffffffn), tag = Number(type >> 32n);
  const held = value == null ? {runtime, address: 0} : values.get(value);
  if (!held || held.runtime !== runtime || !runtime['snail:gc/host-check'](held.address, tag, flags)) {
    throw new TypeError('expected a compatible managed value from this runtime');
  }
  return held.address;
}

export function holdRoot(runtime, value) {
  const address = runtime?.['snail:gc/roots']?.(1);
  let live = address !== undefined;
  if (live) new DataView(runtime.memory.buffer).setUint32(address >>> 0, values.get(value)?.address ?? value ?? 0, true);
  return {release() {
    if (live) { live = false; runtime['snail:gc/release-roots'](address); }
  }};
}

export function instantiateManaged(module, imports, runtime) {
  const checkpoint = runtime?.['snail:gc/module-checkpoint']?.();
  let instance;
  const complete = foreignImports(module, imports, () => instance.exports, () => runtime ?? instance.exports);
  try { return instance = invoke(runtime, () => new WebAssembly.Instance(module, complete)); }
  catch (error) {
    if (checkpoint !== undefined) runtime['snail:gc/rollback-modules'](checkpoint);
    if (runtime?.['snail:gc/abi-error']?.()) {
      throw new WebAssembly.LinkError('incompatible Snail reference layout');
    }
    throw error;
  }
}

function foreignImports(module, imports, exports, runtime) {
  const descriptors = new Set(WebAssembly.Module.exports(module).map(entry => entry.name)), complete = {...imports};
  for (const {module: from, name, kind} of WebAssembly.Module.imports(module)) {
    const descriptor = `snail:foreign/${from}\0${name}`, fn = imports[from]?.[name];
    if (kind !== 'function' || !fn || !descriptors.has(descriptor)) continue;
    complete[from] = {...complete[from], [name]: (...args) => {
      const describe = exports()[descriptor], owner = runtime();
      const result = fn(...args.map((value, i) => describe(i) ? managedValue(owner, value) : value));
      const type = describe(-1);
      return type ? checkedPointer(owner, result, type) : result;
    }};
  }
  return complete;
}

const retired = new WeakSet();
export function retireProgram(program, kept) {
  for (const [name, instance] of program.linked) {
    if (kept?.linked.get(name) === instance || retired.has(instance)) continue;
    const root = instance.exports['snail:gc/module-roots']?.value;
    if (root) program.runtime.exports['snail:gc/release-roots'](root);
    retired.add(instance);
  }
}
