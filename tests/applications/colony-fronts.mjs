// Fixtures position artillery and outposts; real Wasm owns targeting, spawning,
// damage, victory and exact restored identities. No fixture models combat.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,restoreColony,fixtureCall} from './colony-state.mjs';

const state=r=>colony(r.snapshot(1)),call=fixtureCall;
const distance=(a,b)=>(a.x-b.x)**2+(a.y-b.y)**2;
const source=(world,enemy)=>world.nests.toSorted((a,b)=>distance(a,{x:(enemy.x-20)/40,y:(enemy.y-20)/40})-distance(b,{x:(enemy.x-20)/40,y:(enemy.y-20)/40}))[0].id;
function structure(world,kind,x,y) {
  const site={id:world.nextId++,kind,x,y,level:1,hp:kind===2?100:90,stock:0,stage:2,cooldown:0,
    aimX:x*40+20,aimY:y*40+20,armed:0,source:0,moveX:-1,moveY:-1};
  world.buildings.push(site);world.surveys.unshift({x,y,radius:kind===3?7:4});
  const cost=kind===2?50:25;world.spent+=cost;world.ore-=cost;world.started=true;return site;
}
function firingSite(world,nest) {
  return [[0,4],[4,0],[0,-4],[-4,0]].map(([dx,dy])=>({x:nest.x+dx,y:nest.y+dy}))
    .find(site=>!world.deposits.some(deposit=>deposit.cell===site.x+site.y*64));
}
async function advance(r,count=1){for(let i=0;i<count;i++)await call(r,'advance');}

export async function checkFronts(test,fresh) {
  await test('three stable nests share each opening wave and cleared fronts permanently remove their shares',async()=>{
    const r=await fresh(),base=state(r);assert.deepEqual(base.nests.map(n=>n.hp),[900,900,900]);
    assert.deepEqual(base.nests.map(n=>n.id),[0,1,2]);
    for(const dead of [[],[0],[0,2]]) {
      const w=structuredClone(base);w.started=true;w.tick=449;for(const id of dead)w.nests[id].hp=0;
      await restoreColony(r,w);await advance(r);const spawned=state(r);
      assert.equal(spawned.enemies.length,(3-dead.length)*2);
      for(const nest of spawned.nests)assert.equal(spawned.enemies.filter(e=>source(spawned,e)===nest.id).length,nest.hp?2:0);
      const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);
    }
    await r.close();
  });
  await test('three simultaneous raid fronts select their own nearer outpost rather than one distant tendril',async()=>{
    const r=await fresh(),w=state(r),hub=w.surveys[0],targets=new Map();w.started=true;w.tick=1349;
    for(const nest of w.nests) {
      const horizontal=Math.abs(hub.x-nest.x)>Math.abs(hub.y-nest.y);
      const x=nest.x+(horizontal?Math.sign(hub.x-nest.x)*3:0),y=nest.y+(horizontal?0:Math.sign(hub.y-nest.y)*3);
      targets.set(nest.id,structure(w,3,x,y).id);
    }
    await restoreColony(r,w);await advance(r);const spawned=state(r);assert.equal(spawned.enemies.length,7);
    assert.equal(new Set(spawned.enemies.map(e=>e.target)).size,3);
    for(const enemy of spawned.enemies){assert.equal(enemy.kind,1);assert.equal(enemy.target,targets.get(source(spawned,enemy)));}
    await r.close();
  });
  await test('artillery must clear every nest; final victory keeps surviving enemies and freezes saved time',async()=>{
    const r=await fresh(),w=state(r),nest=w.nests[0],site=firingSite(w,nest);structure(w,2,site.x,site.y);
    w.enemies.push({id:w.nextId++,x:w.surveys.at(-1).x*40+20,y:w.surveys.at(-1).y*40+20,hp:80,kind:0,target:0,path:[]});
    await restoreColony(r,w);
    for(let index=0;index<3;index++) {
      const candidate=state(r),target=candidate.nests[index],gun=candidate.buildings[0];
      target.hp=6;Object.assign(gun,{...firingSite(candidate,target),cooldown:0});candidate.surveys.unshift({x:gun.x,y:gun.y,radius:4});
      await restoreColony(r,candidate);const bank=candidate.ore;await advance(r);const hit=state(r);
      assert.equal(hit.nests[index].hp,0);assert.equal(hit.outcome,index===2?3:0);assert.equal(hit.ore,bank);
      assert.deepEqual([hit.buildings[0].aimX,hit.buildings[0].aimY],[target.x*40+20,target.y*40+20]);
    }
    assert.equal(state(r).enemies.length,1);await call(r,'pause-colony',[1]);const won=r.snapshot(1);
    await r.restore(1,won);await advance(r,20);assert.deepEqual(r.snapshot(1),won);await r.close();
  });
  await test('a nest killed on a spawn tick emits its final share and emits nothing on the next wave',async()=>{
    const r=await fresh(),w=state(r),nest=w.nests[0];w.tick=449;nest.hp=6;
    structure(w,2,nest.x,nest.y-6);structure(w,3,nest.x,nest.y-4);
    await restoreColony(r,w);await advance(r);const killed=state(r);
    assert.equal(killed.nests[0].hp,0);assert.equal(killed.enemies.length,6);assert.equal(killed.outcome,0);
    const next=state(r),firstId=next.nextId;next.tick=749;await restoreColony(r,next);await advance(r);
    const later=state(r),born=later.enemies.filter(e=>e.id>=firstId);assert.equal(born.length,4);
    assert.ok(born.every(e=>source(later,e)!==0));await r.close();
  });
  await test('dead fronts do not promote a replacement strongest enemy or boss',async()=>{
    const r=await fresh(),base=state(r);
    for(const tick of [1050,5400]) {
      const w=structuredClone(base);w.started=true;w.tick=tick-1;await restoreColony(r,w);await advance(r);
      const all=state(r),strongest=all.enemies.reduce((a,b)=>a.rank>b.rank?a:b),dead=source(all,strongest);
      w.nests[dead].hp=0;await restoreColony(r,w);await advance(r);const reduced=state(r);
      assert.ok(reduced.enemies.every(e=>e.rank<strongest.rank));assert.ok(reduced.enemies.every(e=>e.kind!==2));
      assert.ok(reduced.enemies.length<all.enemies.length);await r.restore(1,r.snapshot(1));
    }
    await r.close();
  });
  await test('restore proves the full seed-owned nest set and rejects impossible outcomes atomically',async()=>{
    const r=await fresh(),saved=r.snapshot(1);
    for(const edit of [w=>w.nests.pop(),w=>w.nests.push({...w.nests[0]}),w=>w.nests.reverse(),w=>w.nests[0].id++,
      w=>w.nests[0].x++,w=>w.nests[0].y++,w=>w.nests[0].hp=-1,w=>w.nests[0].hp=901,
      w=>w.outcome=3,w=>w.nests.forEach(n=>n.hp=0)]) {
      const invalid=colony(saved);edit(invalid);await assert.rejects(()=>restoreColony(r,invalid),WebAssembly.RuntimeError);
      assert.deepEqual(r.snapshot(1),saved);
    }
    await r.close();
  });
}

if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};
  let count=0;await checkFronts(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);
}
