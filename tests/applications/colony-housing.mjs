// Real World 10 transitions own house completion, paid recruits and capacity.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,restoreColony,fixtureCall,setWorker,at,pixelAt} from './colony-state.mjs';
const state=r=>colony(r.snapshot(1));
function node(r,key,value=r.view().ui){if(value.key===key)return value;for(const child of value.children){const found=node(r,key,child);if(found)return found;}}
function population(world,count){while(world.bots.length<count){world.bots.push({...world.bots[0],id:world.nextId++});setWorker(world,world.bots.length-1);}return world;}
async function advance(r,count=1){for(let i=0;i<count;i++)await fixtureCall(r,'advance');}
async function house(r){await fixtureCall(r,'build-house',[10,22]);for(let i=0;i<100&&state(r).buildings[0].stage!==2;i++)await advance(r);assert.equal(state(r).buildings[0].stage,2);}
export async function checkHousing(test,fresh){
  await test('an unfinished house adds no capacity; completion permits four paid recruits above the old cap',async()=>{
    const r=await fresh();await restoreColony(r,population(state(r),12));await fixtureCall(r,'fabricate-worker');assert.equal(state(r).notice,8);assert.equal(state(r).ore,160);
    await fixtureCall(r,'build-house',[10,22]);assert.match(node(r,'worker-capacity').text,/12 \/ 12/);
    await fixtureCall(r,'fabricate-worker');assert.equal(state(r).notice,8);
    for(let i=0;i<100&&state(r).buildings[0].stage!==2;i++)await advance(r);
    assert.equal(state(r).buildings[0].stage,2);assert.match(node(r,'worker-capacity').text,/12 \/ 16/);
    for(let i=0;i<4;i++)await fixtureCall(r,'fabricate-worker');assert.equal(state(r).ore,52);assert.match(node(r,'worker-capacity').text,/16 \/ 16/);
    await fixtureCall(r,'fabricate-worker');assert.equal(state(r).notice,8);assert.equal(state(r).ore,52);
    await advance(r,30);assert.equal(state(r).bots.length,16);await r.restore(1,r.snapshot(1));await r.close();
  });
  await test('destroying housing preserves queued recruits and over-capacity World 10 saves',async()=>{
    const r=await fresh();await house(r);await restoreColony(r,population(state(r),12));for(let i=0;i<4;i++)await fixtureCall(r,'fabricate-worker');
    const world=state(r),site=world.buildings[0];site.hp=1;world.tick=9;world.lastRevealTick=-100;
    world.enemies.push({id:world.nextId++,...pixelAt(world,10,22),hp:500,kind:0,target:site.id,path:[],rank:0});await restoreColony(r,world);await advance(r);
    assert.equal(state(r).buildings.length,0);assert.match(node(r,'worker-capacity').text,/16 \/ 12/);const saved=r.snapshot(1);assert.equal(saved[0],10);
    await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);await advance(r,30);assert.equal(state(r).bots.length,16);
    const ore=state(r).ore;await fixtureCall(r,'fabricate-worker');assert.equal(state(r).notice,8);assert.equal(state(r).ore,ore);await r.close();
  });
  await test('housing caps at 64 including queued workers and the decoder enforces only that hard bound',async()=>{
    const r=await fresh();await house(r);const world=state(r),template=world.buildings[0];
    for(let y=22;y<=23;y++)for(let x=10;x<=16;x++){if(x===10&&y===22)continue;const point=at(world,x,y);world.buildings.push({...template,id:world.nextId++,...point,aimX:point.x*40+20,aimY:point.y*40+20});world.spent+=8;world.ore-=8;}
    await restoreColony(r,population(world,63));assert.match(node(r,'worker-capacity').text,/63 \/ 64/);await fixtureCall(r,'fabricate-worker');assert.match(node(r,'worker-capacity').text,/64 \/ 64/);
    const ore=state(r).ore;await fixtureCall(r,'fabricate-worker');assert.equal(state(r).notice,8);assert.equal(state(r).ore,ore);await advance(r,30);assert.equal(state(r).bots.length,64);
    const saved=r.snapshot(1);await r.restore(1,saved);const invalid=population(state(r),65);await assert.rejects(()=>restoreColony(r,invalid),WebAssembly.RuntimeError);assert.deepEqual(r.snapshot(1),saved);await r.close();
  });
  await test('legacy kind-four construction keeps its ore ledger and becomes housing on World 10 restore',async()=>{
    const legacy=await fresh(),current=await fresh();await fixtureCall(legacy,'build-wall',[10,22]);await fixtureCall(current,'build-house',[10,22]);assert.deepEqual(legacy.snapshot(1),current.snapshot(1));
    for(let i=0;i<100&&state(legacy).buildings[0].stage!==2;i++)await advance(legacy);const saved=legacy.snapshot(1);await current.restore(1,saved);assert.deepEqual(current.snapshot(1),saved);
    assert.match(node(current,'worker-capacity').text,/3 \/ 16/);assert.equal(state(current).spent,8);assert.equal(state(current).buildings[0].hp,220);await legacy.close();await current.close();
  });
}
if(process.argv[1]===import.meta.filename){const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};let count=0;await checkHousing(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);console.log(`${count} housing checks passed`);}
