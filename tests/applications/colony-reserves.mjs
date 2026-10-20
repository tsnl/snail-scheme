// Boundary worlds establish last-unit and ownership races. Every production,
// task, construction and loss transition runs through the compiled authority.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {MAP_WIDTH,colony,colonyBalance,restoreColony,fixtureCall,setWorker,at,pixelAt,withdrawReserves} from './colony-state.mjs';

const state=r=>colony(r.snapshot(1)),call=fixtureCall;
const reserve=(world,site)=>world.deposits.find(deposit=>deposit.cell===site.x+site.y*MAP_WIDTH);
function leaveReserve(world,site,remaining) {
  const deposit=reserve(world,site),amount=deposit.remaining-remaining;
  assert.ok(amount>=0);deposit.remaining=remaining;world.produced+=amount;world.lostOre+=amount;
}
function balance(world) {
  const sums=colonyBalance(world);assert.equal(world.ore,sums.bank);assert.equal(world.produced,sums.raw);
}
async function advance(r,count=1) {for(let i=0;i<count;i++){await call(r,'advance');balance(state(r));}}
async function mine(fresh,level=1) {
  const r=await fresh();await call(r,'extract',[12,20]);
  for(let i=0;i<150&&state(r).buildings[0].stage!==2;i++)await advance(r);
  assert.equal(state(r).buildings[0].stage,2);
  if(level>1)await call(r,'upgrade',[12,20]);
  if(level>2){const w=state(r);withdrawReserves(w,200);w.delivered+=200;w.ore+=200;await restoreColony(r,w);await call(r,'upgrade',[12,20]);}
  return r;
}
function fixtureMine(world,x,y) {
  const point=at(world,x,y),aim=pixelAt(world,x,y);
  const site={id:world.nextId++,kind:1,...point,level:1,hp:140,stock:0,stage:2,cooldown:0,
    aimX:aim.x,aimY:aim.y,armed:0,source:0,moveX:-1,moveY:-1};
  world.buildings.push(site);world.surveys.unshift({...point,radius:7});world.spent+=25;world.ore-=25;return site;
}

