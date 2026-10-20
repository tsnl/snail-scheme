// Compare compiled worker arrivals with an independent shortest-time graph.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {decodeObservation} from '../../apps/siegework/headless.mjs';
import {establishColony,colony,colonyBalance,restoreColony,fixtureCall,at,pixelAt,setWorker,withdrawReserves} from './colony-state.mjs';

const cell=(x,y)=>x+y*64;
const manhattan=(a,b)=>Math.abs(a%64-b%64)+Math.abs(Math.floor(a/64)-Math.floor(b/64));
function building(world,x,y,kind=3,level=1) {
  const point=pixelAt(world,x,y),site={id:world.nextId++,kind,...at(world,x,y),level,hp:kind===3?90:100,
    stock:0,stage:2,cooldown:0,aimX:point.x,aimY:point.y,armed:0,source:0,moveX:-1,moveY:-1};
  world.buildings.push(site);world.spent+=kind===3?25*level:50;world.ore-=kind===3?25*level:50;
  world.surveys.push({...at(world,x,y),radius:kind===3?(level===1?7:10):4});return site;
}
function shortestTicks(world,tiles,start,target) {
  const ground=new Set(tiles.filter(tile=>tile.terrain===1).map(tile=>tile.cell)),edges=new Map();
  const levels=new Map([[0,3],...world.buildings.map(site=>[site.id,site.level])]);
  for(const rail of world.rails) {
    const [a,b]=rail.path;if(rail.path.length!==2||manhattan(a,b)<=1)continue;
    const speed=80*2**(Math.min(levels.get(rail.source),levels.get(rail.parent))-1);
    const ticks=4+Math.ceil(Math.hypot(a%64-b%64,Math.floor(a/64)-Math.floor(b/64))*40/speed);
    for(const [from,to]of[[a,b],[b,a]])edges.set(from,[...(edges.get(from)??[]),[to,ticks]]);
  }
  const distances=new Map([[start,0]]),pending=[[start,0]];
  while(pending.length) {
    pending.sort((a,b)=>b[1]-a[1]||b[0]-a[0]);const [here,time]=pending.pop();
    if(time!==distances.get(here))continue;if(here===target)return time;
    const neighbors=[here-64,here+64,here-1,here+1].filter(next=>manhattan(here,next)===1).map(next=>[next,5]);
    for(const [next,cost]of[...neighbors,...(edges.get(here)??[])])if(ground.has(next)&&time+cost<(distances.get(next)??Infinity)) {
      distances.set(next,time+cost);pending.push([next,time+cost]);
    }
  }
  return Infinity;
}

