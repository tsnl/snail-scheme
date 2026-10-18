// Actual Scheme shots establish remembered attackers; subsequent real movement
// and encounters prove pursuit, obstruction, damage and compatible persistence.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,restoreColony,fixtureCall,pixelAt,routeCell,siteAt,setWorker} from './colony-state.mjs';

export async function checkRetaliation(test,fresh,bytes) {
  const state=r=>colony(r.snapshot(1)),call=fixtureCall;
  async function advance(r,count=1) {for(let i=0;i<count;i++)await call(r,'advance');}
  async function build(r,action,x,y) {
    await call(r,action,[x,y]);
    for(let i=0;i<300&&siteAt(state(r),x,y)?.stage!==2;i++)await advance(r);
    const site=siteAt(state(r),x,y);assert.equal(site?.stage,2);return site;
  }
  function encounter(world,x,y,extra={}) {
    world.started=true;world.tick=8;world.lastRevealTick=-100;
    for(let i=0;i<world.bots.length;i++)setWorker(world,i);
    for(const site of world.buildings)site.cooldown=0;
    world.enemies=[{id:world.nextId++,...pixelAt(world,x,y),hp:500,kind:0,target:0,path:[],rank:5,...extra}];
    return world;
  }
  await test('a shot makes a hub attacker leave the hub and retaliate against the gun',async()=>{
    const r=await fresh(),gun=await build(r,'fortify',12,22),world=encounter(state(r),8,22),point=pixelAt(world,8,22);
    await restoreColony(r,world);await advance(r);let enemy=state(r).enemies[0];
    assert.ok(enemy.hp<500);assert.equal(enemy.target,gun.id);assert.equal(enemy.path.at(-1),routeCell(world,12,22));
    await advance(r);enemy=state(r).enemies[0];assert.equal(enemy.x,point.x+5);assert.equal(state(r).hull,300);
    await advance(r,40);assert.ok(state(r).buildings.find(site=>site.id===gun.id).hp<gun.hp);
    assert.equal(state(r).hull,300);await r.close();
  });
  await test('workers and unrelated buildings do not distract an enemy pursuing its attacker',async()=>{
    const r=await fresh(),gun=await build(r,'fortify',14,22),decoy=await build(r,'observe',10,23);
    const world=encounter(state(r),10,22),point=pixelAt(world,10,22);setWorker(world,0,{x:10,y:22});
    await restoreColony(r,world);await advance(r,2);const after=state(r),enemy=after.enemies[0];
    assert.equal(enemy.target,gun.id);assert.equal(enemy.x,point.x+5);assert.equal(after.hull,300);
    assert.equal(after.bots.find(bot=>bot.id===world.bots[0].id).hp,14);
    assert.equal(after.buildings.find(site=>site.id===decoy.id).hp,decoy.hp);
    await advance(r,32);assert.ok(state(r).buildings.find(site=>site.id===gun.id).hp<gun.hp);
    assert.equal(state(r).buildings.find(site=>site.id===decoy.id).hp,decoy.hp);await r.close();
  });
  await test('another hit by the same gun retains the current route instead of replanning',async()=>{
    const r=await fresh(),gun=await build(r,'fortify',14,22),world=encounter(state(r),15,18);
    const path=[[16,18],[16,19],[16,20],[16,21],[16,22],[15,22],[14,22]].map(([x,y])=>routeCell(world,x,y));
    Object.assign(world.enemies[0],{target:gun.id,path});const point=pixelAt(world,15,18);
    await restoreColony(r,world);await advance(r);const enemy=state(r).enemies[0];
    assert.ok(enemy.hp<500);assert.equal(enemy.target,gun.id);assert.equal(enemy.x,point.x+5);
    assert.deepEqual(enemy.path,path);await r.close();
  });
  await test('a pursuer updates its destination when the same attacking gun relocates',async()=>{
    const r=await fresh(),gun=await build(r,'fortify',12,22),world=encounter(state(r),16,22);
    await restoreColony(r,world);await advance(r);assert.equal(state(r).enemies[0].target,gun.id);
    await call(r,'relocate-building',[12+22*48,10+22*48]);assert.equal(state(r).notice,21);
    await advance(r,50);const after=state(r),enemy=after.enemies[0],moved=siteAt(after,10,22);
    assert.equal(moved.id,gun.id);assert.equal(enemy.target,gun.id);
    assert.equal(enemy.path.at(-1),routeCell(world,10,22));assert.ok(moved.hp<gun.hp);
    assert.equal(after.hull,300);await r.restore(1,r.snapshot(1));await r.close();
  });
  await test('the latest gun to hit becomes the saved target and a different attacker redirects it',async()=>{
    const r=await fresh();await build(r,'fortify',12,21);await build(r,'fortify',12,25);
    const world=encounter(state(r),16,23),first=world.buildings[0],last=world.buildings.at(-1);
    await restoreColony(r,world);await advance(r);assert.equal(state(r).enemies[0].target,last.id);
    assert.equal(state(r).enemies[0].path.at(-1),last.x+last.y*384);
    const saved=r.snapshot(1);await r.restore(1,saved);await r.replace(r.prepare(bytes,r.manifest));assert.deepEqual(r.snapshot(1),saved);
    const next=state(r);next.buildings.find(site=>site.id===first.id).cooldown=0;
    next.buildings.find(site=>site.id===last.id).cooldown=8;await restoreColony(r,next);await advance(r);
    assert.equal(state(r).enemies[0].target,first.id);assert.equal(state(r).enemies[0].path.at(-1),first.x+first.y*384);await r.close();
  });
  await test('houses do not intercept enemies pursuing their remembered artillery attacker',async()=>{
    const r=await fresh(),house=await build(r,'build-house',12,22),gun=await build(r,'fortify',14,22);
    const world=encounter(state(r),10,22);await restoreColony(r,world);await advance(r,22);const after=state(r);
    assert.equal(after.enemies[0].target,gun.id);assert.ok(after.enemies[0].x>house.x*40+20-50);
    assert.equal(after.buildings.find(site=>site.id===house.id).hp,house.hp);assert.equal(after.hull,300);
    await advance(r,10);assert.ok(state(r).buildings.find(site=>site.id===gun.id).hp<gun.hp);await r.close();
  });
  await test('destroying the attacker clears the commitment and resumes a valid hub route',async()=>{
    const r=await fresh(),gun=await build(r,'fortify',14,22),world=encounter(state(r),14,23);
    world.buildings.find(site=>site.id===gun.id).hp=1;await restoreColony(r,world);await advance(r,2);
    assert.ok(!state(r).buildings.some(site=>site.id===gun.id));assert.equal(state(r).enemies[0].target,gun.id);
    const saved=r.snapshot(1);await r.restore(1,saved);await advance(r);const enemy=state(r).enemies[0];
    assert.equal(enemy.target,0);assert.equal(enemy.path.at(-1),routeCell(world,8,22));await r.close();
  });
  await test('retaliation walks around water even when the incoming shot crosses it',async()=>{
    const r=await fresh(),gun=await build(r,'fortify',12,22),world=encounter(state(r),8,22);
    const site=world.buildings.find(site=>site.id===gun.id);Object.assign(site,{x:81,y:7});world.rails=[];world.tracks=[];
    world.surveys.unshift({x:81,y:7,radius:4});Object.assign(world.enemies[0],{x:83*40+20,y:7*40+20});
    await restoreColony(r,world);await advance(r);const enemy=state(r).enemies[0];
    assert.ok(enemy.hp<500);assert.equal(enemy.target,gun.id);assert.equal(enemy.path.at(-1),81+7*384);
    assert.ok(!enemy.path.includes(82+7*384));assert.ok(enemy.path.length>2);
    await advance(r,12);assert.deepEqual(state(r).breaches,[]);assert.deepEqual(state(r).excavations,[]);await r.close();
  });
  await test('the 3-by-3 hub has a rounded attack boundary along its sides and corners',async()=>{
    const r=await fresh(),base=state(r),point=pixelAt(base,8,22);
    for(const [dx,dy,hits] of [[80,0,true],[-80,0,true],[0,80,true],[0,-80,true],[80,60,true],[80,80,false],[86,0,false]]) {
      const world=encounter(structuredClone(base),8,22,{x:point.x+dx,y:point.y+dy,hp:80,rank:0});world.tick=9;
      await restoreColony(r,world);await advance(r);assert.equal(state(r).hull,hits?293:300,`offset ${dx},${dy}`);
    }
    await r.close();
  });
  await test('artillery levels increase enemy damage while legacy hybrid guns retain their firepower',async()=>{
    const r=await fresh(),gun=await build(r,'fortify',12,22),base=state(r);
    for(const [kind,level,armed,extraCost,damage] of [[2,1,0,0,12],[2,2,0,25,18],[2,3,0,50,24],[3,2,1,0,12],[3,3,1,25,12]]) {
      const world=encounter(structuredClone(base),16,22),site=world.buildings.find(site=>site.id===gun.id);
      Object.assign(site,{kind,level,armed,hp:90});world.spent+=extraCost;world.ore-=extraCost;
      if(kind===3)world.surveys.unshift({x:site.x,y:site.y,radius:10});
      await restoreColony(r,world);await advance(r);assert.equal(state(r).enemies[0].hp,500-damage,`kind ${kind}, level ${level}`);
    }
    await r.close();
  });
  await test('the same artillery level multiplier applies to shots at the nest',async()=>{
    const r=await fresh(),gun=await build(r,'fortify',12,22),base=state(r);
    for(const [level,damage] of [[1,12],[3,24]]) {
      const world=structuredClone(base),site=world.buildings.find(site=>site.id===gun.id),extraCost=25*(level-1);
      Object.assign(site,{kind:2,level,armed:0,x:199,y:28,cooldown:0});world.rails=[];world.tracks=[];
      world.spent+=extraCost;world.ore-=extraCost;world.surveys.unshift({x:199,y:28,radius:4});
      await restoreColony(r,world);await advance(r);assert.equal(state(r).nestHp,1500-damage);
    }
    await r.close();
  });
}

if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json')));
  const bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};
  let count=0;await checkRetaliation(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh,bytes);
  console.log(`${count} retaliation and artillery checks passed`);
}