export async function checkReserves(test,fresh) {
  await test('finite reserves are canonical seed-owned records with an explicit starter supply',async()=>{
    const r=await fresh();
    for(const seed of [1,7,43,65535]) {
      await call(r,'new-run-seed',[seed]);const w=state(r),starter=at(w,12,20);
      assert.equal(reserve(w,starter).remaining,600);assert.ok(w.deposits.length<=46&&w.deposits.length>3);
      assert.equal(new Set(w.deposits.map(d=>d.cell)).size,w.deposits.length);assert.equal(w.produced,0);
      const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);
    }
    await r.close();
  });
  await test('three miners clip one shared final withdrawal and freight ships its last partial load',async()=>{
    const r=await mine(fresh,3),w=state(r),site=w.buildings[0];leaveReserve(w,site,5);
    w.tick=9;w.lastRevealTick=-100;
    for(let i=0;i<3;i++)setWorker(w,i,{x:12,y:20,job:8,target:site.id});
    await restoreColony(r,w);await advance(r);const exhausted=state(r);
    assert.equal(reserve(exhausted,site).remaining,0);assert.equal(exhausted.produced,w.produced+5);
    assert.ok(exhausted.bots.every(bot=>![8,9].includes(bot.job)));assert.equal(exhausted.buildings[0].stock,0);
    assert.equal(exhausted.bots.reduce((sum,bot)=>sum+bot.cargo,0)+exhausted.rails.reduce((sum,rail)=>sum+rail.cargo,0),5);
    await advance(r,80);assert.equal(state(r).produced,exhausted.produced);assert.equal(state(r).delivered,w.delivered+5);
    await call(r,'upgrade',[12,20]);assert.equal(state(r).notice,11);await r.close();
  });
  await test('an exhausted extractor releases incoming miners and ordinary assignment reaches the next mine',async()=>{
    const r=await mine(fresh),w=state(r),starter=w.buildings[0];leaveReserve(w,starter,0);
    const north=fixtureMine(w,9,13);w.surveys.unshift({...at(w,12,13),radius:10});
    for(let i=0;i<3;i++)setWorker(w,i,{x:12,y:20});setWorker(w,0,{x:12,y:20,job:9,target:starter.id});
    await restoreColony(r,w);await advance(r,2);
    assert.ok(state(r).bots.every(bot=>bot.target!==starter.id));
    assert.ok(state(r).bots.some(bot=>bot.target===north.id&&[8,9].includes(bot.job)));
    await advance(r,160);assert.ok(state(r).produced>w.produced);assert.equal(reserve(state(r),starter).remaining,0);await r.close();
  });
  await test('last-unit production releases the loose cache without stealing a paid local construction kit',async()=>{
    const r=await mine(fresh,3),w=state(r),site=w.buildings[0];withdrawReserves(w,50);site.stock=50;
    w.spent+=w.ore;w.ore=0;leaveReserve(w,site,3);w.tick=9;w.lastRevealTick=-100;
    for(let i=0;i<3;i++)setWorker(w,i,{x:12,y:20,job:8,target:site.id});
    await restoreColony(r,w);await call(r,'observe',[13,20]);const paid=state(r),project=paid.buildings.at(-1);
    assert.equal(project.source,site.id);assert.equal(paid.localSpent,w.localSpent+25);
    await advance(r);const exhausted=state(r);assert.equal(reserve(exhausted,site).remaining,0);
    assert.equal(exhausted.produced,paid.produced+3);assert.equal(exhausted.bots.find(bot=>bot.target===project.id).cargo,25);
    for(let i=0;i<100&&state(r).buildings.at(-1).stage!==2;i++)await advance(r);
    assert.equal(state(r).buildings.at(-1).stage,2);balance(state(r));await r.close();
  });
  await test('a full extractor buffer preserves underground reserves and pause freezes both ledgers',async()=>{
    const r=await mine(fresh),w=state(r),site=w.buildings[0];withdrawReserves(w,120);site.stock=120;
    leaveReserve(w,site,3);w.tick=9;w.lastRevealTick=-100;setWorker(w,0,{x:12,y:20,job:8,target:site.id});
    setWorker(w,1);setWorker(w,2);await restoreColony(r,w);await advance(r);
    assert.equal(state(r).produced,w.produced);assert.equal(reserve(state(r),site).remaining,3);
    await call(r,'pause-colony',[1]);const saved=r.snapshot(1);await r.restore(1,saved);await advance(r,20);
    assert.deepEqual(r.snapshot(1),saved);await r.close();
  });
  await test('extractor loss and rebuilding preserve the site reserve; depleted rebuilds and upgrades reject payment',async()=>{
    const r=await mine(fresh),w=state(r),site=w.buildings[0];leaveReserve(w,site,100);site.hp=1;w.tick=9;w.lastRevealTick=-100;
    for(let i=0;i<3;i++)setWorker(w,i);
    w.enemies.push({id:w.nextId++,...pixelAt(w,12,20),hp:80,kind:0,target:site.id,path:[]});
    await restoreColony(r,w);await advance(r);assert.equal(state(r).buildings.length,0);assert.equal(reserve(state(r),site).remaining,100);
    const quiet=state(r);quiet.enemies=[];await restoreColony(r,quiet);await call(r,'extract',[12,20]);
    assert.equal(state(r).notice,10);assert.equal(reserve(state(r),site).remaining,100);
    await call(r,'cancel-building',[12,20]);await advance(r,100);const depleted=state(r);leaveReserve(depleted,site,0);
    await restoreColony(r,depleted);const bank=state(r).ore;await call(r,'extract',[12,20]);
    assert.equal(state(r).notice,39);assert.equal(state(r).ore,bank);assert.equal(state(r).buildings.length,0);await r.close();
    const ready=await mine(fresh),last=state(ready);leaveReserve(last,last.buildings[0],0);await restoreColony(ready,last);
    await call(ready,'upgrade',[12,20]);assert.equal(state(ready).notice,39);assert.equal(state(ready).ore,last.ore);await ready.close();
  });
  await test('restore rejects missing, duplicated, relocated or replenished deposits and mismatched production',async()=>{
    const r=await fresh(),saved=r.snapshot(1);
    for(const edit of [w=>w.deposits.pop(),w=>w.deposits.push({...w.deposits[0]}),w=>w.deposits.reverse(),
      w=>w.deposits[0].cell++,w=>w.deposits[0].remaining=-1,w=>w.deposits[0].remaining++,w=>w.deposits[0].remaining--]) {
      const invalid=colony(saved);edit(invalid);await assert.rejects(()=>restoreColony(r,invalid),WebAssembly.RuntimeError);
      assert.deepEqual(r.snapshot(1),saved);
    }
    await r.close();
  });
}

if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};
  let count=0;await checkReserves(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);
}
