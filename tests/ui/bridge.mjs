// Attack presentation boundaries before any DOM can observe a malformed tree.
import assert from 'node:assert/strict';
import {createUiBridge} from '../../src/ui/bridge.mjs';
const manifest = {applications: [{owner: 'client', handlers: [
  {id: 'increment-v1', payload: []}, {id: 'amount-v1', payload: ['I32']}
]}]};
let tx;
const bridge = createUiBridge(functions => functions, () => tx), host = bridge.provider;
function start() { tx = {readOnly: true}; }
function text(field, value) {
  const scalars = Array.from(value, character => character.codePointAt(0));
  host.text(field, -1, scalars.length); scalars.forEach((value, index) => host.text(field, index, value));
}
function node(kind, key) { host.begin(kind, 0, 0, 100, 40); text(0, key); }

start(); node(5, 'root'); node(2, 'button'); text(1, 'Increase'); host.action(2, 0, 0, 0); host.end(); host.end();
const tree = bridge.finish(tx, manifest);
assert.deepEqual(tree.children[0].action, {owner: 2, command: {handler: 'increment-v1', args: []}});
assert.equal(tree.children[0].text, 'Increase');
console.log('ok - copied requests become manifest endpoint identities');

start(); node(5, 'root'); node(1, 'same'); host.end(); node(1, 'same'); host.end(); host.end();
assert.throws(() => bridge.finish(tx, manifest), /unique/);
start(); node(5, 'root'); assert.throws(() => bridge.finish(tx, manifest), /complete/);
start(); node(1, 'root'); host.text(1, -1, 2); host.text(1, 0, 65); host.end();
assert.throws(() => bridge.finish(tx, manifest), /incomplete UI text/);
start(); node(1, 'root'); host.text(1, -1, 1); assert.throws(() => host.text(1, 0, 0xd800), /text sequence/);
console.log('ok - duplicate identity, incomplete nesting/text and invalid Unicode reject the presentation');

start(); node(3, 'number'); host.action(2, 0, 0, 0); host.end();
assert.throws(() => bridge.finish(tx, manifest), /number input payload/);
start(); node(2, 'button'); host.action(2, 99, 0, 0); host.end();
assert.throws(() => bridge.finish(tx, manifest), /invalid UI endpoint/);
tx = {readOnly: false}; assert.throws(() => host.begin(1, 0, 0, 0, 0), /presentation query/);
console.log('ok - invalid endpoints, input arity and writes outside presentation are rejected');
