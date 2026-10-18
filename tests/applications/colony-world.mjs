// Real compiled reducers own generation, construction, combat and conservation.
// Seed 1's nest clearing at (199,24) supplies a bounded forward-artillery fixture.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,colonyBalance,restoreColony,at,setWorker,fixtureCall,pixelAt,routeCell} from './colony-state.mjs';

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
  await test('large worlds place reproducible central hubs and begin with a live distant nest',async()=>{
    const r=await fresh(),spawns=new Set();
    for(const seed of [1,7,43,65535]) {
      await call(r,'new-run-seed',[seed]); const world=state(r),hub=world.surveys[0];
      assert.ok((hub.x-192)**2+(hub.y-144)**2<=24**2); spawns.add(`${hub.x},${hub.y}`);
      assert.ok(world.bots.every(bot=>bot.x===hub.x*40+20&&bot.y===hub.y*40+20));
      assert.equal(world.nestHp,1500); assert.equal(world.lastRevealTick,-100); assert.equal(world.outcome,0);
      assert.equal(r.snapshot(1)[0],10);
      const again=state(r); await call(r,'new-run-seed',[seed]); again.runMarker++;
      assert.deepEqual(state(r),again);
    }
    assert.ok(spawns.size>=3); await r.close();
  });
  await test('surviving the old finale does not win and the nest continues spawning later waves',async()=>{
    const r=await fresh(),world=state(r); world.started=true; world.tick=4800; await restoreColony(r,world); await advance(r);
    assert.equal(state(r).outcome,0); assert.equal(state(r).nestHp,1500);
    const later=state(r); later.tick=11699; await restoreColony(r,later); await advance(r);
    assert.ok(state(r).enemies.length>7); assert.equal(state(r).outcome,0);
    assert.ok(state(r).enemies.every(enemy=>Math.abs(enemy.x-(199*40+20))<=47&&Math.abs(enemy.y-(24*40+20))<=87));
    await r.close();
  });
  await test('forward artillery destroys the nest and that victory survives save and pause',async()=>{
    const r=await fresh(),point=at(state(r),10,23); await build(r,'fortify',point.x,point.y);
    const world=state(r),site=world.buildings[0]; Object.assign(site,{kind:2,level:1,armed:0,x:199,y:28,cooldown:0}); world.rails=[];
    world.surveys.unshift({x:199,y:28,radius:4}); world.lastRevealTick=world.tick; world.nestHp=6;
    await restoreColony(r,world); const bank=state(r).ore; await advance(r);
    assert.equal(state(r).nestHp,0); assert.equal(state(r).outcome,3); assert.equal(state(r).ore,bank);
    assert.deepEqual([state(r).buildings[0].aimX,state(r).buildings[0].aimY],[199*40+20,24*40+20]);
    const won=r.snapshot(1); await r.restore(1,won); await advance(r,10); assert.deepEqual(r.snapshot(1),won); await r.close();
  });
  await test('the continuing wave respects the 128-enemy live cap',async()=>{
    const r=await fresh(),world=state(r); world.started=true; world.tick=899;
    for(let i=0;i<127;i++)world.enemies.push({id:world.nextId++,x:199*40+20,y:24*40+20,hp:80,kind:0,target:0,path:[]});
    await restoreColony(r,world); await advance(r); assert.equal(state(r).enemies.length,128);
    const saved=r.snapshot(1); await r.restore(1,saved); assert.deepEqual(r.snapshot(1),saved); await r.close();
  });
  await test('light raiders travel faster than ordinary enemies and the heavy beast',async()=>{
    const r=await fresh(),world=state(r),start=199*40+20; world.started=true;
    for(const kind of [0,1,2])world.enemies.push({id:world.nextId++,x:start,y:24*40+20,
      hp:kind===2?1800:80,kind,target:0,path:[200+24*384]});
    await restoreColony(r,world); await advance(r);
    assert.deepEqual(state(r).enemies.map(enemy=>enemy.x-start),[5,7,5]);
    await r.close();
  });
  await test('long enemy routes beyond the old snapshot cap round-trip through the bounded real decoder',async()=>{
    const r=await fresh(),world=state(r); world.started=true; world.paused=1;
    const path=Array.from({length:1024},(_,i)=>199+(i%2===0?1:0)+24*384);
    for(let i=0;i<128;i++)world.enemies.push({id:world.nextId++,x:199*40+20,y:24*40+20,hp:80,kind:0,target:0,path:[...path]});
    await restoreColony(r,world); const saved=r.snapshot(1); assert.ok(saved.length>65536&&saved.length<=1048576);
    await r.restore(1,saved); await advance(r); assert.deepEqual(r.snapshot(1),saved); await r.close();
  });
  await test('houses require worker delivery and remain ordinary attackable structures without extending sight',async()=>{
    const r=await fresh(),point=at(state(r),10,22); await call(r,'build-house',[point.x,point.y]);
    assert.equal(state(r).ore,152); assert.notEqual(state(r).buildings[0].stage,2); await advance(r);
    assert.equal(state(r).bots.find(bot=>bot.job===3).cargo,8);
    for(let i=0;i<40&&state(r).buildings[0].stage!==2;i++)await advance(r);
    const world=state(r); assert.equal(world.buildings[0].hp,220); assert.equal(world.surveys.length,1);
    assert.equal(world.lastRevealTick,-100); world.tick=0;
    for(let i=0;i<world.bots.length;i++)setWorker(world,i);
    const vanishedTarget=world.nextId++;
    world.enemies.push({id:world.nextId++,...pixelAt(world,14,22),hp:80,kind:0,target:vanishedTarget,path:[]});
    await restoreColony(r,world); await advance(r);
    assert.ok(state(r).enemies[0].path.includes(routeCell(world,10,22)),'enemy chooses a direct route past the house');
    await advance(r,29); assert.equal(state(r).enemies[0].y,pixelAt(world,14,22).y);
    assert.equal(state(r).buildings[0].hp,213); assert.equal(state(r).hull,300);
    assert.ok(state(r).bots.every(bot=>bot.hp===14)); assert.equal(state(r).alerts[0].kind,5); await r.close();
  });
  await test('an expensive third extractor tier creates a third physical mining slot',async()=>{
    const r=await fresh(),point=at(state(r),12,20); await build(r,'extract',point.x,point.y);
    await call(r,'upgrade',[point.x,point.y]); assert.equal(state(r).buildings[0].level,2);
    await call(r,'upgrade',[point.x,point.y]); assert.equal(state(r).notice,7);
    const supplied=state(r); supplied.produced+=200; supplied.delivered+=200; supplied.ore+=200;
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
    for(const edit of [world=>world.nestHp=1501,world=>world.lastRevealTick=world.tick+1,
      world=>world.outcome=2,world=>world.outcome=3,world=>world.nestHp=0]) {
      const invalid=colony(saved); edit(invalid); await assert.rejects(()=>restoreColony(r,invalid),WebAssembly.RuntimeError);
      assert.deepEqual(r.snapshot(1),saved);
    }
    await r.close();
  });
}

if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json')));
  const bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};
  let count=0; await checkWorld(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);
  console.log(`${count} large-world checks passed`);
}
