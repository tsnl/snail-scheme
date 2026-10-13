// Foreign aliases retain the owner; callback arrays carry evaluated arguments.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { createFinalizers, createIdentityHasher } from '../src/runtime/host.mjs';
import { createBuildEffects } from '../src/runtime/build.mjs';

const [filename] = process.argv.slice(2);
const wasi = new WASI({ version: 'preview1', args: [filename], env: process.env,
  preopens: { '.': process.cwd() }, returnOnExit: true });
const module = await WebAssembly.compile(await readFile(filename));
let instance, abi;
const node = { cwd: process.cwd(), exports: null };
const build = createBuildEffects(node);
const finalizers = createFinalizers((kind, id) => instance.exports['ports/drop-resource'](kind, id));

function ownedArguments(root, count) {
  assert.equal(abi.length(root), count);
  return Array.from({ length: count }, (_, index) => abi.at(root, index));
}

function exchange(root) {
  const arguments_ = ownedArguments(root, 3);
  const [vector, value, index] = arguments_;
  try {
    assert.equal(abi.kind(vector), 8);
    assert.equal(abi.is_kind(vector, 8), 1);
    const hash = abi.identity_hash(vector);
    abi.vector_set(vector, Number(abi.as_integer(index)), value);
    assert.equal(abi.identity_hash(vector), hash);
    return abi.retain(vector);
  } finally { arguments_.forEach(value => abi.release(value)); }
}

function envelope(root) {
  const [vector] = ownedArguments(root, 1);
  const values = abi.values(vector);
  try {
    const result = abi.vector_new(1);
    abi.vector_set(result, 0, values);
    return result;
  } finally { abi.release(values); abi.release(vector); }
}

function call(root) {
  const [procedure, arguments_] = ownedArguments(root, 2);
  try { return abi.call(procedure, arguments_); }
  finally { abi.release(arguments_); abi.release(procedure); }
}

function exchangePair(root) {
  const [pair, value] = ownedArguments(root, 2);
  try {
    assert.equal(abi.kind(pair), 7);
    const hash = abi.identity_hash(pair);
    abi.pair_set_car(pair, value);
    abi.pair_set_cdr(pair, pair);
    assert.equal(abi.identity_hash(pair), hash);
    return abi.retain(pair);
  } finally { abi.release(value); abi.release(pair); }
}

function checkRawPairCarriers() {
  const roots = [];
  const own = value => { roots.push(value); return value; };
  try {
    const backing = own(abi.vector_new(1));
    const first = own(abi.integer(2147483648n));
    abi.vector_set(backing, 0, first);
    const envelope = own(abi.values(backing));
    const pair = own(abi.pair(envelope, own(abi.atom(2))));
    const copied = own(abi.car(pair));
    assert.equal(abi.kind(copied), 15, 'car consumed a raw envelope');
    assert.equal(abi.identity_hash(copied), abi.identity_hash(envelope));
    const replacement = own(abi.integer(4294967296n));
    abi.vector_set(backing, 0, replacement);
    assert.equal(abi.as_integer(own(abi.at(copied, 0))), 4294967296n);
    abi.pair_set_cdr(pair, copied);
    assert.equal(abi.kind(own(abi.cdr(pair))), 15, 'pair write consumed a raw envelope');
  } finally { roots.reverse().forEach(value => abi.release(value)); }
}

const imports = { ...wasi.getImportObject(), 'snail.node': build.imports,
  'snail.test': { 'snail:container-exchange!': exchange, 'snail:container-envelope': envelope,
    'snail:container-call': call, 'snail:container-pair-exchange!': exchangePair },
  'snail.host': { 'register-finalizer': finalizers.register,
    'hash-identity': createIdentityHasher(), 'unregister-finalizer': finalizers.unregister } };
instance = await WebAssembly.instantiate(module, imports);
abi = node.exports = instance.exports;
process.exitCode = wasi.start(instance);
checkRawPairCarriers();
assert.equal(abi.abi_live_roots.value, 3, 'foreign container probes leaked roots');
