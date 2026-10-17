// Reproducible observation of the optional policies, not a claim that one is fun
// or globally optimal. The manual baseline issues the same public build orders.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,colonyBalance} from './colony-state.mjs';
const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json')));
const bytes=readFileSync(join(directory,manifest.module)), results=[];
for(const seed of [1,7,43]) for(const mode of ['manual-baseline','explore','defend']) {
  const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);
  const call=(name,args=[])=>r.dispatch(1,r.command('match',name,args));
  await call('new-run-seed',[seed]);
  if(mode==='manual-baseline') {await call('extract',[12,20]);await call('fortify',[15,20]);await call('observe',[16,21]);}
  else await call('set-focus',[mode==='explore'?1:2]);
  const sites=[[16,22],[15,24],[12,24],[16,18],[13,17],[18,20],[18,22],[19,18]];
  let next=0,localKits=0,kits=0,maxMines=0,maxWorkers=3,world=colony(r.snapshot(1));
  let minHull=world.hull,minReserve=world.ore,peakThreats=0,firstDamageTick=null;
  const observed=new Set(world.buildings.map(b=>b.id)); const started=performance.now();
  for(let tick=0;tick<4800&&world.outcome===0;tick++) {
    if(mode==='manual-baseline'&&world.ore>=50&&next<sites.length){await call('fortify',sites[next]);if(colony(r.snapshot(1)).notice===10)next++;}
    await call('advance');world=colony(r.snapshot(1));const balance=colonyBalance(world);
    assert.equal(world.ore,balance.bank);assert.equal(world.produced,balance.raw);
    minHull=Math.min(minHull,world.hull);minReserve=Math.min(minReserve,world.ore);
    peakThreats=Math.max(peakThreats,world.enemies.length);
    if(firstDamageTick===null&&(world.hull<300||world.alerts.length>0))firstDamageTick=world.tick;
    for(const building of world.buildings)if(!observed.has(building.id)){observed.add(building.id);kits++;if(building.source>0)localKits++;}
    maxMines=Math.max(maxMines,world.buildings.filter(b=>b.kind===1&&b.stage===2).length);
    maxWorkers=Math.max(maxWorkers,world.bots.length);
    if(mode!=='manual-baseline')assert.ok(world.ore>=40,'automatic purchases retain the hub reserve');
  }
  const result={seed,mode,outcome:world.outcome,tick:world.tick,ore:world.ore,hull:world.hull,minHull,minReserve,peakThreats,firstDamageTick,
    produced:world.produced,delivered:world.delivered,
    localSpent:world.localSpent,casualties:world.casualties,lostBuildings:world.lost,maxMines,maxWorkers,kits,localKits,
    elapsedMs:Math.round(performance.now()-started)};
  assert.ok(world.produced>0&&world.delivered>0);assert.ok(maxMines>=1);
  results.push(result);console.log(JSON.stringify(result));await r.close();
}
if(process.argv[3])writeFileSync(process.argv[3],JSON.stringify({generation:manifest.generation,results},null,2)+'\n');
