// Deterministic commands exercise the real reducer and its commit-time validator.
// A failure retains the exact pre-command words and replay context under /tmp.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,colonyBalance,colonyWords,restoreColony,fixtureCall,origin,at} from './colony-state.mjs';

const directory=resolve(process.argv[2]),steps=Number(process.argv[3]??2400);
const sustained=process.argv.includes('--sustained');
const manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
let commands=0,roundTrips=0,attacks=0,repairs=0;
for(const seed of [1,7,43,65535]) {
  const r=new ReducerRuntime(); await r.replace(r.prepare(bytes,manifest)); await r.initialize(1); await r.initialize(2);
  let random=seed,iteration=0,candidate;
  const validate=r.validateReplacement.bind(r);
  r.validateReplacement=(instance,tx)=>{if(tx.next)candidate=Array.from(tx.next);return validate(instance,tx);};
  const next=limit=>{random=(Math.imul(random,1664525)+1013904223)>>>0;return random%limit;};
  async function action(name,args=[]) {
    const before=r.snapshot(1); candidate=undefined;
    try {
      await fixtureCall(r,name,args); commands++;
      const world=colony(r.snapshot(1)),balance=colonyBalance(world);
      assert.equal(world.ore,balance.bank); assert.equal(world.produced,balance.raw);
    } catch(error) {
      const path=`/tmp/siegework-transition-failure-${seed}.json`;
      writeFileSync(path,JSON.stringify({artifact:directory,seed,iteration,name,args,before,candidate,error:String(error)}));
      throw new Error(`seed ${seed}, iteration ${iteration}, ${name} ${JSON.stringify(args)}; replay ${path}`,{cause:error});
    }
  }
  async function order() {
    const world=colony(r.snapshot(1)),offset=origin(world),site=world.buildings[next(Math.max(1,world.buildings.length))];
    const x=8+next(17)-8,y=22+next(17)-8;
    switch(next(9)) {
      case 0: await action('observe',[x,y]); break;
      case 1: await action('fortify',[x,y]); break;
      case 2: await action('upgrade',[8,22]); break;
      case 3: if(site)await action('upgrade',[site.x-offset.x,site.y-offset.y]); break;
      case 4: if(site)await action('cancel-building',[site.x-offset.x,site.y-offset.y]); break;
      case 5: await action('fabricate-worker'); break;
      case 6: if(site) {
        const sx=site.x-offset.x,sy=site.y-offset.y;
        await action('relocate-building',[sx+sy*48,sx+(next(2)?1:-1)+sy*48]);
      } break;
      case 7: await action('extract',[12,20]); break;
      case 8: {
        await action('pause-colony',[1]); const saved=r.snapshot(1); await action('advance');
        assert.deepEqual(r.snapshot(1),saved); await r.restore(1,saved); roundTrips++;
        await action('pause-colony',[0]);
      } break;
    }
  }
  await action('new-run-seed',[seed]); await action('extract',[12,20]);
  for(;iteration<steps;iteration++) {
    let world=colony(r.snapshot(1));
    if(world.outcome!==0) {
      if(!sustained||world.outcome!==1)break;
      // A bounded fixture repairs a defeated hub and funds another construction
      // cycle; actual combat and all subsequent material transitions stay real.
      world.hull=300; world.outcome=0; world.enemies=[];
      world.produced+=500; world.delivered+=500; world.ore+=500;
      await restoreColony(r,world); repairs++;
    }
    if(iteration%13===0)await order();
    if(iteration>0&&iteration%180===0) {
      world=colony(r.snapshot(1));
      const sites=world.buildings.filter(site=>site.stage===2),site=sites[next(Math.max(1,sites.length))];
      const point=site??at(world,12,20),rank=attacks%5;
      world.enemies.push({id:world.nextId++,x:point.x*40+20,y:point.y*40+20,
        hp:[80,90,125,180,300][rank],kind:attacks%2,target:0,path:[],rank});
      if(world.enemies.length<=128) {await restoreColony(r,world);attacks++;}
    }
    await action('advance');
    if(iteration%37===0) {
      const saved=r.snapshot(1); await r.restore(1,saved); roundTrips++;
      assert.deepEqual(r.snapshot(1),saved); assert.deepEqual(colonyWords(colony(saved)),saved);
    }
  }
  const world=colony(r.snapshot(1));
  console.log(JSON.stringify({seed,iterations:iteration,tick:world.tick,outcome:world.outcome,
    workers:world.bots.length,casualties:world.casualties,buildings:world.buildings.length,lost:world.lost,spent:world.spent}));
  await r.close();
}
console.log(`stress passed: ${commands} validated commands, ${roundTrips} save round-trips, ${attacks} close encounters, ${repairs} fixture repairs`);
