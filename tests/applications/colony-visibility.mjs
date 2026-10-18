// Surveyed terrain and current sight differ. Exercise both at the real Wasm
// command boundary, including menus opened before the source of sight is lost.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,client,colonyBalance,restoreColony,restoreClient,fixtureCall,at,setWorker,pixelAt} from './colony-state.mjs';

const state=r=>colony(r.snapshot(1));
const orders=[['extract',5,5,40,1],['observe',12,11,25,1],['fortify',12,11,50,2],['build-wall',12,11,8,3]];
async function advance(r,count=1) {
  for(let i=0;i<count;i++) {
    await fixtureCall(r,'advance'); const world=state(r),balance=colonyBalance(world);
    assert.equal(world.ore,balance.bank); assert.equal(world.produced,balance.raw);
  }
}
async function complete(r) {
  for(let i=0;i<600&&state(r).buildings[0].stage!==2;i++)await advance(r);
  assert.equal(state(r).buildings[0].stage,2);
}
async function select(r,x,y) {
  const local=client(r.snapshot(2)),point=at(state(r),x,y);
  Object.assign(local,{cursorX:point.x,cursorY:point.y}); await restoreClient(r,local);
  await r.dispatch(2,r.command('client','confirm'));
}
async function choose(r,choice) {
  const result=await r.dispatch(2,r.command('client','choose',[choice]));
  assert.equal(result.effects.length,1);
  for(const effect of result.effects)await r.dispatch(1,r.effectCommand(effect));
}
async function roundTrip(r) {
  const saved=r.snapshot(1); await r.restore(1,saved); assert.deepEqual(r.snapshot(1),saved);
  assert.equal(r.lastFailure,undefined);
}

export async function checkVisibility(test,fresh) {
  for(const [name,x,y,cost,choice] of orders) {
    await test(`${name}: new hidden orders preserve resources and existing kits finish after sight returns`,async()=>{
      const r=await fresh(),world=state(r);
      world.surveys.unshift({...at(world,12,14),radius:10},{...at(world,5,5),radius:7});
      await restoreColony(r,world); await fixtureCall(r,name,[x,y]);
      assert.deepEqual(state(r),{...world,notice:1},'fresh hidden order changes only its notice');

      const shown=state(r); setWorker(shown,0,{x,y:y+1}); await restoreColony(r,shown);
      await select(r,x,y); const gone=state(r); setWorker(gone,0); await restoreColony(r,gone);
      await choose(r,choice); assert.deepEqual(state(r),{...gone,notice:1},'stale menu cannot spend');

      const visible=state(r); setWorker(visible,0,{x,y:y+1}); await restoreColony(r,visible);
      await fixtureCall(r,name,[x,y]); const ordered=state(r),project=ordered.buildings[0];
      assert.equal(ordered.notice,10); assert.equal(ordered.ore,160-cost); assert.equal(project.stage,3);
      assert.equal(ordered.rails.length,name==='observe'||name==='fortify'?1:0);
      assert.notEqual(ordered.bots[0].order,project.id,'the scout is separate from the reserved builder');
      setWorker(ordered,0); await restoreColony(r,ordered); await advance(r,10);
      assert.equal(state(r).buildings[0].stage,0); assert.equal(state(r).spent,cost);
      assert.ok(state(r).bots.every(bot=>bot.order===0&&bot.cargo===0)); await roundTrip(r);

      const resumed=state(r); setWorker(resumed,0,{x,y:y+1}); await restoreColony(r,resumed); await advance(r);
      const carried=state(r); assert.equal(carried.buildings[0].stage,1);
      assert.ok(carried.bots.some(bot=>bot.job===3&&bot.cargo===(name==='fortify'?25:cost)));
      setWorker(carried,0); await restoreColony(r,carried); await roundTrip(r); await complete(r);
      assert.equal(state(r).spent,cost); await roundTrip(r); await r.close();
    });
  }
  await test('destroying an observer safely rejects menu choices made before or after visibility is lost',async()=>{
    const r=await fresh(); await fixtureCall(r,'observe',[12,14]); await complete(r);
    const world=state(r); world.buildings[0].hp=7; world.tick=9; world.lastRevealTick=-100;
    for(let i=0;i<world.bots.length;i++)setWorker(world,i);
    await restoreColony(r,world); await select(r,12,11); const selected=r.snapshot(2),pending=[];
    for(const choice of [1,2,3]) {
      await r.restore(2,selected); const result=await r.dispatch(2,r.command('client','choose',[choice]));
      assert.equal(result.effects.length,1); pending.push(result.effects[0]);
    }
    const attacked=state(r);
    attacked.enemies.push({id:attacked.nextId++,...pixelAt(attacked,12,14),hp:80,kind:0,
      target:attacked.buildings[0].id,path:[]});
    await restoreColony(r,attacked); await advance(r); const destroyed=state(r);
    assert.equal(destroyed.buildings.length,0); assert.equal(destroyed.rails.length,0);
    assert.deepEqual(destroyed.tracks,world.tracks); assert.deepEqual(destroyed.surveys,world.surveys);
    for(const effect of pending) {
      await r.dispatch(1,r.effectCommand(effect)); assert.deepEqual(state(r),{...destroyed,notice:1});
    }
    for(const choice of [1,2,3]) {
      await r.restore(2,selected); await choose(r,choice); assert.deepEqual(state(r),{...destroyed,notice:1});
    }
    await roundTrip(r); await r.close();
  });
}

if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json')));
  const bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};
  let count=0; await checkVisibility(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);
  console.log(`${count} construction visibility checks passed`);
}
