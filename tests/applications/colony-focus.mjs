// Exercise the compiled Scheme authority; fixtures only establish bounded state.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve, join} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {checkColony} from './colony.mjs';
import {checkEncounters} from './colony-encounters.mjs';
import {checkLogistics} from './colony-logistics.mjs';
import {colony, colonyBalance, restoreColony, restoreClient, client, setWorker, addEnemy} from './colony-state.mjs';

export async function checkFocus(test, fresh, call) {
  const state = r => colony(r.snapshot(1));
  function balanced(r) {
    const world = state(r), totals = colonyBalance(world);
    assert.equal(world.ore, totals.bank, 'bank conservation');
    assert.equal(world.produced, totals.raw, 'mined material conservation');
  }
  async function advance(r, count = 1) {
    for (let i = 0; i < count; i++) { await call(r, 'advance'); balanced(r); }
  }
  async function until(r, predicate, limit = 600) {
    for (let i = 0; i < limit && !predicate(state(r)); i++) await advance(r);
    assert.ok(predicate(state(r)), 'bounded task completes');
  }
  async function build(r, kind, x, y) {
    await call(r, kind, [x,y]);
    await until(r, w => w.buildings.some(b => b.x === x && b.y === y && b.stage === 2));
    return state(r).buildings.find(b => b.x === x && b.y === y);
  }
  async function mineStock(r, stock = 50, bank = 0) {
    const mine = await build(r, 'extract', 12, 20), world = state(r);
    const value = world.buildings.find(b => b.id === mine.id);
    world.produced += stock - value.stock; value.stock = stock;
    world.spent += world.ore - bank; world.ore = bank;
    setWorker(world, 0, {x:12,y:20}); setWorker(world, 1); setWorker(world, 2);
    await restoreColony(r, world); return mine.id;
  }
  const move = (r,x,y,a,b) => call(r,'relocate-building',[x+y*48,a+b*48]);

  await test('manual is the default and idle colonies do not spend or repair', async () => {
    const r = await fresh(), world = state(r); world.hull = 250;
    await restoreColony(r, world); await advance(r, 100);
    assert.equal(state(r).focus, 0); assert.equal(state(r).ore, 160);
    assert.equal(state(r).hull, 250); assert.equal(state(r).buildings.length, 0);
    assert.ok(!r.manifest?.applications?.some(a => a.handlers.some(h => h.binding === 'repair')));
    await r.close();
  });
  await test('local extractor supply picks the nearby empty worker without charging the bank', async () => {
    const r = await fresh(), source = await mineStock(r);
    await call(r, 'fortify', [13,20]); const reserved = state(r), project = reserved.buildings.at(-1);
    assert.equal(project.source, source); assert.equal(project.stage, 3);
    assert.equal(reserved.bots[0].order, project.id); assert.equal(reserved.bots[0].path.length, 0);
    assert.equal(reserved.ore, 0); assert.equal(reserved.localSpent, 50);
    assert.equal(reserved.buildings[0].stock, 0); balanced(r);
    await advance(r); assert.equal(state(r).bots[0].source, source);
    assert.equal(state(r).bots[0].job, 3); assert.equal(state(r).bots[0].x, 500);
    await until(r, w => w.buildings.at(-1).stage === 2, 12);
    assert.equal(state(r).ore, 0); assert.equal(state(r).localSpent, 50); await r.close();
  });
  await test('ordinary mining retains one useful construction cache and releases it when hub ore is low', async () => {
    const r=await fresh(); await build(r,'extract',12,20);
    await until(r,w=>w.delivered>=16 && w.buildings[0].stock>=50,500);
    const before=state(r); assert.ok(before.delivered>=16); assert.equal(before.localSpent,0);
    await call(r,'fortify',[13,20]); assert.equal(state(r).buildings.at(-1).source,before.buildings[0].id);
    assert.equal(state(r).ore,before.ore); assert.equal(state(r).localSpent,50);
    await until(r,w=>w.buildings.at(-1).stage===2);
    await until(r,w=>w.buildings[0].stock>=50,500);
    const low=state(r); low.spent+=low.ore-39; low.ore=39;
    setWorker(low,0,{x:12,y:20,job:8,target:low.buildings[0].id});
    setWorker(low,1,{x:12,y:20}); setWorker(low,2,{job:6,timer:30});
    await restoreColony(r,low); await advance(r,2);
    assert.ok(state(r).bots.some(b=>b.job===2&&b.cargo===16));
    assert.ok(state(r).buildings[0].stock<50); balanced(r); await r.close();
  });
  await test('uncollected local kits count against mine capacity and cancel back to the same source', async () => {
    const r = await fresh(); await mineStock(r,120,0); await call(r,'fortify',[13,20]);
    const world = state(r); const project = world.buildings.at(-1);
    setWorker(world,0,{x:8,y:22,job:10,order:project.id});
    setWorker(world,1,{x:12,y:20,job:8,target:world.buildings[0].id});
    setWorker(world,2,{job:1,target:world.buildings[0].id,path:[1065,1066,1067,1068,1020,972]});
    world.tick = 9; await restoreColony(r,world);
    await advance(r); assert.equal(state(r).buildings[0].stock,70);
    await call(r,'cancel-building',[13,20]); balanced(r);
    assert.equal(state(r).buildings[0].stock,120); assert.equal(state(r).localSpent,0);
    assert.equal(state(r).ore,0); await call(r,'cancel-building',[13,20]);
    assert.equal(state(r).buildings[0].stock,120); await r.close();
  });
  await test('carried local cancellation persists and refunds only after physical hub arrival', async () => {
    const r = await fresh(); await mineStock(r); await call(r,'fortify',[13,20]); await advance(r);
    await call(r,'cancel-building',[13,20]); assert.equal(state(r).ore,0);
    await call(r,'pause-colony',[1]); const snapshot = r.snapshot(1);
    await r.restore(1,snapshot); await advance(r,10); assert.deepEqual(r.snapshot(1),snapshot);
    await call(r,'pause-colony',[0]); await until(r,w=>w.localSpent === 0);
    assert.ok(state(r).delivered >= 50); assert.ok(state(r).ore >= 50);
    const returned = state(r); assert.equal(returned.spent,160); await r.close();
  });
  await test('hub supply chooses total completion time, then retries waiting orders', async () => {
    const r = await fresh(), world = state(r);
    setWorker(world,0,{x:13,y:20}); setWorker(world,1); setWorker(world,2,{x:14,y:20});
    await restoreColony(r,world); await call(r,'observe',[13,21]);
    assert.equal(state(r).bots.find(b=>b.order>0).id,2,'worker at hub beats worker by the site');
    await call(r,'fortify',[14,21]); assert.equal(state(r).buildings.at(-1).stage,0);
    await until(r,w=>w.buildings.every(b=>b.stage===2)); balanced(r); await r.close();
  });
  await test('visible enemies behind rock receive no direct artillery fire', async () => {
    const r = await fresh(); await build(r,'observe',12,14); await build(r,'observe',12,8);
    const gun = await build(r,'fortify',6,9); await addEnemy(r,{x:6,y:11,hp:80});
    await advance(r); assert.equal(state(r).enemies[0].hp,80);
    assert.equal(state(r).buildings.find(b=>b.id===gun.id).cooldown,0);
    const world = state(r); world.enemies[0].x=7*40+20; world.enemies[0].y=9*40+20;
    await restoreColony(r,world); await advance(r); assert.equal(state(r).enemies[0].hp,60); await r.close();
  });
  await test('queued tower movement drains freight, preserves value and survives pause/reload', async () => {
    const r = await fresh(), parent = await build(r,'observe',12,21), child = await build(r,'observe',16,21);
    const world=state(r); world.produced+=48; world.buildings[0].stock=16; world.buildings[0].hp=61;
    world.rails.find(l=>l.source===child.id).cargo=32;
    await restoreColony(r,world); const before=state(r).ore;
    await move(r,12,21,12,22); assert.equal(state(r).ore,before-5);
    assert.equal(state(r).buildings[0].moveY,22); await call(r,'pause-colony',[1]);
    const snapshot=r.snapshot(1); await r.restore(1,snapshot); await advance(r,10); assert.deepEqual(r.snapshot(1),snapshot);
    await call(r,'pause-colony',[0]); await until(r,w=>w.buildings[0].y===22);
    const moved=state(r); assert.equal(moved.buildings[0].id,parent.id); assert.equal(moved.buildings[0].hp,61);
    assert.equal(moved.buildings[0].moveX,-1); assert.equal(moved.delivered,48);
    assert.ok(moved.rails.every(l=>l.cargo===0)); balanced(r); await r.close();
  });
  await test('failed moves cost nothing and pending moves cancel exactly once', async () => {
    const r = await fresh(); await build(r,'observe',12,21); const before=state(r).ore;
    await move(r,12,21,16,21); assert.equal(state(r).ore,before); assert.equal(state(r).notice,25);
    await call(r,'pause-colony',[1]); await move(r,12,21,12,22); assert.equal(state(r).ore,before-5);
    await call(r,'cancel-building',[12,21]); assert.equal(state(r).ore,before);
    await call(r,'cancel-building',[12,21]); assert.equal(state(r).ore,before); await r.close();
  });
  await test('moving a loaded three-tower chain drains in either request order', async () => {
    for(const order of [[0,1,2],[2,1,0]]) {
      const r=await fresh(); for(const x of [12,16,20]) await build(r,'observe',x,21);
      const world=state(r); world.produced+=96;
      for(const b of world.buildings)b.stock=16;
      for(const rail of world.rails)rail.cargo=16;
      const identities=world.buildings.map(b=>b.id),parents=world.rails.map(l=>l.parent);
      await restoreColony(r,world); await call(r,'pause-colony',[1]);
      for(const index of order)await move(r,world.buildings[index].x,21,world.buildings[index].x,22);
      const saved=r.snapshot(1); await r.restore(1,saved); await advance(r,5); assert.deepEqual(r.snapshot(1),saved);
      await call(r,'pause-colony',[0]); let parentMovedBeforeChildDrained=false;
      for(let tick=0;tick<500&&!state(r).buildings.every(b=>b.y===22);tick++) {
        await advance(r); const current=state(r);
        parentMovedBeforeChildDrained ||= current.buildings[0].y===22 && current.buildings[1].stock>0;
      }
      const moved=state(r); assert.deepEqual(moved.buildings.map(b=>b.id),identities);
      assert.ok(parentMovedBeforeChildDrained); assert.ok(moved.buildings.every(b=>b.y===22));
      assert.deepEqual(moved.rails.map(l=>l.parent),parents);
      assert.ok(moved.buildings.every(b=>b.stock===0&&b.moveX===-1));
      await until(r,w=>w.delivered===96); balanced(r); await r.close();
    }
  });
  await test('move input outside the map cannot wrap into a different row', async () => {
    const r=await fresh(), local=(name,args=[])=>r.dispatch(2,r.command('client',name,args));
    const value=client(r.snapshot(2)); value.originX=0; value.originY=22;
    value.pointX=860; value.pointY=340; value.cameraX=1080000; value.cameraY=560000;
    await restoreClient(r,value); const effects=(await local('confirm')).effects;
    assert.deepEqual(r.effectCommand(effects[0]),r.command('match','relocate-building',[22*48,-1]));
    const before=state(r).ore; await r.dispatch(1,r.effectCommand(effects[0])); assert.equal(state(r).ore,before);
    await r.close();
  });
  await test('local tower kits are exclusive against rail loading', async () => {
    const r=await fresh(), tower=await build(r,'observe',12,21), world=state(r);
    world.buildings[0].stock=50; world.produced+=50; world.spent+=world.ore; world.ore=0;
    setWorker(world,0,{x:12,y:21}); setWorker(world,1); setWorker(world,2); await restoreColony(r,world);
    await call(r,'fortify',[13,21]); assert.equal(state(r).buildings.at(-1).source,tower.id);
    await advance(r); assert.equal(state(r).rails[0].cargo,0); assert.equal(state(r).bots[0].cargo,50);
    balanced(r); await r.close();
  });
  await test('source loss destroys only uncollected local kits and clears their claims', async () => {
    const r=await fresh(); await mineStock(r); await call(r,'fortify',[13,20]);
    const world=state(r), project=world.buildings.at(-1); world.tick=9; world.buildings[0].hp=7;
    setWorker(world,0,{job:10,order:project.id}); setWorker(world,1,{job:6,timer:30}); setWorker(world,2,{job:6,timer:30});
    await restoreColony(r,world); await addEnemy(r,{x:12,y:20}); await advance(r);
    assert.equal(state(r).buildings.length,0); assert.equal(state(r).localSpent,50);
    assert.equal(state(r).ore,0); assert.ok(state(r).bots.every(b=>b.order===0)); balanced(r); await r.close();
  });
  await test('a local carrier survives source loss and retains its paid provenance', async () => {
    const r=await fresh(), source=await mineStock(r); await call(r,'fortify',[13,20]); await advance(r);
    const world=state(r), project=world.buildings.at(-1); world.tick=9; world.buildings[0].hp=7;
    setWorker(world,0,{x:16,y:20,job:3,target:project.id,cargo:50,source,path:[975,974,973]});
    await restoreColony(r,world); await addEnemy(r,{x:12,y:20}); await advance(r);
    assert.equal(state(r).buildings.length,1); assert.equal(state(r).bots[0].source,source);
    const clear=state(r); clear.enemies=[]; await restoreColony(r,clear);
    await until(r,w=>w.buildings[0].stage===2); assert.equal(state(r).localSpent,50); balanced(r); await r.close();
  });
  await test('fleeing with local supplies converts a returned live kit without minting ore', async () => {
    const r=await fresh(), source=await mineStock(r); await call(r,'fortify',[13,20]); await advance(r);
    const world=state(r); world.tick=1; await restoreColony(r,world); await addEnemy(r,{x:12,y:20});
    await advance(r); assert.equal(state(r).bots[0].job,7); assert.equal(state(r).bots[0].source,source);
    const clear=state(r); clear.enemies=[]; await restoreColony(r,clear);
    await until(r,w=>w.localSpent===0); assert.equal(state(r).spent,210);
    assert.equal(state(r).ore,state(r).delivered-50); balanced(r); await r.close();
  });
  await test('an uncollected local reservation retreats home before returning to its actual source', async () => {
    const r=await fresh(),source=await mineStock(r); await call(r,'fortify',[13,20]);
    await addEnemy(r,{x:12,y:20}); await advance(r);
    assert.equal(state(r).bots[0].job,7); assert.equal(state(r).bots[0].timer,11);
    const clear=state(r); clear.enemies=[]; await restoreColony(r,clear);
    await until(r,w=>w.buildings.at(-1).stage===2,250);
    assert.equal(state(r).localSpent,50); assert.equal(state(r).spent,210);
    assert.equal(state(r).buildings[0].id,source); balanced(r); await r.close();
  });
  await test('decoder rejects duplicate relocation destinations and unsupported local kit balances', async () => {
    const r=await fresh(); await build(r,'observe',12,21); await build(r,'observe',14,21);
    await call(r,'pause-colony',[1]); await move(r,12,21,13,21);
    const duplicate=state(r); duplicate.buildings[1].moveX=13; duplicate.buildings[1].moveY=21;
    duplicate.ore-=5; duplicate.spent+=5;
    await assert.rejects(()=>restoreColony(r,duplicate),WebAssembly.RuntimeError); await r.close();
    const local=await fresh(); await mineStock(local); await call(local,'fortify',[13,20]);
    const underfunded=state(local); underfunded.localSpent--; underfunded.spent--; underfunded.produced--;
    await assert.rejects(()=>restoreColony(local,underfunded),WebAssembly.RuntimeError); await local.close();
  });
  await test('local carrier death loses its kit once without counting it as loose ore loss', async () => {
    const r=await fresh(), source=await mineStock(r); await call(r,'fortify',[13,20]); await advance(r);
    const world=state(r); world.tick=9;
    setWorker(world,0,{x:12,y:20,job:7,target:world.buildings.at(-1).id,cargo:50,timer:5,hp:7,source});
    await restoreColony(r,world); await addEnemy(r,{x:12,y:20}); await advance(r);
    assert.equal(state(r).casualties,1); assert.equal(state(r).buildings.length,1);
    assert.equal(state(r).localSpent,50); assert.equal(state(r).lostOre,0); assert.equal(state(r).ore,0);
    balanced(r); await r.close();
  });
  await test('loaded workers with a destroyed depot reroute before new construction assignment', async () => {
    const r=await fresh(), depot=await build(r,'observe',12,21), world=state(r);
    world.buildings=[]; world.rails=[]; world.produced+=16;
    setWorker(world,0,{x:12,y:20,job:2,target:depot.id,cargo:16,path:[1020]});
    setWorker(world,1,{job:6,timer:30}); setWorker(world,2,{job:6,timer:30}); await restoreColony(r,world);
    await call(r,'observe',[13,20]); assert.equal(state(r).buildings[0].stage,0);
    await advance(r); assert.equal(state(r).bots[0].target,0);
    await until(r,w=>w.buildings[0].stage===2); assert.ok(state(r).delivered>=16); balanced(r); await r.close();
  });
  await test('optional automation develops known extraction, and Manual stops new purchases', async () => {
    for (const focus of [1,2]) {
      const r=await fresh(); await call(r,'set-focus',[focus]); await advance(r);
      assert.equal(state(r).buildings[0].kind,1); assert.equal(state(r).buildings[0].x,12);
      await until(r,w=>w.buildings.some(b=>b.kind===2 && b.stage===2),500);
      assert.ok(state(r).ore>=40); await call(r,'set-focus',[0]); const count=state(r).buildings.length;
      await advance(r,100); assert.equal(state(r).buildings.length,count); assert.ok(state(r).produced>0);
      await r.close();
    }
  });
  await test('announced harder waves replace nearby sorties and keep the final beast health unchanged', async () => {
    for(const [tick,count,kind] of [[599,0,0],[600,4,0],[1050,4,0],[1950,0,0],[2100,5,1],[3300,6,1],[3750,7,0],[4200,7,2]]) {
      const r=await fresh(), world=state(r); world.tick=tick-1; await restoreColony(r,world);
      if(tick===1950)assert.match(r.view().label,/NEXT SPAWN 3:30 · 5 outpost raiders/);
      await advance(r); const enemies=state(r).enemies; assert.equal(enemies.length,count);
      if(kind===2){assert.equal(enemies.filter(e=>e.kind===2).length,1);assert.equal(enemies[0].hp,1800);}
      else assert.ok(enemies.every(e=>e.kind===kind));
      await r.close();
    }
  });
  await test('the full scheduled enemy backlog survives pause, save/reload and presentation', async () => {
    const r=await fresh(),baseQuads=r.view().quads.length,world=state(r); world.tick=4200; world.paused=1;
    for(let i=0;i<50;i++)world.enemies.push({id:world.nextId++,x:500,y:820,hp:i===49?1800:170,
      kind:i===49?2:0,target:0,path:[]});
    await restoreColony(r,world); const saved=r.snapshot(1);
    assert.ok(saved.length<65536); assert.ok(r.view().quads.length>=baseQuads+200);
    await r.restore(1,saved); await advance(r,5); assert.deepEqual(r.snapshot(1),saved);
    const excess=state(r); excess.enemies.push({...excess.enemies[0],id:excess.nextId++});
    await assert.rejects(()=>restoreColony(r,excess),WebAssembly.RuntimeError);
    await call(r,'pause-colony',[0]); await advance(r); assert.equal(state(r).enemies.length,50); await r.close();
  });
}

if (process.argv[1] === import.meta.filename) {
  const output=resolve(process.argv[2]); const manifest=JSON.parse(readFileSync(join(output,'manifest.json')));
  const bytes=readFileSync(join(output,manifest.module));
  async function fresh() { const r=new ReducerRuntime(); await r.replace(r.prepare(bytes,manifest)); await r.initialize(1); await r.initialize(2); return r; }
  const call=(r,name,args=[])=>r.dispatch(1,r.command('match',name,args));
  let count=0; const test=async(name,run)=>{await run(); console.log(`ok ${++count} - ${name}`);};
  if(process.argv.includes("--regression")) {await checkColony(test,fresh,call);await checkEncounters(test,fresh,call);await checkLogistics(test,fresh,call);}
  await checkFocus(test,fresh,call);
  console.log(`${count} colony focus checks passed`);
}
