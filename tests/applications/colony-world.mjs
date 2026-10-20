// Real compiled reducers own generation, construction, combat and conservation.
// Seed-owned nest clearings supply bounded forward-artillery fixtures.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {MAP_WIDTH,MAP_HEIGHT,establishColony,colony,colonyBalance,restoreColony,at,setWorker,fixtureCall,pixelAt,routeCell, withdrawReserves} from './colony-state.mjs';

export async function checkWorld(test,fresh) {
  const state=r=>colony(r.snapshot(1));
  const call=(r,name,args=[])=>r.dispatch(1,r.command('match',name,args));
  async function advance(r,count=1) {
    for(let i=0;i<count;i++) {
      await call(r,'advance'); const world=state(r), balance=colonyBalance(world);
      assert.equal(world.ore,balance.bank); assert.equal(world.produced,balance.raw);
    }
  }
  async function build(r,name,x,y) {
    await call(r,name,[x,y]);
    for(let i=0;i<250&&!state(r).buildings.some(site=>site.x===x&&site.y===y&&site.stage===2);i++)await advance(r);
    const site=state(r).buildings.find(site=>site.x===x&&site.y===y); assert.equal(site.stage,2); return site;
  }
  await test('compact worlds place reproducible central hubs and begin with three live distant nests',async()=>{
    const r=await fresh(),spawns=new Set();
    for(const seed of [1,7,43,65535]) {
      await call(r,'new-run-seed',[seed]); const world=state(r),hub=world.surveys[0];
      assert.ok((hub.x-MAP_WIDTH/2)**2+(hub.y-MAP_HEIGHT/2)**2<=4**2); spawns.add(`${hub.x},${hub.y}`);
      assert.ok(world.bots.every(bot=>bot.x===hub.x*40+20&&bot.y===hub.y*40+20));
      assert.deepEqual(world.nests.map(nest=>nest.hp),[900,900,900]); assert.equal(world.lastRevealTick,-100); assert.equal(world.outcome,0);
      assert.equal(r.snapshot(1)[0],15);
      const again=state(r); await call(r,'new-run-seed',[seed]); again.runMarker++;
      assert.deepEqual(state(r),again);
    }
    assert.ok(spawns.size>=3); await r.close();
  });
  await test('surviving ten minutes does not win and the nest continues spawning later waves',async()=>{
    const r=await fresh(),world=state(r); world.started=true; world.tick=6000; await restoreColony(r,world); await advance(r);
    assert.equal(state(r).outcome,0); assert.deepEqual(state(r).nests.map(nest=>nest.hp),[900,900,900]);
    const later=state(r); later.tick=6749; await restoreColony(r,later); await advance(r);
    assert.ok(state(r).enemies.length>7); assert.equal(state(r).outcome,0);
    assert.ok(state(r).enemies.every(enemy=>state(r).nests.some(nest=>Math.abs(enemy.x-(nest.x*40+20))<=47&&Math.abs(enemy.y-(nest.y*40+20))<=87)));
    await r.close();
  });
  await test('forward artillery destroys the final nest and that victory survives save and pause',async()=>{
    const r=await fresh(),point=at(state(r),10,23); await build(r,'fortify',point.x,point.y);
    const world=state(r),site=world.buildings[0],nest=world.nests[0]; Object.assign(site,{kind:2,level:1,armed:0,x:nest.x,y:nest.y+4,cooldown:0}); world.rails=[];
    world.surveys.unshift({x:nest.x,y:nest.y+4,radius:6}); world.lastRevealTick=world.tick; world.nests.forEach(nest=>nest.hp=nest.id===0?6:0);
    await restoreColony(r,world); const bank=state(r).ore; await advance(r);
    assert.ok(state(r).nests.every(nest=>nest.hp===0)); assert.equal(state(r).outcome,3); assert.equal(state(r).ore,bank);
    assert.deepEqual([state(r).buildings[0].aimX,state(r).buildings[0].aimY],[nest.x*40+20,nest.y*40+20]);
    const won=r.snapshot(1); await r.restore(1,won); await advance(r,10); assert.deepEqual(r.snapshot(1),won); await r.close();
  });
  await test('the continuing wave respects the 128-enemy live cap',async()=>{
    const r=await fresh(),world=state(r); world.started=true; world.tick=449;
    for(let i=0;i<127;i++)world.enemies.push({id:world.nextId++,...pixelAt(world,20,22),hp:80,kind:0,target:0,path:[]});
    await restoreColony(r,world); await advance(r); assert.equal(state(r).enemies.length,128);
    const saved=r.snapshot(1); await r.restore(1,saved); assert.deepEqual(r.snapshot(1),saved); await r.close();
  });
  await test('light raiders travel faster than ordinary enemies and the heavy beast',async()=>{
    const r=await fresh(),world=state(r),start=pixelAt(world,20,22).x; world.started=true;
    for(const kind of [0,1,2])world.enemies.push({id:world.nextId++,x:start,y:pixelAt(world,20,22).y,
      hp:kind===2?1800:80,kind,target:0,path:[routeCell(world,21,22)]});
    await restoreColony(r,world); await advance(r);
    assert.deepEqual(state(r).enemies.map(enemy=>enemy.x-start),[5,7,5]);
    await r.close();
  });
  await test('long enemy routes beyond the old snapshot cap round-trip through the bounded real decoder',async()=>{
    const r=await fresh(),world=state(r); world.started=true; world.paused=1;
    const path=Array.from({length:1024},(_,i)=>routeCell(world,20+(i%2===0?1:0),22));
    for(let i=0;i<128;i++)world.enemies.push({id:world.nextId++,...pixelAt(world,20,22),hp:80,kind:0,target:0,path:[...path]});
    await restoreColony(r,world); const saved=r.snapshot(1); assert.ok(saved.length>65536&&saved.length<=1048576);
    await r.restore(1,saved); await advance(r); assert.deepEqual(r.snapshot(1),saved); await r.close();
  });
  await test('an expensive third extractor tier creates a third physical mining slot',async()=>{
    const r=await fresh(),point=at(state(r),12,20); await build(r,'extract',point.x,point.y);
    await call(r,'upgrade',[point.x,point.y]); assert.equal(state(r).buildings[0].level,2);
    await call(r,'upgrade',[point.x,point.y]); assert.equal(state(r).notice,7);
    const supplied=state(r); withdrawReserves(supplied, 200); supplied.delivered+=200; supplied.ore+=200;
    await restoreColony(r,supplied); const bank=state(r).ore; await call(r,'upgrade',[point.x,point.y]);
    assert.equal(state(r).ore,bank-160); assert.equal(state(r).buildings[0].level,3);
    const staffed=state(r); staffed.tick=9; staffed.lastRevealTick=-100;
    for(let i=0;i<3;i++)setWorker(staffed,i,{x:12,y:20,job:8,target:staffed.buildings[0].id});
    await restoreColony(r,staffed); await advance(r); assert.equal(state(r).produced,staffed.produced+6);
    const spent=state(r).spent; await call(r,'upgrade',[point.x,point.y]); assert.equal(state(r).notice,11); assert.equal(state(r).spent,spent); await r.close();
  });
  await test('fresh survey timing preserves old coverage and freezes with paused simulation',async()=>{
    const r=await fresh(),point=at(state(r),12,21); await build(r,'observe',point.x,point.y);
    const first=state(r); assert.equal(first.lastRevealTick,first.tick);
    assert.deepEqual(first.surveys[0],{x:point.x,y:point.y,radius:7});
    await call(r,'upgrade',[point.x,point.y]);
    for(let i=0;i<100&&state(r).buildings[0].level!==2;i++)await advance(r);
    const upgraded=state(r);
    assert.equal(upgraded.surveys[0].radius,10); assert.equal(upgraded.surveys[1].radius,7);
    await call(r,'pause-colony',[1]); const paused=r.snapshot(1); await advance(r,40); assert.deepEqual(r.snapshot(1),paused); await r.close();
  });
  await test('worker glimpses reveal two cells without granting a permanent construction route',async()=>{
    const r=await fresh(),world=state(r); setWorker(world,0,{x:8,y:13}); await restoreColony(r,world);
    await fixtureCall(r,'observe',[8,11]); assert.equal(state(r).notice,6); assert.equal(state(r).ore,160);
    await fixtureCall(r,'observe',[8,10]); assert.equal(state(r).notice,1); assert.equal(state(r).ore,160);
    assert.deepEqual(state(r).surveys,world.surveys); assert.equal(state(r).lastRevealTick,-100);
    const saved=r.snapshot(1); await r.restore(1,saved); assert.deepEqual(r.snapshot(1),saved); await r.close();
  });
  await test('a worker can rebuild a previously surveyed frontier after its observer is lost',async()=>{
    const r=await fresh(),world=state(r),point=at(world,12,14);
    world.surveys.unshift({...point,radius:7}); setWorker(world,0,{x:12,y:12}); await restoreColony(r,world);
    await fixtureCall(r,'observe',[12,11]); assert.equal(state(r).notice,10); assert.equal(state(r).ore,135);
    assert.deepEqual(state(r).surveys,world.surveys); assert.equal(state(r).lastRevealTick,-100);
    await fixtureCall(r,'cancel-building',[12,11]); const moved=state(r); setWorker(moved,0);
    await restoreColony(r,moved); await fixtureCall(r,'observe',[12,11]); assert.equal(state(r).notice,1);
    assert.deepEqual(state(r).surveys,world.surveys); await r.close();
  });
  await test('unseen paid construction releases pickup workers and resumes when worker vision returns',async()=>{
    const r=await fresh(),world=state(r); world.surveys.unshift({...at(world,12,14),radius:7});
    setWorker(world,0,{x:12,y:12}); await restoreColony(r,world); await fixtureCall(r,'observe',[12,11]);
    const queued=state(r),project=queued.buildings[0];
    for(let i=0;i<queued.bots.length;i++)setWorker(queued,i);
    setWorker(queued,0,{job:11,order:project.id}); await restoreColony(r,queued); await advance(r,10);
    assert.equal(state(r).buildings[0].stage,0); assert.equal(state(r).ore,135); assert.equal(state(r).spent,25);
    assert.ok(state(r).bots.every(bot=>bot.order===0&&bot.cargo===0));
    const seen=state(r); setWorker(seen,1,{x:12,y:12}); await restoreColony(r,seen); await advance(r);
    assert.equal(state(r).buildings[0].stage,1); assert.equal(state(r).bots.find(bot=>bot.job===3).cargo,25);
    const carried=state(r); setWorker(carried,1); await restoreColony(r,carried);
    for(let i=0;i<150&&state(r).buildings[0].stage!==2;i++)await advance(r);
    assert.equal(state(r).buildings[0].stage,2); assert.equal(state(r).spent,25); await r.close();
  });
  await test('world decoding rejects impossible nest outcomes and future reveal timing',async()=>{
    const r=await fresh(),saved=r.snapshot(1);
    for(const edit of [world=>world.nests[0].hp=901,world=>world.lastRevealTick=world.tick+1,
      world=>world.outcome=2,world=>world.outcome=3,world=>world.nests.forEach(nest=>nest.hp=0)]) {
      const invalid=colony(saved); edit(invalid); await assert.rejects(()=>restoreColony(r,invalid),WebAssembly.RuntimeError);
      assert.deepEqual(r.snapshot(1),saved);
    }
    await r.close();
  });
}

if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json')));
  const bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return establishColony(r);};
  let count=0; await checkWorld(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);
  console.log(`${count} compact-world checks passed`);
}
