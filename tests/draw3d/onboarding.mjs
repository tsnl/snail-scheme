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
async function home() {
  await command('home');
  for(let i=0;i<80&&local().homing;i++)await command('animate',[50]);
  assert.equal(local().homing,false);
}
function cursor(x,y) { assert.equal(local().cursorX,x);assert.equal(local().cursorY,y); }
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
  const fresh=runtime.snapshot(1);
  assert.equal(node('onboarding'),undefined);assert.equal(node('context'),undefined);
  await command('center');cursor(12,20);
  await command('pan',[20,-20]);await home();cursor(8,22);
  assert.match(node('context-title').text,/hub/i);assert.deepEqual(runtime.snapshot(1),fresh);
  await command('dismiss');await command('center');cursor(12,20);
  await runtime.replace(runtime.prepare(bytes,manifest));assert.deepEqual(runtime.snapshot(1),fresh);
  // The tallest visible tip projects onto an adjacent ground cell.
  await point(11.8,20,.63);cursor(12,20);assert.equal(node('context'),undefined);
  await command('confirm');assert.match(node('context-title').text,/deposit/i);
  assert.deepEqual(runtime.snapshot(1),fresh);await command('choose',[1]);assert.equal(world().buildings[0].kind,1);
  await point(11.8,20,.63);cursor(12,20);await command('confirm');await command('cancel');
  assert.equal(world().buildings.length,0);await command('center');cursor(12,20);
  await command('confirm');await command('choose',[1]);await advance(140);assert.equal(world().buildings[0].stage,2);
  assert.ok(world().surveys.some(s=>s.x===at(world(),12,20).x&&s.y===at(world(),12,20).y));
  await command('center');cursor(8,22);await command('suspend',[1]);
  const established=runtime.snapshot(1),selection=runtime.snapshot(2);save('established');
  if(fixtures){
    // Bounded known-location alerts exercise live cameras without revealing fog.
    const encounters=world();encounters.alerts=[[12,20,1],[8,22,0],[10,22,4]].map(([x,y,kind])=>({...at(encounters,x,y),kind,tick:encounters.tick}));
    await restoreColony(runtime,encounters);save('alerts');await runtime.restore(1,established);
  }
  await runtime.replace(runtime.prepare(bytes,manifest));assert.equal(node('context'),undefined);
  assert.deepEqual(runtime.snapshot(1),established);assert.deepEqual(runtime.snapshot(2),selection);
  console.log('ok - fresh guidance centers a deposit; H selects the hub; crystal-tip selection, explicit order and cancellation preserve intent');

  if(previous){
    const old=JSON.parse(readFileSync(join(previous,'manifest.json')));
    assert.equal(protocolContract(manifest),protocolContract(old));
    const oldBytes=readFileSync(join(previous,old.module));assert.notDeepEqual(oldBytes,bytes);
    await runtime.replace(runtime.prepare(oldBytes,old));assert.deepEqual(runtime.snapshot(1),established);assert.deepEqual(runtime.snapshot(2),selection);
    await runtime.replace(runtime.prepare(bytes,manifest));assert.deepEqual(runtime.snapshot(1),established);assert.deepEqual(runtime.snapshot(2),selection);
    console.log('ok - compatible old and current modules preserve exact owner snapshots');
  }

  const attacked=world();attacked.buildings[0].hp=1;attacked.paused=0;
  await restoreColony(runtime,attacked);await addEnemy(runtime,{x:12,y:20,target:attacked.buildings[0].id});await advance(20);
  assert.equal(world().buildings.length,0);assert.equal(world().outcome,0);
  assert.ok(world().surveys.some(s=>s.x===at(world(),12,20).x&&s.y===at(world(),12,20).y));
  await command('center');cursor(8,22);
  console.log('ok - actual enemy destruction retains completion history and does not restore first-extractor guidance');

  await runtime.restore(1,fresh);
  for(const y of [15,9]){
    const site=at(world(),10,y);await runtime.dispatch(1,runtime.command('match','observe',[site.x,site.y]));await advance(180);
  }
  await command('center');cursor(5,5);const explored=runtime.snapshot(1);
  await command('confirm');assert.deepEqual(runtime.snapshot(1),explored);await command('choose',[1]);await advance(10);
  const planned=siteAt(world(),5,5);assert.ok(planned);assert.equal(planned.kind,1);
  console.log('ok - explored richer deposits become the guidance target while construction stays explicit');

  await runtime.restore(1,fresh);const unsafe=world();await addEnemy(runtime,{x:12,y:20});await command('center');cursor(8,22);
  await restoreColony(runtime,{...unsafe,hull:1});await addEnemy(runtime,{x:8,y:22});await advance(20);
  assert.equal(world().outcome,1);assert.ok(node('result'));assert.match(node('context-title').text,/colony lost/i);
  assert.equal(node('restart').properties[1],1);
  await restoreColony(runtime,{...world(),bots:[]});assert.ok(node('workers'));assert.equal(world().bots.length,0);runtime.view();save('defeated');
  await command('restart');assert.equal(world().outcome,1);assert.ok(node('restart-dialog'));
  await command('accept-restart');assert.equal(world().outcome,0);assert.equal(node('restart-dialog'),undefined);
  await command('center');cursor(12,20);
  console.log('ok - unsafe guidance falls back to the hub, a zero-worker HUD renders, and defeat requires explicit restart confirmation');
} finally { await runtime.close(); }
