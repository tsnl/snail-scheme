// A compiled lexical request crosses the real Wasm import into the UI parser.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createUiBridge} from '../../src/ui/bridge.mjs';
const tx = {readOnly: true}, bridge = createUiBridge(functions => functions, () => tx);
const {instance} = await WebAssembly.instantiate(readFileSync(process.argv[2]), {'snail.ui': bridge.provider});
instance.exports.main(); assert.equal(instance.exports.entry(), 1);
const manifest = {applications: [{owner: 'client', handlers: [
  {id: 'choose-v1', payload: []}, {id: 'preview-v1', payload: ['I32']}
]}]};
const [choice, dial] = bridge.finish(tx, manifest).children;
assert.equal(choice.key, 'choice'); assert.deepEqual(choice.rect, [12, 24, 120, 44]);
assert.deepEqual(choice.action, {owner: 2, command: {handler: 'choose-v1', args: []}});
assert.deepEqual(choice.hover.enter, {owner: 2, command: {handler: 'preview-v1', args: [3]}});
assert.deepEqual(choice.hover.leave, {owner: 2, command: {handler: 'preview-v1', args: [0]}});
console.log('ok - linked Wasm carries typed hover and click requests through layout and the browser bridge');
assert.equal(dial.kind, 6); assert.equal(dial.text, '42'); assert.equal(dial.help, 'Ore 42; hub health');
assert.deepEqual(dial.rect, [150, 24, 72, 72]); assert.equal(dial.action, undefined);
assert.deepEqual([dial.properties[0], dial.properties[3], dial.properties[5]], [2, 75, 100]);
console.log('ok - linked Wasm carries a circular readout with separate center text and meter range');
