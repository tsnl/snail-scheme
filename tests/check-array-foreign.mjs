// Each failing case gets a fresh instance. The exit hook checks that a rejected
// operation left the array unchanged; execution never resumes after that exit.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { createFinalizers, createIdentityHasher } from '../src/runtime/host.mjs';
import { createBuildEffects } from '../src/runtime/build.mjs';

const [filename, mode = 'pass'] = process.argv.slice(2);
const wasi = new WASI({ version: 'preview1', args: [filename], env: process.env,
  preopens: { '.': process.cwd() }, returnOnExit: true });
let instance, abi, inspectFailure = () => {}, diagnostic = '';
const node = { cwd: process.cwd(), exports: null };
const build = createBuildEffects(node);
const finalizers = createFinalizers((kind, id) => instance.exports['ports/drop-resource'](kind, id));
class ExpectedExit extends Error {}

function boundary(root) {
  const roots = [];
  const own = value => { roots.push(value); return value; };
  const args = values => {
    const result = own(abi.vector_new(values.length));
    values.forEach((value, index) => abi.vector_set(result, index, value));
    return result;
  };
  const invoke = (procedure, values) => own(abi.call(procedure, args(values)));
  const [numeric, boxed, realStorage, anyStorage, read, append, arrayCopy, copy] =
    Array.from({ length: 8 }, (_, index) => own(abi.at(root, index)));
  const real = (object, index) => abi.as_real(own(abi.at(object, index)));
  inspectFailure = () => {
    assert.equal(real(numeric, 0), 1.25, 'failed operation partially wrote first element');
    assert.equal(real(numeric, 1), 1.25, 'failed operation wrote final element');
  };
  try {
    assert.equal(abi.kind(realStorage), 18);
    assert.equal(abi.is_kind(realStorage, 18), 1);
    assert.equal(abi.is_kind(realStorage, 8), 0);
    assert.equal(abi.kind(numeric), 8);
    const backing = args([own(abi.real(2.5))]);
    const envelope = own(abi.values(backing));
    abi.vector_set(boxed, 0, envelope);
    const index = own(abi.integer(0n));
    if (mode === 'write') abi.vector_set(numeric, 0, own(abi.atom(0)));
    if (mode === 'envelope-write') abi.vector_set(numeric, 0, envelope);
    if (mode === 'late-copy') invoke(copy, [numeric, args([own(abi.real(4.5)), own(abi.atom(0))])]);
    if (mode === 'multiple-ref') {
      abi.vector_set(boxed, 0, own(abi.values(args([own(abi.real(1.0)), own(abi.real(2.0))]))));
      invoke(read, [boxed, index]);
    }
    if (mode === 'witness-mismatch') invoke(append, [realStorage, boxed, boxed]);
    if (mode === 'empty-copy') invoke(arrayCopy, [numeric, index, boxed, index, index]);
    assert.equal(mode, 'pass', 'expected operation to reject');
    const raw = own(abi.at(boxed, 0));
    assert.equal(abi.kind(raw), 15, 'Eqref storage consumed a raw envelope');
    assert.equal(abi.identity_hash(raw), abi.identity_hash(envelope));
    assert.equal(abi.as_real(invoke(read, [boxed, index])), 2.5);
    const result = invoke(append, [anyStorage, boxed, boxed]);
    const copied = own(abi.at(result, 0));
    assert.equal(abi.kind(copied), 15, 'array.append consumed an element');
    assert.equal(abi.identity_hash(copied), abi.identity_hash(envelope));
    abi.vector_set(backing, 0, own(abi.real(3.75)));
    assert.equal(abi.as_real(invoke(read, [result, index])), 3.75);
    const inner = own(abi.values(args([own(abi.real(9.0))])));
    const outer = own(abi.values(args([inner])));
    abi.vector_set(boxed, 0, outer);
    assert.equal(abi.kind(invoke(read, [boxed, index])), 15, 'array.ref consumed more than one envelope');
    for (const contents of [[], [own(abi.real(1.0)), own(abi.real(2.0))], [inner]]) {
      const carrier = own(abi.values(args(contents)));
      abi.vector_set(boxed, 0, carrier);
      const appended = invoke(append, [anyStorage, boxed, boxed]);
      const item = own(abi.at(appended, 0));
      assert.equal(abi.kind(item), 15, 'array.append inspected its raw initialization seed');
      assert.equal(abi.identity_hash(item), abi.identity_hash(carrier));
    }
    invoke(copy, [numeric, args([])]); // An ordinary empty copy has no values to reject.
    const hash = abi.identity_hash(numeric);
    invoke(copy, [numeric, args([own(abi.real(4.5)), own(abi.real(5.5))])]);
    assert.equal(real(numeric, 0), 4.5);
    assert.equal(real(numeric, 1), 5.5);
    assert.equal(abi.identity_hash(numeric), hash);
    return abi.atom(3);
  } finally { roots.reverse().forEach(value => abi.release(value)); }
}

const wasiImports = wasi.getImportObject();
const originalWrite = wasiImports.wasi_snapshot_preview1.fd_write;
wasiImports.wasi_snapshot_preview1.fd_write = (fd, vectors, count, written) => {
  if (fd !== 2 || mode === 'pass') return originalWrite(fd, vectors, count, written);
  const view = new DataView(abi.memory.buffer);
  let size = 0;
  for (let index = 0; index < count; index++) {
    const offset = view.getUint32(vectors + index * 8, true);
    const length = view.getUint32(vectors + index * 8 + 4, true);
    diagnostic += new TextDecoder().decode(new Uint8Array(abi.memory.buffer, offset, length));
    size += length;
  }
  view.setUint32(written, size, true);
  return 0;
};
if (mode !== 'pass') wasiImports.wasi_snapshot_preview1.proc_exit = status => {
  assert.equal(status, 1);
  assert.equal(abi.error_code.value, mode === 'multiple-ref' ? 5 : 8);
  inspectFailure();
  throw new ExpectedExit();
};
instance = await WebAssembly.instantiate(await WebAssembly.compile(await readFile(filename)), {
  ...wasiImports, 'snail.node': build.imports, 'snail.test': { 'snail:array-boundaries': boundary },
  'snail.host': { 'register-finalizer': finalizers.register,
    'hash-identity': createIdentityHasher(), 'unregister-finalizer': finalizers.unregister },
});
abi = node.exports = instance.exports;
if (mode === 'pass') {
  assert.equal(wasi.start(instance), 0);
  assert.equal(abi.abi_live_roots.value, 3, 'successful foreign operations leaked roots');
} else {
  assert.throws(() => wasi.start(instance), ExpectedExit);
  assert.match(diagnostic, mode === 'multiple-ref' ? /single value/ : /incorrect value type/);
  console.log(`passed foreign array rejection ${mode}`);
}
