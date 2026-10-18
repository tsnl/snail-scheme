// Stable strength and wave progression are exercised through the real reducers.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,restoreColony,fixtureCall,pixelAt} from './colony-state.mjs';

export async function checkRanks(test,fresh) {
  const state=r=>colony(r.snapshot(1)),call=fixtureCall;
  async function wave(r,tick) {
    const world=state(r); world.started=true; world.tick=tick-1; world.enemies=[];
    await restoreColony(r,world); await call(r,'advance'); return state(r).enemies;
  }
  await test('each strength rank arrives singly with familiar escorts before the first boss',async()=>{
    const r=await fresh(),health=[65,90,125,180,300,500,1800];
    for(const [tick,rank] of [[300,0],[600,1],[1200,2],[1800,3],[2400,4],[3000,5],[3600,6]]) {
      const enemies=await wave(r,tick); assert.equal(Math.max(...enemies.map(enemy=>enemy.rank)),rank);
      if(rank>0)assert.equal(enemies.filter(enemy=>enemy.rank===rank).length,1);
      assert.ok(enemies.some(enemy=>enemy.rank===0));
      if(rank>1)assert.ok(enemies.some(enemy=>enemy.rank===rank-1));
      for(const enemy of enemies)assert.equal(enemy.hp,enemy.kind===1?Math.floor(health[enemy.rank]*4/5):health[enemy.rank]);
      assert.equal(enemies.filter(enemy=>enemy.kind===2).length,rank===6?1:0);
    }
    await r.close();
  });
  await test('bosses recur separately while new enemies continue gaining health after rank six',async()=>{
    const r=await fresh(); assert.ok((await wave(r,3900)).every(enemy=>enemy.rank<6));
    const later=await wave(r,7200); assert.equal(later[0].rank,6); assert.equal(later[0].hp,1890);
    assert.equal(later.filter(enemy=>enemy.rank===6).length,1);
    assert.equal((await wave(r,25200))[0].hp,2310); assert.equal((await wave(r,28800))[0].hp,2310);
    await r.close();
  });
  await test('wounded ranks retain their damage and survive pause and snapshot restore',async()=>{
    const r=await fresh(),damage=[7,8,10,12,16,20,30];
    for(let rank=0;rank<=6;rank++) {
      const world=state(r); world.started=true; world.tick=9; world.hull=300; world.alerts=[];
      world.enemies=[{id:world.nextId++,...pixelAt(world,8,22),hp:1,kind:0,target:0,path:[],rank}];
      await restoreColony(r,world); await call(r,'advance');
      assert.equal(state(r).hull,300-damage[rank]); assert.equal(state(r).enemies[0].rank,rank);
      await call(r,'pause-colony',[1]); const saved=r.snapshot(1); await r.restore(1,saved); await call(r,'advance');
      assert.deepEqual(r.snapshot(1),saved); await call(r,'pause-colony',[0]);
    }
    await r.close();
  });
  await test('rank and continued-health bounds are checked before a snapshot replaces live state',async()=>{
    const r=await fresh(); await wave(r,3600); const saved=r.snapshot(1);
    for(const edit of [enemy=>enemy.rank=-1,enemy=>enemy.rank=7,enemy=>enemy.hp=2311]) {
      const world=colony(saved); edit(world.enemies[0]);
      await assert.rejects(()=>restoreColony(r,world),WebAssembly.RuntimeError); assert.deepEqual(r.snapshot(1),saved);
    }
    await r.close();
  });
  await test('the first accepted order starts time and cancellation never stops it again',async()=>{
    const r=await fresh(); for(let i=0;i<30;i++)await call(r,'advance');
    assert.equal(state(r).started,false); assert.equal(state(r).tick,0);
    await call(r,'observe',[8,22]); await call(r,'advance'); assert.equal(state(r).tick,0);
    await call(r,'pause-colony',[1]); await call(r,'pause-colony',[0]); assert.equal(state(r).started,false);
    const waiting=r.snapshot(1); await r.restore(1,waiting); assert.equal(state(r).started,false);
    await call(r,'observe',[10,22]); assert.equal(state(r).started,true);
    await call(r,'cancel-building',[10,22]); assert.equal(state(r).buildings.length,0);
    await call(r,'advance'); assert.equal(state(r).tick,1);
    await call(r,'new-run-seed',[1]); await call(r,'advance'); assert.equal(state(r).tick,0);
    await call(r,'fabricate-worker'); await call(r,'advance'); assert.equal(state(r).started,true); assert.equal(state(r).tick,1);
    await r.close();
  });
}

if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json')));
  const bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};
  let count=0; await checkRanks(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);
  console.log(`${count} rank and clock checks passed`);
}
