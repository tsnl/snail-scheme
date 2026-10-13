// Execute real tensor primitives and collect their WasmGC owners independently
// of the selected port provider. Cleanup observations contain scalar IDs only.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { createFinalizers, createIdentityHasher, dropResource } from '../src/runtime/host.mjs';
import { createBuildEffects } from '../src/runtime/build.mjs';

// ---- Linked module and selected cleanup provider ----

const [filename] = process.argv.slice(2);
const wasi = new WASI({ version: 'preview1', args: [filename], env: process.env,
  preopens: { '.': process.cwd() }, returnOnExit: true });
let exports;
const arrays = new Set(), ports = new Set(), portNotices = new Set();
const testPort = 1048576;
const finalizers = createFinalizers((kind, id) => dropResource(exports, kind, id));
const node = { cwd: process.cwd(), exports: null };
const build = createBuildEffects(node);
const imports = { ...wasi.getImportObject(), 'snail.node': build.imports, 'snail.host': {
  'register-finalizer': finalizers.register, 'unregister-finalizer': finalizers.unregister,
  'hash-identity': createIdentityHasher(),
} };
const { instance } = await WebAssembly.instantiate(await readFile(filename), imports);
const abi = instance.exports;
exports = { ...abi,
  'snail:drop-array'(id) { abi['snail:drop-array'](id); arrays.add(id); },
  'ports/drop-resource'(kind, id) {
    assert.equal(kind, 1, 'the selected port provider must not own numeric arrays');
    portNotices.add(id);
    if (id === testPort) ports.delete(id);
    else abi['ports/drop-resource'](kind, id);
  },
};
node.exports = abi;
assert.equal(wasi.start(instance), 0);
const baseline = abi.abi_live_roots.value;

// ---- Owned ABI arguments ----

function invoke(name, values) {
  const args = abi.vector_new(values.length);
  try {
    values.forEach((value, i) => abi.vector_set(args, i, value));
    return abi[`snail:%iverson-${name}`](args);
  } finally { abi.release(args); }
}

function dimensions(values) {
  const result = abi.vector_new(values.length);
  values.forEach((value, i) => {
    const root = abi.integer(BigInt(value));
    abi.vector_set(result, i, root);
    abi.release(root);
  });
  return result;
}

function iota(count) {
  const dtype = abi.integer(1n), length = abi.integer(BigInt(count));
  try { return invoke('iota', [dtype, length]); }
  finally { abi.release(dtype); abi.release(length); }
}

function element(array, index) {
  const offset = abi.integer(BigInt(index));
  const result = invoke('ref', [array, offset]);
  try { return abi.as_real(result); }
  finally { abi.release(result); abi.release(offset); }
}

async function collected(notices, id) {
  for (let i = 0; i < 100 && !notices.has(id); i++) {
    global.gc();
    await new Promise(setImmediate);
  }
  assert(notices.has(id), `resource ${id} must be collected`);
}

// ---- Shared buffers and provider isolation ----

const source = iota(6), shape = dimensions([2, 3]);
const view = invoke('reshape', [shape, source]);
const sourceId = abi.extension_id(source), viewId = abi.extension_id(view);
assert.notEqual(sourceId, viewId);
abi.release(shape);
abi.release(source);
await collected(arrays, sourceId);
assert(!arrays.has(viewId), 'the retained view keeps its own wrapper alive');
assert.equal(element(view, 5), 5);
abi.release(view);
await collected(arrays, viewId);

const next = iota(3), nextId = abi.extension_id(next);
assert(nextId > viewId, 'resource IDs are fresh');
dropResource(exports, 2, sourceId);
dropResource(exports, 2, sourceId);
assert.equal(element(next, 2), 2, 'late cleanup cannot release another buffer');
abi.release(next);
await collected(arrays, nextId);

ports.add(testPort);
const port = abi.extension(1, testPort);
abi.release(port);
await collected(portNotices, testPort);
assert(!ports.has(testPort), 'port cleanup reaches the selected provider');
assert.equal(abi.abi_live_roots.value, baseline, 'temporary ABI roots are released');
console.log('Iverson buffer ownership and cleanup routing checks passed');
