import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {loadWasm} from '../../src/lofi/compiler/execute.mjs';
import {invokeLibraryGenerator, libraryTransferJSON, openLibraryBuilder} from '../../src/lofi/compiler/builder.mjs';

const directory = process.argv[2];
const code = loadWasm(readFileSync(join(directory, 'complete-producer.wasm')));
const packet = JSON.parse(libraryTransferJSON(invokeLibraryGenerator(code)));
const text = packet.nodes.find(node => node[0] === 'string-literal');
assert.equal(packet.nodes[text[1]][1], 'A🙂\0Z');
writeFileSync(join(directory, 'complete.json'), JSON.stringify(packet));
const binding = (nodes, name) => nodes.findIndex(node => node[0] === 'binding' && nodes[node[2]][1] === name);
const first = (nodes, kind) => nodes.find(node => node[0] === kind);
function shareLocalOutsideScope(nodes, before) {
  const local = binding(nodes, 'shadow');
  const expression = nodes.findIndex(node => node[0] === 'reference' && nodes[node[1]][0] === 'local-reference' && nodes[node[1]][1] === local);
  const statement = nodes.length, root = nodes[packet.root], nil = nodes.findIndex(node => node[0] === 'nil');
  nodes.push(['expression-statement', expression]);
  if (before) { nodes.push(['cons', statement, root[5]]); root[5] = statement + 1; }
  else {
    let tail = nodes[root[5]];
    while (nodes[tail[2]][0] !== 'nil') tail = nodes[tail[2]];
    nodes.push(['cons', statement, nil]); tail[2] = statement + 1;
  }
}
const mutations = [
  ['future-let', nodes => {
    const shadows = nodes.flatMap((node, id) => node[0] === 'binding' && nodes[node[2]][1] === 'shadow' ? [id] : []);
    const reference = nodes.find(node => node[0] === 'local-reference' && node[1] === shadows[0]);
    reference[1] = shadows[1];
  }],
  ['variable-scope', nodes => { first(nodes, 'variable-id')[1] = nodes.findIndex(node => node[0] === 'scope'); }],
  ['escaped-variable', nodes => {
    const definition = nodes.find(node => node[0] === 'definition' && node[1] === binding(nodes, 'text'));
    definition[2] = nodes.findIndex(node => node[0] === 'variable-type');
  }],
  ['block-parent', nodes => {
    const block = first(nodes, 'block');
    nodes[block[1]][1] = nodes.findIndex(node => node[0] === 'scope');
  }],
  ['static-value', nodes => {
    const literal = nodes.findIndex(node => node[0] === 'literal' && node[1] === 'I32' && node[2] === '5');
    const span = nodes[literal][3], reference = nodes.length;
    nodes.push(['local-reference', binding(nodes, 'Box'), span]);
    nodes[literal] = ['reference', reference];
  }],
  ['byte-range', nodes => { first(nodes, 'byte')[1] = 256; }],
  ['duplicate-static-binding', nodes => { first(nodes, 'class-method')[1] = binding(nodes, 'box'); }],
  ['forged-evidence', nodes => { first(nodes, 'scalar-type')[1] = 'CheckedI32'; }],
  ['surrogate-text', nodes => { nodes[first(nodes, 'string-literal')[1]][1] = '\ud800'; }],
  ['reserved-binding', nodes => { nodes[nodes[binding(nodes, 'text')][2]][1] = 'def'; }],
  ['reserved-variable', nodes => { nodes[first(nodes, 'variable-id')[2]][1] = 'I32'; }],
  ['duplicate-variable-name', nodes => {
    const signature = first(nodes, 'all-signature'), variables = nodes[signature[2]];
    const variable = [...nodes[variables[1]]], id = nodes.length;
    nodes.push(variable, ['cons', id, signature[2]]);
    signature[2] = id + 1;
  }],
  ['class-as-type', nodes => {
    first(nodes, 'nominal-type')[1] = first(nodes, 'constraint')[1];
  }],
  ['value-as-constraint', nodes => {
    const constraint = first(nodes, 'constraint'), reference = nodes.length;
    nodes.push(['local-reference', binding(nodes, 'identity'), constraint[3]]);
    constraint[1] = reference;
  }],
  ['shared-reference-first', nodes => shareLocalOutsideScope(nodes, true)],
  ['shared-reference-last', nodes => shareLocalOutsideScope(nodes, false)],
];
for (const [name, mutate] of mutations) {
  const copy = structuredClone(packet);
  mutate(copy.nodes);
  writeFileSync(join(directory, `bad-${name}.json`), JSON.stringify(copy));
}

// Inspection uses the same arena ownership and category checks as construction.
const arena = openLibraryBuilder(), other = openLibraryBuilder();
const api = arena.provider.exports, foreign = other.provider.exports['name-empty']();
for (const kind of ['kind-type', 'kind-constraint', 'kind-function', 'kind-evidence', 'kind-annotation']) {
  assert.equal(api[kind], undefined);
  const removed = structuredClone(packet);
  removed.nodes.push([kind]);
  assert.throws(() => arena.receive(JSON.stringify(removed)), /unsupported transfer node/);
  writeFileSync(join(directory, `bad-${kind}.json`), JSON.stringify(removed));
}
const name = api['name-character'](api['name-empty'](), 0x1f642);
assert.equal(api['name-length'](name), 1n);
assert.equal(api['name-ref'](name, 0n), 0x1f642);
assert.throws(() => api['name-ref'](name, 1n), /index out of range/);
assert.throws(() => api['inspect-field'](name, 0), /reference field/);
assert.throws(() => api['inspect-tag'](foreign), /invocation handle/);
assert.throws(() => api['byte'](256n), /0..255/);
assert.throws(() => api['list-type'](name), /handle kind/);
const span = api.span(name, 1, 1), literal = api['literal-F64'](-0, span);
assert(Object.is(api['inspect-literal-F64'](literal), -0));
assert.throws(() => api['inspect-literal-I32'](literal), /wrong scalar type/);
arena.close(); other.close();
assert.throws(() => api['inspect-tag'](name), /closed/);
console.log('PASS complete compiled producer, inspection copies and untrusted transfer fixtures');
