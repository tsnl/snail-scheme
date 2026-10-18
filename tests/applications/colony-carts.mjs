// Worker paths and cargo remain authoritative while completed stations add speed.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,colonyBalance,restoreColony,fixtureCall,origin,pixelAt,routeCell,siteAt,setWorker,addEnemy} from './colony-state.mjs';

export async function checkCarts(test,fresh) {
  const state=r=>colony(r.snapshot(1)),call=fixtureCall;
  async function advance(r,count=1) {
    for(let i=0;i<count;i++) {
      await call(r,'advance'); const world=state(r),balance=colonyBalance(world);
      assert.equal(world.ore,balance.bank); assert.equal(world.produced,balance.raw);
    }
  }
  async function until(r,predicate) {
    for(let i=0;i<500&&!predicate(state(r));i++)await advance(r);
    assert.ok(predicate(state(r)),'the physical construction or delivery completed');
  }
  async function fund(r) {
    const world=state(r); world.produced+=300; world.delivered+=300; world.ore+=300; await restoreColony(r,world);
  }
  async function build(r,name,x,y) {
    await call(r,name,[x,y]); await until(r,world=>siteAt(world,x,y)?.stage===2); return siteAt(state(r),x,y);
  }
  async function upgrade(r,x,y) {
    const level=siteAt(state(r),x,y).level+1; await call(r,'upgrade',[x,y]);
    await until(r,world=>siteAt(world,x,y)?.level===level&&siteAt(world,x,y)?.stage===2);
  }
  await test('delivered kits progress a sight tower into artillery and then replace its gun with a cart station',async()=>{
    const r=await fresh(); await fund(r); const tower=await build(r,'observe',12,22);
    const world=state(r); world.produced+=16; world.buildings[0].stock=16; await restoreColony(r,world);
    const before=state(r); await call(r,'upgrade',[12,22]); const pending=state(r);
    assert.equal(pending.spent,before.spent+25); assert.equal(pending.buildings[0].level,1);
    assert.equal(pending.buildings[0].armed,0); assert.equal(pending.buildings[0].stock,16);
    assert.deepEqual(pending.rails,before.rails); assert.deepEqual(pending.surveys,before.surveys);
    await call(r,'pause-colony',[1]); const saved=r.snapshot(1); await r.restore(1,saved); await advance(r,20);
    assert.deepEqual(r.snapshot(1),saved); await call(r,'pause-colony',[0]);
    await until(r,world=>world.buildings[0].level===2); assert.equal(state(r).buildings[0].armed,1);
    await call(r,'upgrade',[12,22]); assert.equal(state(r).buildings[0].level,2); assert.equal(state(r).buildings[0].armed,1);
    await until(r,world=>world.buildings[0].level===3); assert.equal(state(r).buildings[0].armed,0);
    assert.equal(state(r).buildings[0].id,tower.id); assert.equal(state(r).spent,75);
    await call(r,'upgrade',[12,22]); assert.equal(state(r).notice,11); assert.equal(state(r).spent,75); await r.close();
  });
  await test('cancelling or losing a carried station kit leaves the prior artillery and one material charge',async()=>{
    const r=await fresh(); await fund(r); await build(r,'fortify',12,22);
    assert.equal(state(r).buildings[0].kind,3); assert.equal(state(r).buildings[0].level,2);
    const bank=state(r).ore; await call(r,'upgrade',[12,22]); await until(r,world=>world.buildings[0].stage===5);
    await call(r,'cancel-building',[12,22]); assert.equal(state(r).buildings[0].armed,1);
    await until(r,world=>world.ore===bank); assert.equal(state(r).spent,50);
    await call(r,'upgrade',[12,22]); await until(r,world=>world.buildings[0].stage===5);
    const world=state(r),index=world.bots.findIndex(bot=>bot.job===3),target=world.buildings[0].id;
    for(let i=0;i<world.bots.length;i++)if(i!==index)setWorker(world,i);
    setWorker(world,index,{x:12,y:22,job:7,target,cargo:25,timer:5,hp:7}); world.tick=9; world.lastRevealTick=-100;
    await restoreColony(r,world); await addEnemy(r,{x:12,y:22}); await advance(r);
    assert.equal(state(r).casualties,1); assert.equal(state(r).buildings[0].stage,2);
    assert.equal(state(r).buildings[0].level,2); assert.equal(state(r).buildings[0].armed,1);
    assert.equal(state(r).spent,75); assert.equal(state(r).ore,bank-25); await r.close();
  });
  await test('both rail endpoints must be stations before loaded workers receive fivefold travel speed',async()=>{
    const r=await fresh(); await fund(r); await build(r,'fortify',12,22); await build(r,'observe',16,22);
    await upgrade(r,16,22); await upgrade(r,16,22);
    async function loaded() {
      const world=state(r); world.produced+=16;
      setWorker(world,0,{x:16,y:22,job:2,cargo:16,path:Array.from({length:8},(_,i)=>15-i+22*48)});
      await restoreColony(r,world); return world.bots[0].x;
    }
    const slow=await loaded(); await advance(r); assert.equal(state(r).bots[0].x,slow-8);
    const saved=r.snapshot(1); await r.restore(1,saved); assert.deepEqual(r.snapshot(1),saved);
    await until(r,world=>world.bots[0].cargo===0); await upgrade(r,12,22);
    const fast=await loaded(),bank=state(r).ore; await advance(r); assert.equal(state(r).bots[0].x,fast-40);
    await advance(r,7); assert.equal(state(r).bots[0].cargo,16); assert.equal(state(r).ore,bank);
    await advance(r); assert.equal(state(r).bots[0].cargo,0); assert.equal(state(r).ore,bank+16); await r.close();
  });
  await test('worker assignment chooses a longer station route when its physical travel time is shorter',async()=>{
    const r=await fresh(); await fund(r); await build(r,'observe',12,22); await upgrade(r,12,22); await upgrade(r,12,22);
    await build(r,'extract',12,20); const world=state(r); world.bots.length=1; setWorker(world,0,{x:8,y:21});
    await restoreColony(r,world); await advance(r); const bot=state(r).bots[0];
    assert.equal(bot.job,9); assert.equal(bot.path[0],routeCell(world,8,22)); assert.equal(bot.path.length,7);
    await advance(r,19); assert.deepEqual([state(r).bots[0].x,state(r).bots[0].y],Object.values(pixelAt(world,12,20)));
    await r.close();
  });
  await test('new rails avoid building footprints and reserve their interiors without charging rejected construction',async()=>{
    const r=await fresh(); await build(r,'build-wall',10,22); const tower=await build(r,'observe',12,22);
    const world=state(r),rail=world.rails.find(rail=>rail.source===tower.id),wall=routeCell(world,10,22);
    assert.ok(!rail.path.includes(wall)); const cell=rail.path[1],offset=origin(world);
    const x=cell%384-offset.x,y=Math.floor(cell/384)-offset.y,bank=world.ore;
    for(const action of ['observe','fortify','build-wall','extract']) {
      await call(r,action,[x,y]); assert.equal(state(r).notice,28); assert.equal(state(r).ore,bank);
      assert.equal(state(r).buildings.length,2);
    }
    await call(r,'relocate-building',[12+22*48,x+y*48]); assert.equal(state(r).notice,28);
    assert.equal(state(r).ore,bank); const saved=r.snapshot(1); await r.restore(1,saved);
    const invalid=colony(saved),moving=invalid.buildings.find(site=>site.id===tower.id);
    moving.moveX=cell%384; moving.moveY=Math.floor(cell/384); invalid.ore-=5; invalid.spent+=5;
    await assert.rejects(()=>restoreColony(r,invalid),WebAssembly.RuntimeError);
    await call(r,'pause-colony',[1]); await call(r,'relocate-building',[12+22*48,13+22*48]);
    assert.equal(state(r).notice,21); await call(r,'observe',[14,22]); assert.equal(state(r).notice,10);
    assert.ok(!state(r).rails.at(-1).path.includes(routeCell(world,13,22)));
    await r.restore(1,r.snapshot(1)); await r.close();
  });
  await test('destroyed stations leave physical rails while their freight is lost once and workers dismount',async()=>{
    const r=await fresh(); await fund(r); await build(r,'observe',12,22); await upgrade(r,12,22); await upgrade(r,12,22);
    const world=state(r),tracks=[...world.tracks]; assert.equal(tracks.length,5);
    world.buildings[0].hp=7; world.rails[0].cargo=16; world.produced+=16; world.tick=9; world.lastRevealTick=-100;
    for(let i=0;i<world.bots.length;i++)setWorker(world,i);
    await restoreColony(r,world); await addEnemy(r,{x:12,y:22}); await advance(r);
    assert.equal(state(r).buildings.length,0); assert.equal(state(r).rails.length,0); assert.equal(state(r).lostOre,16);
    assert.deepEqual(state(r).tracks,tracks); const saved=r.snapshot(1); await r.restore(1,saved);
    const quiet=state(r); quiet.enemies=[]; quiet.produced+=16;
    setWorker(quiet,0,{x:12,y:22,job:2,cargo:16,path:[11,10,9,8].map(x=>x+22*48)});
    await restoreColony(r,quiet); const start=state(r).bots[0].x; await advance(r); assert.equal(state(r).bots[0].x,start-8);
    const bank=state(r).ore; await call(r,'build-wall',[11,22]); assert.equal(state(r).notice,28); assert.equal(state(r).ore,bank);
    await build(r,'observe',12,22); assert.deepEqual(state(r).tracks,tracks); assert.equal(state(r).lostOre,16);
    await advance(r,50); assert.equal(state(r).lostOre,16); assert.equal(new Set(state(r).tracks.map(track=>Math.floor(track/32))).size,tracks.length);
    await r.close();
  });
  await test('unbuilt cancelled links leave no rails and relocation preserves a rebuildable old station',async()=>{
    const r=await fresh(); await call(r,'observe',[12,22]); assert.deepEqual(state(r).tracks,[]);
    await call(r,'cancel-building',[12,22]); assert.deepEqual(state(r).tracks,[]);
    await build(r,'observe',12,22); const before=state(r),old=routeCell(before,12,22);
    await call(r,'relocate-building',[12+22*48,13+22*48]); assert.equal(state(r).notice,21); await advance(r);
    assert.equal(siteAt(state(r),13,22)?.stage,2); assert.ok(!state(r).rails[0].path.includes(old));
    const oldTrack=state(r).tracks.find(track=>Math.floor(track/32)===old); assert.ok((oldTrack&16)!==0);
    assert.ok(state(r).tracks.length>before.tracks.length); await call(r,'build-wall',[12,22]); assert.equal(state(r).notice,10);
    await until(r,world=>siteAt(world,12,22)?.stage===2); await r.restore(1,r.snapshot(1)); await r.close();
  });
  await test('track decoding rejects duplicate cells, broken connections and out-of-map geometry',async()=>{
    const r=await fresh(); await build(r,'observe',12,22); const saved=r.snapshot(1);
    for(const edit of [world=>world.tracks.push(world.tracks[0]), world=>{world.tracks[0]^=1;},
      world=>{world.tracks[0]=-1;}, world=>{world.tracks[0]=384*288*32+1;}]) {
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
  let count=0; await checkCarts(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);
  console.log(`${count} cart and track checks passed`);
}
