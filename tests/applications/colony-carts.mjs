// Worker paths and cargo remain authoritative while completed stations add speed.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {establishColony,colony,colonyBalance,restoreColony,fixtureCall,origin,pixelAt,routeCell,siteAt,setWorker,addEnemy, withdrawReserves} from './colony-state.mjs';

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
    const world=state(r); withdrawReserves(world, 300); world.delivered+=300; world.ore+=300; await restoreColony(r,world);
  }
  async function build(r,name,x,y) {
    await call(r,name,[x,y]); await until(r,world=>siteAt(world,x,y)?.stage===2); return siteAt(state(r),x,y);
  }
  async function upgrade(r,x,y) {
    const level=siteAt(state(r),x,y).level+1; await call(r,'upgrade',[x,y]);
    await until(r,world=>siteAt(world,x,y)?.level===level&&siteAt(world,x,y)?.stage===2);
  }
  await test('delivered tower upgrades retain sight and logistics while adding longer sight and faster carts',async()=>{
    const r=await fresh(); await fund(r); const tower=await build(r,'observe',12,22);
    const world=state(r); withdrawReserves(world, 16); world.buildings[0].stock=16; await restoreColony(r,world);
    const before=state(r); await call(r,'upgrade',[12,22]); const pending=state(r);
    assert.equal(pending.spent,before.spent+25); assert.equal(pending.buildings[0].level,1);
    assert.equal(pending.buildings[0].armed,0); assert.equal(pending.buildings[0].stock,16);
    assert.deepEqual(pending.rails,before.rails); assert.deepEqual(pending.surveys,before.surveys);
    await call(r,'pause-colony',[1]); const saved=r.snapshot(1); await r.restore(1,saved); await advance(r,20);
    assert.deepEqual(r.snapshot(1),saved); await call(r,'pause-colony',[0]);
    await until(r,world=>world.buildings[0].level===2); assert.equal(state(r).buildings[0].armed,0);
    await call(r,'upgrade',[12,22]); assert.equal(state(r).buildings[0].level,2); assert.equal(state(r).buildings[0].armed,0);
    await until(r,world=>world.buildings[0].level===3); assert.equal(state(r).buildings[0].armed,0);
    assert.equal(state(r).buildings[0].id,tower.id); assert.equal(state(r).spent,75);
    await call(r,'upgrade',[12,22]); assert.equal(state(r).notice,11); assert.equal(state(r).spent,75); await r.close();
  });
  await test('cancelling or losing an artillery upgrade retains its gun and accounts for one kit',async()=>{
    const r=await fresh(); await fund(r); await build(r,'fortify',12,22);
    assert.equal(state(r).buildings[0].kind,2); assert.equal(state(r).buildings[0].level,1);
    const bank=state(r).ore; await call(r,'upgrade',[12,22]); await until(r,world=>world.buildings[0].stage===5);
    await call(r,'cancel-building',[12,22]); assert.equal(state(r).buildings[0].kind,2);
    await until(r,world=>world.ore===bank); assert.equal(state(r).spent,50);
    await call(r,'upgrade',[12,22]); await until(r,world=>world.buildings[0].stage===5);
    const world=state(r),index=world.bots.findIndex(bot=>bot.job===3),target=world.buildings[0].id;
    for(let i=0;i<world.bots.length;i++)if(i!==index)setWorker(world,i);
    setWorker(world,index,{x:12,y:22,job:7,target,cargo:25,timer:5,hp:7}); world.tick=9; world.lastRevealTick=-100;
    world.buildings[0].cooldown=8;
    await restoreColony(r,world); await addEnemy(r,{x:12,y:22}); await advance(r);
    assert.equal(state(r).casualties,1); assert.equal(state(r).buildings[0].stage,2);
    assert.equal(state(r).buildings[0].level,1); assert.equal(state(r).buildings[0].kind,2);
    assert.equal(state(r).spent,75); assert.equal(state(r).ore,bank-25); await r.close();
  });
  await test('artillery keeps firing through both delivered upgrades and never becomes a tower or cart station',async()=>{
    const r=await fresh(); await fund(r); const gun=await build(r,'fortify',12,22);
    for(const level of [2,3]) {
      const cooled=state(r); cooled.buildings[0].cooldown=0; await restoreColony(r,cooled);
      await call(r,'upgrade',[12,22]); const pending=state(r);
      assert.equal(pending.buildings[0].kind,2); assert.equal(pending.buildings[0].level,level-1);
      assert.ok(pending.buildings[0].stage>=4); assert.deepEqual(pending.rails,[]);
      await addEnemy(r,{x:14,y:22,hp:500}); await advance(r);
      assert.ok(state(r).enemies[0].hp<500); assert.equal(state(r).buildings[0].cooldown,8);
      const quiet=state(r); quiet.enemies=[]; await restoreColony(r,quiet);
      await until(r,world=>world.buildings[0].level===level&&world.buildings[0].stage===2);
      assert.equal(state(r).buildings[0].id,gun.id); assert.equal(state(r).buildings[0].kind,2);
      assert.deepEqual(state(r).rails,[]); assert.deepEqual(state(r).tracks,[]);
      const ready=state(r); ready.buildings[0].cooldown=0; await restoreColony(r,ready);
      await addEnemy(r,{x:14,y:22,hp:500}); await advance(r); assert.ok(state(r).enemies[0].hp<500);
      const clear=state(r); clear.enemies=[]; await restoreColony(r,clear); await r.restore(1,r.snapshot(1));
    }
    assert.equal(state(r).spent,100); await r.close();
  });
  await test('the former tower conversion command cannot create new hybrid buildings',async()=>{
    const r=await fresh(); await build(r,'observe',12,22); const before=state(r);
    await call(r,'arm-tower',[12,22]); assert.deepEqual(state(r),{...before,notice:11}); await r.close();
  });
  await test('saved unfinished hybrid artillery completes with its original gun and rail identity',async()=>{
    const r=await fresh(); await call(r,'fortify',[12,22]); const legacy=state(r);
    Object.assign(legacy.buildings[0],{kind:3,level:2,hp:90}); await restoreColony(r,legacy);
    const id=legacy.buildings[0].id; await r.restore(1,r.snapshot(1));
    await until(r,world=>world.buildings[0].stage===2);
    assert.equal(state(r).buildings[0].id,id); assert.equal(state(r).buildings[0].kind,3);
    assert.equal(state(r).buildings[0].level,2); assert.equal(state(r).buildings[0].armed,1);
    assert.equal(state(r).rails[0].source,id); assert.equal(state(r).spent,50); await r.close();
  });
  await test('every tower supplies carts and each upgrade doubles speed using the slower endpoint',async()=>{
    const r=await fresh();await fund(r);await build(r,'observe',12,22);await build(r,'observe',16,22);
    async function loaded() {
      const world=state(r);withdrawReserves(world, 16);
      setWorker(world,0,{x:16,y:22,job:2,cargo:16,path:[12+22*48,8+22*48]});
      await restoreColony(r,world);return {x:world.bots[0].x,bank:world.ore};
    }
    for(const [parent,child,speed] of [[1,1,80],[2,1,80],[2,2,160],[3,2,160],[3,3,320]]) {
      while(siteAt(state(r),12,22).level<parent)await upgrade(r,12,22);
      while(siteAt(state(r),16,22).level<child)await upgrade(r,16,22);
      const before=await loaded();await advance(r);
      assert.equal(state(r).bots[0].x,before.x);assert.equal(state(r).bots[0].flight[0].speed,speed);
      assert.equal(state(r).bots[0].cargo,16);await advance(r,2);assert.ok(state(r).bots[0].x<before.x);
      await until(r,world=>world.bots[0].cargo===0);assert.equal(state(r).ore,before.bank+16);
      const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);
    }
    await r.close();
  });
  await test('worker assignment chooses a longer station route when its physical travel time is shorter',async()=>{
    const r=await fresh(); await fund(r); await build(r,'observe',12,22); await upgrade(r,12,22); await upgrade(r,12,22);
    await build(r,'extract',12,20); const world=state(r); world.bots.length=1; setWorker(world,0,{x:8,y:21});
    await restoreColony(r,world); await advance(r); const bot=state(r).bots[0];
    assert.equal(bot.job,9); assert.equal(bot.path[0],routeCell(world,8,22)); assert.equal(bot.path.length,4);
    await advance(r,21); assert.deepEqual([state(r).bots[0].x,state(r).bots[0].y],Object.values(pixelAt(world,12,20)));
    await r.close();
  });
  await test('straight aerial freight spans leave intermediate ground available for construction',async()=>{
    const r=await fresh();await fund(r);const tower=await build(r,'observe',12,22);
    const before=state(r),rail=before.rails.find(rail=>rail.source===tower.id);
    assert.deepEqual(rail.path,[routeCell(before,12,22),routeCell(before,8,22)]);
    await build(r,'fortify',10,22);assert.equal(siteAt(state(r),10,22).kind,2);
    assert.deepEqual(state(r).rails.find(link=>link.source===tower.id).path,rail.path);
    const freight=state(r);withdrawReserves(freight,16);freight.rails[0].cargo=16;
    await restoreColony(r,freight);await until(r,value=>value.delivered===freight.delivered+16);
    assert.equal(state(r).lostOre,0);await r.restore(1,r.snapshot(1));await r.close();
  });
  await test('destroyed stations remove their light paths while source freight is lost once and workers dismount',async()=>{
    const r=await fresh(); await fund(r); await build(r,'observe',12,22); await upgrade(r,12,22); await upgrade(r,12,22);
    const world=state(r),tracks=[...world.tracks]; assert.equal(tracks.length,0);
    world.buildings[0].hp=7; world.rails[0].cargo=16; withdrawReserves(world, 16); world.tick=9; world.lastRevealTick=-100;
    for(let i=0;i<world.bots.length;i++)setWorker(world,i);
    await restoreColony(r,world); await addEnemy(r,{x:12,y:22}); await advance(r);
    assert.equal(state(r).buildings.length,0); assert.equal(state(r).rails.length,0); assert.equal(state(r).lostOre,16);
    assert.deepEqual(state(r).tracks,tracks); const saved=r.snapshot(1); await r.restore(1,saved);
    const quiet=state(r); quiet.enemies=[]; withdrawReserves(quiet, 16);
    setWorker(quiet,0,{x:12,y:22,job:2,cargo:16,path:[11,10,9,8].map(x=>x+22*48)});
    await restoreColony(r,quiet); const start=state(r).bots[0].x; await advance(r); assert.equal(state(r).bots[0].x,start-8);
    await build(r,'fortify',11,22); assert.deepEqual(state(r).tracks,tracks);
    await build(r,'observe',12,22); assert.equal(state(r).lostOre,16);
    assert.deepEqual(state(r).tracks,[]);
    assert.deepEqual(state(r).rails[0].path,[routeCell(state(r),12,22),routeCell(state(r),8,22)]);
    await advance(r,50); assert.equal(state(r).lostOre,16);
    assert.equal(new Set(state(r).tracks.map(track=>Math.floor(track/32))).size,state(r).tracks.length);
    await r.close();
  });
  await test('unbuilt cancelled links leave no paths and relocation retains no station history',async()=>{
    const r=await fresh(); await call(r,'observe',[12,22]); assert.deepEqual(state(r).tracks,[]);
    await call(r,'cancel-building',[12,22]); assert.deepEqual(state(r).tracks,[]);
    await build(r,'observe',12,22); const before=state(r),old=routeCell(before,12,22);
    await call(r,'relocate-building',[12+22*48,13+22*48]); assert.equal(state(r).notice,21); await advance(r);
    assert.equal(siteAt(state(r),13,22)?.stage,2); assert.notEqual(state(r).rails[0].path[0],old);
    assert.deepEqual(state(r).tracks,[]); await call(r,'fortify',[12,22]); assert.equal(state(r).notice,10);
    await until(r,world=>siteAt(world,12,22)?.stage===2); await r.restore(1,r.snapshot(1)); await r.close();
  });
  await test('track decoding rejects duplicate cells, broken connections and out-of-map geometry',async()=>{
    const r=await fresh(); await build(r,'observe',12,22);
    const legacy=state(r),a=routeCell(legacy,8,22),b=a+1;
    legacy.tracks=[a*32+17,b*32+20]; await restoreColony(r,legacy); const saved=r.snapshot(1);
    for(const edit of [world=>world.tracks.push(world.tracks[0]), world=>{world.tracks[0]^=1;},
      world=>{world.tracks[0]=-1;}, world=>{world.tracks[0]=128*128*32+1;}]) {
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
  let count=0; await checkCarts(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);
  console.log(`${count} cart and track checks passed`);
}
