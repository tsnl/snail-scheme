// A program owns one memory and one function table. JavaScript holds a guest
// value through a registered root. Only this module can recover the address,
// and only for the instance that allocated it.
const handles = new WeakMap();
const rawInstances = new WeakMap();
const caches = new WeakMap();
// A live handle keeps its heap alive through handles. A finalizer holding
// that heap strongly would keep host callbacks and their handles alive too.
const released = new FinalizationRegistry(({owner, root, pointer}) => {
  const heap = owner.deref();
  if (!heap) return;
  heap['snail:gc/release-roots'](root);
  const cache = caches.get(heap).handles;
  if (!cache.get(pointer)?.deref()) cache.delete(pointer);
});

function hold(heap, address) {
  const pointer = address >>> 0;
  if (!pointer) return null;
  const cache = caches.get(heap);
  const found = cache.handles.get(pointer)?.deref();
  if (found) return found;
  const root = heap['snail:gc/roots'](1);
  new DataView(heap.memory.buffer).setUint32(root >>> 0, pointer, true);
  const handle = Object.freeze(Object.create(null));
  handles.set(handle, {heap, pointer});
  cache.handles.set(pointer, new WeakRef(handle));
  released.register(handle, {owner: cache.owner, root, pointer});
  return handle;
}

function address(heap, handle, type) {
  const held = handle == null ? {heap, pointer: 0} : handles.get(handle);
  if (!held || held.heap !== heap ||
      !heap['snail:gc/host-check'](held.pointer, Number(type >> 32n), Number(type & 0xffffffffn))) {
    throw new TypeError('expected a compatible Snail value from this instance');
  }
  return held.pointer;
}

// A trap abandons the Wasm activation but its shadow frame is in linear
// memory. Nested host callbacks restore to their own entry depth.
function invoke(heap, fn, args) {
  const depth = heap['snail:gc/checkpoint']();
  try {
    const result = fn(...args);
    drainCode(heap);
    return result;
  } finally { heap['snail:gc/restore'](depth); }
}

function publicFunction(heap, fn, describe) {
  const types = Array.from({length: fn.length}, (_, i) => describe?.(i) ?? 0n);
  const result = describe?.(-1) ?? 0n;
  return (...args) => {
    const raw = types.map((type, i) => type ? address(heap, args[i], type) : args[i]);
    const value = invoke(heap, fn, raw);
    return result ? hold(heap, value) : value;
  };
}

// A foreign funcref acquires an entry in the receiving program's own table.
// Collection of its descriptor makes that entry reusable.
function importCode(heap, fn) {
  const cache = caches.get(heap);
  cache.foreignCode = true;
  drainCode(heap);
  const table = heap['snail:table'], reusable = cache.free.pop();
  const index = reusable || table.grow(1, fn);
  if (reusable) table.set(index, fn);
  return heap['snail:gc/code-new'](index);
}

function drainCode(heap) {
  const cache = caches.get(heap);
  if (!cache.foreignCode) return;
  let index;
  while ((index = heap['snail:gc/dead-code']())) {
    heap['snail:table'].set(index, null);
    cache.free.push(index);
  }
}

function hostImports(module, imports, current) {
  const names = new Set(WebAssembly.Module.exports(module).map(entry => entry.name));
  const complete = {...imports};
  for (const {module: from, name, kind} of WebAssembly.Module.imports(module)) {
    const descriptor = 'snail:foreign/' + from + '\0' + name;
    const fn = imports[from]?.[name];
    if (!fn || kind !== 'function' || !names.has(descriptor)) continue;
    complete[from] = {...complete[from], [name]: (...args) => {
      const heap = current(), describe = heap[descriptor];
      const value = fn(...args.map((arg, i) => describe(i) ? hold(heap, arg) : arg));
      const result = describe(-1);
      if ((result & 4n) && typeof value === 'function') return importCode(heap, value);
      return result ? address(heap, value, result) : value;
    }};
  }
  return complete;
}

// Page startup can instantiate large modules off the browser's main thread.
export async function instantiateProgram(module, imports) {
  const instance = await WebAssembly.instantiate(module, hostImports(module, imports, () => rawInstances.get(instance)));
  return exposeInstance(instance);
}

// The guest's synchronous link operation returns the new instance handle in
// the same Wasm call. It follows the same ABI as asynchronous page startup.
export function instantiateProgramSync(module, imports) {
  const instance = new WebAssembly.Instance(module, hostImports(module, imports, () => rawInstances.get(instance)));
  return exposeInstance(instance);
}

function exposeInstance(instance) {
  const heap = instance.exports;
  if (!heap['snail:gc/checkpoint']) return instance;
  rawInstances.set(instance, heap);
  caches.set(heap, {owner: new WeakRef(heap), handles: new Map(), free: [], foreignCode: false});
  const api = Object.create(null);
  for (const [name, entry] of Object.entries(heap)) {
    if (name.startsWith('snail:')) continue;
    const global = heap['snail:global/' + name];
    if (global) {
      const type = global();
      api[name] = Object.freeze({
        get value() { return hold(heap, new DataView(heap.memory.buffer).getUint32(entry.value >>> 0, true)); },
        set value(handle) {
          new DataView(heap.memory.buffer).setUint32(entry.value >>> 0, address(heap, handle, type), true);
        },
      });
    } else {
      api[name] = typeof entry === 'function' ? publicFunction(heap, entry, heap['snail:abi/' + name]) : entry;
    }
  }
  Object.defineProperty(instance, 'exports', {value: Object.freeze(api)});
  return instance;
}

// An untyped Wasm funcref may cross instances when it has a scalar ABI.
// A managed argument would be an address in the wrong memory. Host calls
// through the public view still check the instance and the logical type.
export function exportedCode(instance, name, caller) {
  const raw = rawInstances.get(instance);
  if (!raw || instance === caller) return (raw ?? instance.exports)[name];
  const describe = raw['snail:abi/' + name], code = raw[name];
  if (describe && (describe(-1) || Array.from({length: code.length}, (_, i) => describe(i)).some(Boolean))) {
    throw new TypeError('a function carrying Snail values cannot cross instance memories');
  }
  return code;
}
