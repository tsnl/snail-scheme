// Host implementation of AWI finalization for browsers and Node. Keep the
// returned imports alive with their Wasm instance. Held resource IDs must not
// retain the watched object, directly or through a rooted Scheme reference.
// Explicit close remains necessary for timely cleanup; shutdown need not run
// finalizers. The cleanup function must tolerate already-closed resources.

// ---- Finalization ----

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
