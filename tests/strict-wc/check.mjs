import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { createFinalizers, createIdentityHasher } from '../../src/runtime/host.mjs';
import { createBuildEffects } from '../../src/runtime/build.mjs';

// ---- The same linked instance used for timing ----

const [filename, mode = 'success', corpus, mismatch] = process.argv.slice(2);
const wasi = new WASI({ version: 'preview1', args: [filename],
  env: { ...process.env, SNAIL_CWD: process.cwd() }, preopens: { '/': '/' } });
let instance;
const finalizers = createFinalizers((kind, id) => instance.exports['ports/drop-resource'](kind, id));
const node = { cwd: process.cwd(), exports: null }, build = createBuildEffects(node);
instance = await WebAssembly.instantiate(await WebAssembly.compile(await readFile(filename)),
  { ...wasi.getImportObject(), 'snail.node': build.imports, 'snail.host': {
    'register-finalizer': finalizers.register, 'unregister-finalizer': finalizers.unregister,
    'hash-identity': createIdentityHasher(),
  } });
node.exports = instance.exports;
// The driver supplies count=0 and expected=#f. This initializes the original
// Scheme globals through _start, without replacing any measured instructions.
wasi.start(instance);
const abi = instance.exports;

// ---- Owned ports and list extraction ----

function stringRoot(text) {
  const characters = [...text], root = abi.string_new(characters.length);
  characters.forEach((character, index) => abi.string_set(root, index, character.codePointAt(0)));
  return root;
}

function portCall(name, roots) {
  const arguments_ = abi.vector_new(roots.length);
  roots.forEach((root, index) => abi.vector_set(arguments_, index, root));
  try { return abi[name](arguments_); }
  finally { abi.release(arguments_); }
}

function openInput(text) {
  const source = stringRoot(text);
  try { return portCall('ports/open-input-string', [source]); }
  finally { abi.release(source); }
}

function openFile(path) {
  const name = stringRoot(path);
  try { return portCall('filesystem/open-input-file', [name]); }
  finally { abi.release(name); }
}

function ownedInteger(root) {
  try { return abi.as_integer(root); }
  finally { abi.release(root); }
}

// Consumes the result root. Each cdr gets its own root before the previous
// root is released; temporary car roots never outlive their integer reads.
function counts(root) {
  const values = [];
  try {
    for (let index = 0; index < 3; index++) {
      values.push(ownedInteger(abi.car(root)));
      const next = abi.cdr(root);
      abi.release(root); root = next;
    }
    assert.equal(abi.atom_value(root), 2, 'wc must return a proper three-element list');
    return values;
  } finally { abi.release(root); }
}

function checkCount(port, expected) {
  const live = abi.abi_live_roots.value;
  const actual = counts(abi['test/wcport'](port));
  assert.deepEqual(actual, expected.map(BigInt));
  assert.equal(abi.abi_live_roots.value, live, 'wcport retained temporary roots');
  return actual.map(String);
}

function closeAndRelease(port) {
  assert.equal(abi['snail:io/close'](abi.extension_id(port)), 0);
  abi.release(port);
}

function checkString(text, expected) {
  const port = openInput(text);
  checkCount(port, expected);
  checkCount(port, [0, 0, 0]); // Repeated EOF must not preserve the previous result.
  closeAndRelease(port);
}

async function checkOwner() {
  const port = openInput('λ😀'), id = abi.extension_id(port);
  for (let i = 0; i < 10000; i++) abi.release(abi.string_new(32));
  globalThis.gc();
  await new Promise(resolve => setImmediate(resolve));
  checkCount(port, [0, 1, 2]);
  closeAndRelease(port);
  const fresh = openInput('Z');
  assert.ok(abi.extension_id(fresh) > id, 'resource IDs must never be reused');
  abi['ports/drop-resource'](1, id);
  checkCount(fresh, [0, 1, 1]);
  closeAndRelease(fresh);
}

function fatalCount(port) {
  try { abi['test/wcport'](port); }
  catch (error) {
    // Direct calls after wasi.start throw Node's internal exit token.
    if (error instanceof Error) throw error;
    process.exit(1);
  }
  throw new Error('fatal wc error returned partial counts');
}

// ---- Tests ----

if (mode === 'closed') {
  const port = openInput('A');
  assert.equal(abi['snail:io/close'](abi.extension_id(port)), 0);
  fatalCount(port);
}
if (mode === 'wrong-direction') fatalCount(portCall('ports/open-output-string', []));
if (mode === 'invalid' || mode === 'truncated') {
  const bytes = mode === 'invalid' ? [65, 255] : [65, 240, 159];
  await writeFile('malformed.txt', new Uint8Array(bytes));
  fatalCount(openFile(`${process.cwd()}/malformed.txt`));
}
if (mode === 'success') {
  for (const [text, expected] of [
    ['', [0, 0, 0]], ['A B\n', [1, 2, 4]], [' \n  \n', [2, 0, 5]],
    ['a\n\nb c ', [2, 3, 7]], ['\t\r', [0, 1, 2]], ['λ😀 \nZ', [1, 2, 5]],
    ['\0\u{10ffff}\u00a0\t\r', [0, 1, 5]],
  ]) checkString(text, expected);
  const large = [2147483648n, 1099511627776n, 9223372036854775807n];
  assert.deepEqual(counts(abi['test/count-result'](...large)), large);
  await writeFile('unicode.txt', `${'a'.repeat(8191)}😀 B\n`);
  const unicode = openFile(`${process.cwd()}/unicode.txt`);
  checkCount(unicode, [1, 2, 8195]); closeAndRelease(unicode);
  await checkOwner();
  const original = openFile(corpus);
  const result = checkCount(original, [31102, 851820, 4460056]);
  closeAndRelease(original);
  const module = await WebAssembly.compile(await readFile(mismatch));
  await assert.rejects(WebAssembly.instantiate(module,
    { io: { read: abi['snail:io/read-code'] } }), WebAssembly.LinkError);
  assert.equal(abi.abi_live_roots.value, 3, 'only current ports may retain roots');
  console.log(`WC scalar checks passed: (${result.join(' ')})`);
}
