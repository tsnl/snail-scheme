// Host implementation of ABI finalization for browsers and Node. Keep the
// returned imports alive with their Wasm instance. Held resource IDs must not
// retain the watched object, directly or through a rooted Scheme reference.
// Explicit close remains necessary for timely cleanup; shutdown need not run
// finalizers. The cleanup function must tolerate already-closed resources.

// ---- Finalization ----

// Numeric buffers belong to the common library. Ports belong to the selected
// provider; replacing that provider must not change numeric buffer ownership.
export function dropResource(exports, kind, id) {
  if (kind === 2) exports['snail:drop-array'](id);
  else if (kind === 1) exports['ports/drop-resource'](kind, id);
}

export function createFinalizers(cleanup) {
  const registry = new FinalizationRegistry(({ kind, id }) => cleanup(kind, id));
  return {
    register(object, kind, id) {
      registry.unregister(object);
      registry.register(object, { kind, id }, object);
    },
    unregister(object) {
      registry.unregister(object);
    },
  };
}

// ---- Identity hashing ----

// WasmGC references have stable JS identities even when the engine moves them.
// Weak keys and scalar values let hashed objects, including cycles, be collected.
// Keep one hasher alive for the instance: tables cache these hash values.
export function createIdentityHasher() {
  const identities = new WeakMap();
  let next = 0;
  return value => {
    if (value === null) return 0;
    if (typeof value === 'number') return Math.imul(value, 0x9e3779b1) & 0x3fffffff;
    let hash = identities.get(value);
    if (hash === undefined) {
      hash = next;
      next = (next + 1) & 0x3fffffff;
      identities.set(value, hash);
    }
    return hash;
  };
}
