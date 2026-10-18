// Execute real Scheme picking and contextual transitions without a browser.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony, client} from '../applications/colony-state.mjs';
const output = process.argv[2], manifest = JSON.parse(readFileSync(join(output, 'manifest.json')));
const bytes = readFileSync(join(output, manifest.module)), runtime = new ReducerRuntime();
await runtime.replace(runtime.prepare(bytes, manifest)); await runtime.initialize(1); await runtime.initialize(2);
const world = () => colony(runtime.snapshot(1)), local = () => client(runtime.snapshot(2));
const geometry = scene => ({vertices: scene.batches.reduce((total, batch) => total + batch.vertices.length, 0),
  indices: scene.batches.reduce((total, batch) => total + batch.indices.length, 0)});
async function command(binding, args = []) {
  const result = await runtime.dispatch(2, runtime.command('client', binding, args));
  for (const effect of result.effects) if (effect.kind === 'send') await runtime.dispatch(1, runtime.effectCommand(effect));
}
async function advance(ticks) {
  for (let i = 0; i < ticks; i++) await runtime.dispatch(1, runtime.command('match', 'advance'));
}
function project(x, y, z = 0) {
  const m = runtime.view().scene.uniforms, state = local();
  return [Math.round((m[0] * x - m[4] * y + m[8] * z + m[12] + 1) * state.width / 2),
    Math.round((1 - (m[1] * x - m[5] * y + m[9] * z + m[13])) * state.height / 2)];
}
const point = (x, y, z) => command('move', project(x, y, z));
function node(key, value = runtime.view().ui) {
  if (value.key === key) return value;
  for (const child of value.children) { const found = node(key, child); if (found) return found; }
}
function placed(key, value = runtime.view().ui, x = 0, y = 0) {
  const left = x + value.rect[0], top = y + value.rect[1];
  if (value.key === key) return {node: value, left, top, right: left + value.rect[2], bottom: top + value.rect[3]};
  for (const child of value.children) { const found = placed(key, child, left, top); if (found) return found; }
}
try {
  const snapshot = runtime.snapshot(1); const frame = runtime.view();
  assert.ok(geometry(frame.scene).vertices > 1000); assert.ok(frame.ui); assert.deepEqual(runtime.snapshot(1), snapshot);
  for (const direction of [[1,0],[-1,0],[0,1],[0,-1],[1,-1]]) {
    await command('home'); const retained = runtime.view().scene, before = project(8,22); await command('pan', direction);
    assert.ok(runtime.view().scene.batches.every((batch, index) => batch === retained.batches[index]));
    const after = project(8,22), dx = after[0] - before[0], dy = after[1] - before[1];
    assert.ok(dx * direction[0] + dy * direction[1] < -20);
    assert.ok(Math.abs(dx * direction[1] - dy * direction[0]) <= 1);
    await command('pan', direction.map(value => value * 100)); const bounded = local();
    await command('pan', direction);
    assert.equal(local().cameraX, bounded.cameraX); assert.equal(local().cameraY, bounded.cameraY);
  }
  await command('home'); assert.deepEqual(runtime.snapshot(1), snapshot);
  console.log('ok - projected camera axes and diagonal agree with input; first-bound clipping preserves the direction');
  await point(12, 20); assert.equal(local().cursorX, 12); assert.equal(local().cursorY, 20);
  assert.match(node('context-title').text, /BUILD (AN )?EXTRACTOR/);
  await command('confirm'); assert.equal(world().buildings[0].kind, 1); assert.equal(world().ore, 120);
  await advance(140); assert.equal(world().buildings[0].stage, 2);
  await point(12, 20, 0.94); assert.equal(local().cursorX, 12); assert.equal(local().cursorY, 20);
  await command('confirm'); assert.equal(world().buildings[0].level, 2);
  console.log('ok - camera projection and Scheme ground picking agree; contextual deposit builds and mine click upgrades');
  await point(12, 21); const beforeChoice = runtime.snapshot(1), beforeScene = runtime.view().scene;
  const selectedPoint = project(12, 21, .08); await command('confirm');
  assert.equal(local().chooser, true); assert.deepEqual(runtime.snapshot(1), beforeChoice);
  assert.equal(node('context'), undefined); assert.ok(node('build-chooser'));
  assert.deepEqual(geometry(runtime.view().scene), geometry(beforeScene));
  const chooser = placed('build-chooser');
  const dx = Math.max(chooser.left - selectedPoint[0], selectedPoint[0] - chooser.right, 0);
  const dy = Math.max(chooser.top - selectedPoint[1], selectedPoint[1] - chooser.bottom, 0);
  assert.ok(dx > 0 || dy > 0); assert.ok(Math.hypot(dx, dy) <= 36);
  await point(13, 21); assert.deepEqual(placed('build-chooser'), chooser); await command('choose', [1]);
  assert.equal(local().chooser, false); assert.ok(world().buildings.some(value => value.kind === 3 && value.x === 12 && value.y === 21));
  await advance(180); assert.ok(world().rails.length > 0);
  await point(13, 22); await command('confirm'); await command('choose', [2]);
  assert.ok(world().buildings.some(value => value.kind === 2 && value.x === 13 && value.y === 22));
  console.log('ok - cursor-local choice has no rail preview, survives hover movement and dispatches the locked site');
  await command('suspend', [1]); await point(12, 21, 2.1); await command('relocate');
  assert.match(node('context-title').text, /MOVE STRUCTURE/); await point(12, 22);
  const oreBeforeMove = world().ore; await command('confirm');
  assert.equal(world().buildings.find(value => value.kind === 3).moveY, 22);
  await point(12, 21, 2.1); await command('cancel');
  assert.equal(world().buildings.find(value => value.kind === 3).moveX, -1); assert.equal(world().ore, oreBeforeMove);
  await command('suspend', [0]);
  console.log('ok - tower bounds, explicit move context and queued move cancellation preserve the paid ledger');
  await command('viewport', [390, 844]); await point(12.4, 20, 0.94);
  assert.equal(local().cursorX, 12); assert.equal(local().cursorY, 20);
  await point(13, 21); await command('confirm'); await command('cancel'); assert.equal(local().chooser, false);
  const committed = runtime.snapshot(1), selection = runtime.snapshot(2);
  await runtime.replace(runtime.prepare(bytes, manifest)); await runtime.initialize(1); await runtime.initialize(2);
  assert.deepEqual(runtime.snapshot(1), committed); assert.deepEqual(runtime.snapshot(2), selection);
  console.log('ok - narrow viewport picking, explicit chooser cancellation and compatible reload preserve state');
  if (process.argv[3]) {
    const previous = JSON.parse(readFileSync(join(process.argv[3], 'manifest.json')));
    const oldBytes = readFileSync(join(process.argv[3], previous.module)); assert.notDeepEqual(oldBytes, bytes);
    await runtime.replace(runtime.prepare(oldBytes, previous));
    assert.deepEqual(runtime.snapshot(1), committed); assert.deepEqual(runtime.snapshot(2), selection);
    await runtime.replace(runtime.prepare(bytes, manifest));
    assert.deepEqual(runtime.snapshot(1), committed); assert.deepEqual(runtime.snapshot(2), selection);
    console.log('ok - changed-code replacement and restoration preserve both owners');
  }
  await command('suspend', [-1]); assert.equal(world().paused, 1);
  await command('suspend', [-1]); assert.equal(world().paused, 0);
} finally { await runtime.close(); }
