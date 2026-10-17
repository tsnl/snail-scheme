import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/compiler/execute.mjs';
const root = resolve(process.argv[2] ?? 'build/ui-tests');
const instance = instantiate(loadWasm(readFileSync(join(root, 'layout.wasm'))));
try { assert.equal(invokeEntry(instance, []), 1); } finally { closeInstance(instance); }
console.log('ok - linked Wasm assigns fixed/grow rectangles and exhausted space');
const app = join(root, 'lab/solo'), manifest = JSON.parse(readFileSync(join(app, 'manifest.json')));
const bytes = readFileSync(join(app, manifest.module)), runtime = new ReducerRuntime();
function find(node, key) { return node.key === key ? node : node.children.map(child => find(child, key)).find(Boolean); }
try {
  await runtime.replace(runtime.prepare(bytes, manifest)); await runtime.initialize(1); await runtime.initialize(2);
  const before = runtime.snapshot(2), ui = runtime.view().ui, action = find(ui, 'more').action;
  assert.ok(Object.isFrozen(ui) && Object.isFrozen(action.command));
  await runtime.dispatch(action.owner, action.command);
  assert.equal(runtime.view().label, 'Value 11'); assert.notDeepEqual(runtime.snapshot(2), before);
  const retained = runtime.snapshot(2);
  await runtime.replace(runtime.prepare(bytes, manifest));
  assert.deepEqual(runtime.snapshot(2), retained); assert.equal(find(runtime.view().ui, 'more').action.command.handler, action.command.handler);
  assert.equal(find(runtime.view().ui, 'amount').properties[3], 11);
  console.log('ok - actual UI Wasm emits immutable typed requests and survives compatible replacement');
} finally { await runtime.close(); }
