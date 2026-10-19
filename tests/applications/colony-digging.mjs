// Linked Scheme reducers prove excavation timing and its permanent map effects.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,colonyBalance,restoreColony,fixtureCall,pixelAt,routeCell,siteAt,setWorker} from './colony-state.mjs';

export async function checkDigging(test,fresh) {
  const state=r=>colony(r.snapshot(1)),call=fixtureCall;
  async function advance(r,count=1) {
    for(let i=0;i<count;i++) {
      await call(r,'advance'); const world=state(r),balance=colonyBalance(world);
      assert.equal(world.ore,balance.bank); assert.equal(world.produced,balance.raw);
    }
  }
  function digger(world,changes={}) {
    world.started=true;
    return {id:world.nextId++,...pixelAt(world,6,11),hp:80,kind:0,target:0,
      path:[routeCell(world,6,10)],burrower:true,...changes};
  }
  async function build(r,name,x,y) {
    await call(r,name,[x,y]);
    for(let i=0;i<500&&siteAt(state(r),x,y)?.stage!==2;i++)await advance(r);
    const site=siteAt(state(r),x,y); assert.equal(site?.stage,2); return site;
  }
  await test('a lone burrower stops for eight seconds and leaves a permanent saved breach',async()=>{
    const r=await fresh(),world=state(r),enemy=digger(world),cell=enemy.path[0];
    world.enemies=[enemy]; await restoreColony(r,world); await advance(r);
    assert.deepEqual(state(r).excavations,[{cell,remaining:79}]);
    assert.deepEqual([state(r).enemies[0].x,state(r).enemies[0].y],[enemy.x,enemy.y]);
    await call(r,'pause-colony',[1]); const paused=r.snapshot(1); await r.restore(1,paused); await advance(r,30);
    assert.deepEqual(r.snapshot(1),paused); await call(r,'pause-colony',[0]); await advance(r,78);
    assert.equal(state(r).excavations[0].remaining,1); assert.deepEqual(state(r).breaches,[]);
    assert.equal(state(r).enemies[0].y,enemy.y); await advance(r);
    assert.deepEqual(state(r).breaches,[cell]); assert.deepEqual(state(r).excavations,[]);
    assert.equal(state(r).enemies[0].y,enemy.y-5);
    const saved=r.snapshot(1); await r.restore(1,saved); assert.deepEqual(r.snapshot(1),saved);
    const cleared=state(r); cleared.enemies=[]; await restoreColony(r,cleared); await advance(r);
    assert.deepEqual(state(r).breaches,[cell]); await call(r,'new-run-seed',[1]);
    assert.deepEqual(state(r).breaches,[]); assert.deepEqual(state(r).excavations,[]); await r.close();
  });
  await test('cooperating enemies help excavate but even a crowd takes four seconds',async()=>{
    const r=await fresh(),world=state(r),cell=routeCell(world,6,10);
    world.enemies=Array.from({length:4},()=>digger(world)); await restoreColony(r,world); await advance(r);
    assert.deepEqual(state(r).excavations,[{cell,remaining:78}]); await advance(r,38);
    assert.equal(state(r).excavations[0].remaining,2); assert.equal(state(r).breaches.length,0);
    await advance(r); assert.deepEqual(state(r).breaches,[cell]); assert.equal(state(r).excavations.length,0); await r.close();
  });
  await test('unfinished excavation survives retreat and ordinary enemies can continue it',async()=>{
    const r=await fresh(),world=state(r); world.enemies=[digger(world)]; await restoreColony(r,world); await advance(r,5);
    const abandoned=state(r); abandoned.enemies=[]; await restoreColony(r,abandoned); await advance(r,5);
    assert.equal(state(r).excavations[0].remaining,75);
    const following=state(r); following.enemies=[digger(following,{burrower:false})]; await restoreColony(r,following); await advance(r);
    assert.equal(state(r).excavations[0].remaining,74); assert.equal(state(r).enemies[0].burrower,false); await r.close();
  });
  await test('ordinary enemies compare walking time with joining an existing excavation',async()=>{
    const r=await fresh(); await build(r,'observe',9,14); const target=await build(r,'fortify',6,9);
    const world=state(r),enemy=digger(world,{burrower:false,target:target.id,path:[]}),cell=routeCell(world,6,10);
    world.enemies=[enemy]; world.excavations=[{cell,remaining:79}]; world.tick=19-(enemy.id%20); world.lastRevealTick=-100;
    for(let i=0;i<world.bots.length;i++)setWorker(world,i);
    await restoreColony(r,world); await advance(r);
    assert.ok(!state(r).enemies[0].path.includes(cell)); assert.equal(state(r).excavations[0].remaining,79);
    world.enemies[0].kind=1; world.excavations[0].remaining=50; await restoreColony(r,world); await advance(r);
    assert.ok(!state(r).enemies[0].path.includes(cell),'faster raiders prefer the six-tick-per-cell detour');
    world.enemies[0].path=[[7,11],[8,11],[9,11],[10,11],[10,10],[10,9],[9,9],[8,9],[7,9],[6,9]]
      .map(([x,y])=>routeCell(world,x,y));
    world.excavations[0].remaining=20; await restoreColony(r,world); await advance(r);
    assert.equal(state(r).enemies[0].path[0],cell); assert.equal(state(r).enemies[0].y,enemy.y);
    await advance(r); assert.equal(state(r).excavations[0].remaining,19);
    world.excavations=[]; world.breaches=[cell]; await restoreColony(r,world); await advance(r);
    assert.equal(state(r).enemies[0].path[0],cell); assert.equal(state(r).enemies[0].y,enemy.y-7); await r.close();
  });
  await test('completed excavation opens direct fire and workers can build on the cleared rock',async()=>{
    const r=await fresh(); await build(r,'observe',9,14); const gun=await build(r,'fortify',6,9);
    const world=state(r),enemy=digger(world,{target:gun.id}),cell=enemy.path[0]; world.enemies=[enemy];
    enemy.path.push(routeCell(world,6,9)); // The remembered route still reaches its gun beyond the rock.
    world.tick=0; world.lastRevealTick=-100; world.buildings.find(site=>site.id===gun.id).cooldown=0;
    for(let i=0;i<world.bots.length;i++)setWorker(world,i);
    await restoreColony(r,world); await advance(r,79); assert.equal(state(r).enemies[0].hp,80);
    await advance(r); assert.ok(state(r).enemies[0].hp<80); assert.deepEqual(state(r).breaches,[cell]);
    const safe=state(r); safe.enemies=[]; await restoreColony(r,safe);
    await build(r,'build-house',6,10); assert.equal(siteAt(state(r),6,10).hp,220);
    const saved=r.snapshot(1); await r.restore(1,saved); assert.deepEqual(r.snapshot(1),saved); await r.close();
  });
  await test('roughly one in ten spawned enemies has the deterministic burrowing capability',async()=>{
    const r=await fresh(); let total=0,burrowers=0;
    for(let tick=450;tick<=6150;tick+=300) {
      const world=state(r); world.started=true; world.tick=tick-1; world.enemies=[]; await restoreColony(r,world); await advance(r);
      for(const enemy of state(r).enemies) {
        assert.equal(enemy.burrower,(state(r).seed%10+enemy.id%10)%10===0);
        total++; if(enemy.burrower)burrowers++;
      }
    }
    assert.ok(total>100); assert.ok(burrowers/total>=0.08&&burrowers/total<=0.12); await r.close();
  });
  await test('raid targeting follows frontier exposure in every direction and excludes houses and guns',async()=>{
    const r=await fresh(),funded=state(r); funded.produced+=200; funded.delivered+=200; funded.ore+=200; await restoreColony(r,funded);
    await build(r,'observe',12,14); const north=await build(r,'observe',12,8);
    await build(r,'observe',16,21); await build(r,'observe',22,20);
    await build(r,'build-house',12,2); await build(r,'fortify',12,1);
    const world=state(r); world.tick=1349; world.lastRevealTick=-100; world.enemies=[]; await restoreColony(r,world); await advance(r);
    assert.equal(state(r).enemies.length,5); assert.ok(state(r).enemies.every(enemy=>enemy.target===north.id)); await r.close();
  });
  await test('decoding rejects impossible excavation, water breaches and unqualified rock routes',async()=>{
    const r=await fresh(),saved=r.snapshot(1),base=state(r),cell=routeCell(base,6,10);
    const edits=[world=>world.breaches=[routeCell(world,8,22)],world=>world.breaches=[80+16*128],
      world=>world.breaches=[cell,cell],world=>world.excavations=[{cell,remaining:0}],
      world=>world.excavations=[{cell,remaining:80}],world=>world.excavations=[{cell,remaining:79},{cell,remaining:78}],
      world=>{world.breaches=[cell];world.excavations=[{cell,remaining:79}];},
      world=>world.enemies=[digger(world,{burrower:false})],
      world=>world.enemies=[digger(world,{...pixelAt(world,6,10),path:[]})]];
    for(const edit of edits) {
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
  let count=0; await checkDigging(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);
  console.log(`${count} excavation checks passed`);
}
