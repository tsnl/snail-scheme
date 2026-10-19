// Replace genuinely different compiled schema-12 game artifacts while a move
// owns freight. Neither package nor its on-disk save is modified by this check.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,colonyBalance,fixtureCall,at} from './colony-state.mjs';
function artifact(directory) {
  const path=resolve(directory),manifest=JSON.parse(readFileSync(join(path,'manifest.json')));
  return {manifest,bytes:readFileSync(join(path,manifest.module))};
}
const old=artifact(process.argv[2]),next=artifact(process.argv[3]);
assert.notDeepEqual(old.bytes,next.bytes,'replacement must contain changed compiled game code');
const r=new ReducerRuntime();await r.replace(r.prepare(old.bytes,old.manifest));
await r.initialize(1);await r.initialize(2);
const call=(name,args=[])=>fixtureCall(r,name,args);
const state=()=>colony(r.snapshot(1));
async function until(predicate) {
  for(let tick=0;tick<500&&!predicate(state());tick++)await call('advance');
  assert.ok(predicate(state()),'bounded scenario reaches its checkpoint');
}
await call('extract',[12,20]);await until(w=>w.buildings[0].stage===2);
await call('observe',[12,21]);await until(w=>w.buildings[1]?.stage===2&&w.rails.some(l=>l.cargo>0));
await call('pause-colony',[1]);await call('relocate-building',[12+21*48,12+22*48]);
await r.dispatch(2,r.command('client','pan',[-100,-100]));
await r.dispatch(2,r.command('client','confirm'));
await r.dispatch(2,r.command('client','preview',[1]));
const world=r.snapshot(1),local=r.snapshot(2);
assert.equal(state().buildings[1].moveY,at(state(),12,22).y);assert.ok(state().rails.some(l=>l.cargo>0));
await r.replace(r.prepare(next.bytes,next.manifest));await r.initialize(1);await r.initialize(2);
assert.deepEqual(r.snapshot(1),world);assert.deepEqual(r.snapshot(2),local);
await call('advance');assert.deepEqual(r.snapshot(1),world);
await call('pause-colony',[0]);await until(w=>w.buildings[1].y===at(w,12,22).y);
const finished=state(),balance=colonyBalance(finished);
assert.equal(finished.ore,balance.bank);assert.equal(finished.produced,balance.raw);
console.log('ok - changed compiled game preserves paused freight, queued move and local camera/selection',
  old.manifest.generation,'→',next.manifest.generation);
await r.close();
