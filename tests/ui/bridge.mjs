// Attack presentation boundaries before any DOM can observe a malformed tree.
import assert from 'node:assert/strict';
import {createUiBridge} from '../../src/ui/bridge.mjs';
const manifest = {applications: [{owner: 'client', handlers: [
  {id: 'increment-v1', payload: []}, {id: 'amount-v1', payload: ['I32']}
]}, {owner: 'match', handlers: [{id: 'shared-amount-v1', payload: ['I32']}]}]};
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

start(); node(2, 'preview'); host.action(2, 0, 0, 0);
host.hover(0, 2, 1, 4, 0); host.hover(1, 2, 1, 0, 0); host.end();
assert.deepEqual(bridge.finish(tx, manifest).hover, {
  enter: {owner: 2, command: {handler: 'amount-v1', args: [4]}},
  leave: {owner: 2, command: {handler: 'amount-v1', args: [0]}}
});
start(); node(1, 'incomplete-hover'); host.hover(0, 2, 0, 0, 0); host.end();
assert.throws(() => bridge.finish(tx, manifest), /requires an endpoint/);
start(); node(1, 'invalid-hover'); host.hover(0, 2, 99, 0, 0); host.hover(1, 2, 1, 0, 0); host.end();
assert.throws(() => bridge.finish(tx, manifest), /invalid UI endpoint/);
start(); node(1, 'invalid-hover-field'); assert.throws(() => host.hover(2, 2, 0, 0, 0), /invalid UI hover field/);
console.log('ok - paired hover requests use the same manifest endpoint validation');

start(); node(6, 'dial'); text(1, '42'); text(2, 'Hub health'); host.property(3, 75); host.property(5, 100); host.end();
const dial = bridge.finish(tx, manifest);
assert.equal(dial.action, undefined); assert.equal(dial.text, '42'); assert.equal(dial.help, 'Hub health');
start(); node(6, 'invalid-dial'); host.property(3, 0); host.property(5, 0); host.end();
assert.throws(() => bridge.finish(tx, manifest), /invalid UI dial range/);
start(); node(6, 'missing-value'); host.property(5, 100); host.end();
assert.throws(() => bridge.finish(tx, manifest), /invalid UI dial range/);
console.log('ok - circular readouts need a meter range and carry no activation endpoint');

start(); node(5, 'root'); node(1, 'same'); host.end(); node(1, 'same'); host.end(); host.end();
assert.throws(() => bridge.finish(tx, manifest), /unique/);
start(); node(5, 'root'); assert.throws(() => bridge.finish(tx, manifest), /complete/);
start(); node(1, 'root'); host.text(1, -1, 2); host.text(1, 0, 65); host.end();
assert.throws(() => bridge.finish(tx, manifest), /incomplete UI text/);
start(); node(1, 'root'); host.text(1, -1, 1); assert.throws(() => host.text(1, 0, 0xd800), /text sequence/);
console.log('ok - duplicate identity, incomplete nesting/text and invalid Unicode reject the presentation');

start(); node(3, 'number'); host.action(2, 0, 0, 0); host.end();
assert.throws(() => bridge.finish(tx, manifest), /client endpoint with one I32 payload/);
start(); node(3, 'shared-number'); host.action(1, 0, 0, 0); host.end();
assert.throws(() => bridge.finish(tx, manifest), /client endpoint with one I32 payload/);
start(); node(2, 'shared-button'); host.action(1, 0, 5, 0); host.end();
assert.deepEqual(bridge.finish(tx, manifest).action, {owner: 1, command: {handler: 'shared-amount-v1', args: [5]}});
start(); node(2, 'button'); host.action(2, 99, 0, 0); host.end();
assert.throws(() => bridge.finish(tx, manifest), /invalid UI endpoint/);
tx = {readOnly: false}; assert.throws(() => host.begin(1, 0, 0, 0, 0), /presentation query/);
assert.throws(() => host.viewport(0), /presentation query/);
start(); bridge.resize(640, 480); assert.equal(host.viewport(0), 640); assert.equal(host.viewport(1), 480);
console.log('ok - number fields require client ownership; match buttons work; invalid endpoints, arity and non-presentation writes reject');
