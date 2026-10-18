// Derive first-extractor guidance from real Scheme transitions and saved worlds.
import assert from 'node:assert/strict';
import {mkdirSync, readFileSync, writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {ReducerRuntime, protocolContract} from '../../src/application/runtime.mjs';
import {colony, client, restoreColony, addEnemy, at, siteAt} from '../applications/colony-state.mjs';

const output = process.argv[2], fixtures = process.argv[3], previous = process.argv[4];
const manifest = JSON.parse(readFileSync(join(output, 'manifest.json')));
const bytes = readFileSync(join(output, manifest.module)), runtime = new ReducerRuntime();
await runtime.replace(runtime.prepare(bytes, manifest)); await runtime.initialize(1); await runtime.initialize(2);
const world = () => colony(runtime.snapshot(1)), local = () => {
  const value=client(runtime.snapshot(2)), hub=world().surveys.find(s=>s.radius===9);
  return {...value,cursorX:value.cursorX<0?-1:value.cursorX-hub.x+8,cursorY:value.cursorY<0?-1:value.cursorY-hub.y+22};
};
async function command(binding, args = []) {
  const result = await runtime.dispatch(2, runtime.command('client', binding, args));
  for (const effect of result.effects) if (effect.kind === 'send') await runtime.dispatch(1, runtime.effectCommand(effect));
}
async function advance(ticks) {
  for (let i = 0; i < ticks; i++) await runtime.dispatch(1, runtime.command('match', 'advance'));
}
function node(key, value = runtime.view().ui) {
  if (value.key === key) return value;
  for (const child of value.children) { const found = node(key, child); if (found) return found; }
}
const onboarding = () => !!node('onboarding');
function project(x, y, z = 0) {
  ({x,y}=at(world(),x,y));
  const scene = runtime.view().scene, m = scene.uniforms, state = local(), v = scene.viewport ?? [0, 0, state.width, state.height];
  return [Math.round(v[0] + (m[0] * x - m[4] * y + m[8] * z + m[12] + 1) * v[2] / 2),
    Math.round(v[1] + (1 - (m[1] * x - m[5] * y + m[9] * z + m[13])) * v[3] / 2)];
}
const point = (x, y, z) => command('move', project(x, y, z));
function save(name) {
  if (!fixtures) return;
  mkdirSync(fixtures, {recursive: true});
  writeFileSync(join(fixtures, name + '.json'), JSON.stringify({revision: 1, epoch: name, clients: {}, state: runtime.snapshot(1)}));
}
try {
  const fresh = runtime.snapshot(1);
  assert.ok(onboarding()); assert.equal(node('context-title').text, 'START: BUILD AN EXTRACTOR');
  await command('pan', [20, -20]); await command('home');
  assert.equal(local().cursorX, 12); assert.equal(local().cursorY, 20); assert.deepEqual(runtime.snapshot(1), fresh);
  await runtime.replace(runtime.prepare(bytes, manifest));
  assert.ok(onboarding()); assert.deepEqual(runtime.snapshot(1), fresh);
  // This tallest visible tip projects onto the adjacent ground cell (11, 19).
  await point(11.8, 20, 0.63); assert.equal(local().cursorX, 12); assert.equal(local().cursorY, 20);
  await command('confirm'); assert.equal(world().buildings[0].kind, 1); assert.equal(onboarding(), false);
  await point(11.8, 20, 0.63); assert.equal(local().cursorX, 12); assert.equal(local().cursorY, 20);
  await command('cancel'); assert.equal(world().buildings.length, 0); assert.ok(onboarding());
  await command('confirm'); await advance(140); assert.equal(world().buildings[0].stage, 2);
  assert.ok(world().surveys.some(s => s.x === at(world(),12,20).x && s.y === at(world(),12,20).y)); assert.equal(onboarding(), false);
  await command('suspend', [1]); const established = runtime.snapshot(1), selection = runtime.snapshot(2); save('established');
  await runtime.replace(runtime.prepare(bytes, manifest)); assert.equal(onboarding(), false);
  assert.deepEqual(runtime.snapshot(1), established); assert.deepEqual(runtime.snapshot(2), selection);
  console.log('ok - fresh/reloaded guidance, crystal-tip order, cancellation and completed survey history');

  if (previous) {
    const old = JSON.parse(readFileSync(join(previous, 'manifest.json')));
    assert.equal(protocolContract(manifest), protocolContract(old));
    const oldBytes = readFileSync(join(previous, old.module)); assert.notDeepEqual(oldBytes, bytes);
    await runtime.replace(runtime.prepare(oldBytes, old));
    assert.deepEqual(runtime.snapshot(1), established); assert.deepEqual(runtime.snapshot(2), selection);
    await runtime.replace(runtime.prepare(bytes, manifest));
    assert.deepEqual(runtime.snapshot(1), established); assert.deepEqual(runtime.snapshot(2), selection);
    assert.equal(onboarding(), false);
    console.log('ok - previous code and current code share exact owner/handler contracts and preserve both snapshots');
  }

  const attacked = world(); attacked.buildings[0].hp = 1; attacked.paused = 0;
  await restoreColony(runtime, attacked); await addEnemy(runtime, {x: 12, y: 20, target: attacked.buildings[0].id});
  await advance(20); assert.equal(world().buildings.length, 0); assert.equal(world().outcome, 0);
  assert.ok(world().surveys.some(s => s.x === at(world(),12,20).x && s.y === at(world(),12,20).y)); assert.equal(onboarding(), false);
  console.log('ok - actual enemy destruction retains completion evidence and never restores onboarding');

  await runtime.restore(1, fresh);
  for (const y of [15, 9]) {
    const site=at(world(),10,y); await runtime.dispatch(1, runtime.command('match', 'observe', [site.x,site.y])); await advance(180);
  }
  await command('home'); assert.equal(local().cursorX, 5); assert.equal(local().cursorY, 5);
  await command('confirm'); await advance(10);
  const planned = world().buildings.find(b => b.kind === 1);
  assert.ok(planned); assert.equal(planned.x, at(world(),5,5).x); assert.equal(planned.y, at(world(),5,5).y);
  console.log('ok - guidance finds the richer deposit after tower exploration; building remains an explicit choice');

  await runtime.restore(1, fresh); const unsafe = world();
  await addEnemy(runtime, {x: 12, y: 20}); await command('home');
  assert.ok(onboarding()); assert.match(node('context-description').text, /No free/);
  assert.equal(local().cursorX, 8); assert.equal(local().cursorY, 22);
  await restoreColony(runtime, {...unsafe, hull: 1}); await addEnemy(runtime, {x: 8, y: 22}); await advance(20);
  assert.equal(world().outcome, 1); assert.equal(onboarding(), false);
  assert.ok(node('result')); assert.equal(node('context-title').text, 'COLONY LOST'); assert.equal(node('restart').properties[1], 1);
  save('defeated');
  await command('restart'); assert.equal(world().outcome, 0); assert.ok(onboarding());
  console.log('ok - no safe target falls back to hub; actual defeat shows restart and suppresses onboarding');
} finally { await runtime.close(); }