export async function checkWorkerRoutes(test,fresh) {
  const state=r=>colony(r.snapshot(1));
  async function step(r) {
    await fixtureCall(r,'advance');const world=state(r),balance=colonyBalance(world);
    assert.equal(world.ore,balance.bank);assert.equal(world.produced,balance.raw);
    await r.restore(1,r.snapshot(1));return world;
  }
  async function setup(stations,start=[8,22],destination=null) {
    const r=await fresh(),world=state(r);world.started=true;world.bots.length=1;
    withdrawReserves(world,2000);world.delivered+=2000;world.ore+=2000;
    for(const [x,y,level=1]of stations)building(world,x,y,3,level);
    if(destination)building(world,...destination,2);
    setWorker(world,0,{x:start[0],y:start[1]});await restoreColony(r,world);await step(r);return r;
  }
  async function arrival(r,job) {
    const flights=[];let previous='',elapsed=0;
    while(state(r).bots[0].job!==job&&elapsed<300) {
      const world=await step(r),flight=world.bots[0].flight[0];elapsed++;
      const key=flight?`${flight.origin}:${flight.destination}`:'';
      if(key&&key!==previous)flights.push({...flight});previous=key;
    }
    assert.equal(state(r).bots[0].job,job,'worker physically arrived');return{elapsed,flights};
  }
  async function order(r,destination) {
    const world=state(r),bot=world.bots[0],target=at(world,...destination);
    const expected=shortestTicks(world,decodeObservation(r.observe()).tiles,
      cell(Math.floor(bot.x/40),Math.floor(bot.y/40)),cell(target.x,target.y));
    await fixtureCall(r,'scavenge-building',destination);assert.equal(state(r).notice,44);
    const result=await arrival(r,17);assert.equal(result.elapsed,expected+1);return result;
  }
  await test('workers use both directions and multiple links for shortest elapsed arrival at arbitrary destinations',async()=>{
    for(const [start,destination]of[[[8,22],[18,24]],[[16,22],[8,24]]]) {
      const r=await setup([[12,22],[16,22]],start,destination),before=state(r);
      const result=await order(r,destination);assert.equal(result.flights.length,2);
      const againstFreight=start[0]===8;
      for(const flight of result.flights)assert.ok(before.rails.some(rail=>
        rail.path[againstFreight?1:0]===flight.origin&&rail.path[againstFreight?0:1]===flight.destination));
      await r.close();
    }
  });
  await test('a useful walk away from the hub reaches a faster zipline; upgraded speed reduces actual arrival ticks',async()=>{
    const times=[];
    for(const level of[1,2,3]) {
      const r=await setup([[16,24,level]],[13,24]),world=state(r),hub=at(world,8,22),bot=world.bots[0];
      const expected=shortestTicks(world,decodeObservation(r.observe()).tiles,
        cell(Math.floor(bot.x/40),Math.floor(bot.y/40)),cell(hub.x,hub.y));
      await fixtureCall(r,'fabricate-worker');assert.equal(state(r).notice,13);
      const result=await arrival(r,6);assert.equal(result.elapsed,expected+1);assert.equal(result.flights.length,1);
      assert.equal(result.flights[0].origin,cell(...Object.values(at(world,16,24))));
      assert.ok(result.elapsed<36);times.push(result.elapsed);await r.close();
    }
    assert.ok(times[0]>times[1]&&times[1]>times[2]);
  });
  await test('boarding overhead and disconnected stations leave faster walking routes on the ground',async()=>{
    for(const [stations,start,destination]of[[[[12,22],[16,22]],[11,22],[13,22]],[[[18,22]],[18,22],[14,24]]]) {
      const r=await setup(stations,start,destination),result=await order(r,destination);
      assert.deepEqual(result.flights,[]);await r.close();
    }
  });
  await test('worker routing crosses rock by a real cable but never walks through rock or unknown ground',async()=>{
    const r=await setup([[16,22],[22,22],[22,15],[26,15]],[22,15],[26,14]);
    const result=await order(r,[26,14]);assert.ok(result.flights.length>0);await r.close();
    const isolated=await setup([], [8,22]);const world=state(isolated);building(world,2,2,2);
    await restoreColony(isolated,world);await fixtureCall(isolated,'scavenge-building',[2,2]);
    assert.equal(state(isolated).notice,42);assert.equal(state(isolated).bots[0].job,0);await isolated.close();
  });
  await test('a queued paid walking kit adopts a newly completed cable and arrives sooner without changing its owner',async()=>{
    for(const [tick,expected]of[[20,59],[24,49],[29,39],[34,29]]) {
      const r=await setup([], [8,22],[20,23]);await fixtureCall(r,'observe',[20,22]);await step(r);
      const world=state(r),carrier=world.bots[0],project=world.buildings.find(site=>site.id===carrier.target);
      assert.equal(carrier.job,3);assert.equal(carrier.cargo,25);assert.equal(carrier.path.length,12);
      building(world,16,22);world.tick=tick;await restoreColony(r,world);
      const before=world.ore,ownership={target:carrier.target,cargo:carrier.cargo,source:carrier.source,order:carrier.order};
      let elapsed=0,flights=0;
      while(state(r).buildings.find(site=>site.id===project.id).stage!==2&&elapsed<70) {
        const current=await step(r);elapsed++;const bot=current.bots[0];if(bot.flight.length)flights++;
        if(bot.cargo)assert.deepEqual({target:bot.target,cargo:bot.cargo,source:bot.source,order:bot.order},ownership);
      }
      assert.equal(elapsed,expected);assert.ok(flights>0);assert.equal(state(r).ore,before);
      assert.equal(state(r).buildings.find(site=>site.id===project.id).stage,2);await r.close();
    }
  });
  await test('a partial walking step finishes normally before any refreshed route can board a flight',async()=>{
    const r=await setup([], [8,22],[20,23]);await fixtureCall(r,'observe',[20,22]);await step(r);await step(r);
    const world=state(r);assert.equal(world.bots[0].x%40,28);building(world,16,22);world.tick=14;
    await restoreColony(r,world);const next=await step(r);
    assert.equal(next.bots[0].x,world.bots[0].x+8);assert.deepEqual(next.bots[0].flight,[]);
    assert.equal(next.bots[0].cargo,25);assert.equal(next.bots[0].target,world.bots[0].target);await r.close();
  });
  await test('equal-time route choices stay deterministic when restored rail records are reordered',async()=>{
    const r=await setup([[12,22],[16,22]], [8,22],[18,24]),world=state(r);
    await fixtureCall(r,'scavenge-building',[18,24]);const path=state(r).bots[0].path;
    world.rails.reverse();await restoreColony(r,world);await fixtureCall(r,'scavenge-building',[18,24]);
    assert.deepEqual(state(r).bots[0].path,path);await r.close();
  });
}
if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return establishColony(r);};
  let count=0;await checkWorkerRoutes(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);
  console.log(`${count} worker route groups passed`);
}
