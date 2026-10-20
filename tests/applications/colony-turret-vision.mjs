// A lone artillery's own observer must cover its gun; rock LOS remains separate.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {decodeObservation} from '../../apps/siegework/headless.mjs';
import {colony,restoreColony,MAP_WIDTH} from './colony-state.mjs';

export async function checkTurretVision(test,fresh) {
  const state=r=>colony(r.snapshot(1)),cell=(x,y)=>x+y*MAP_WIDTH;
  async function isolated(r,distance,blocked) {
    const saved=r.snapshot(1),world=state(r);
    // Inspection chooses a reproducible bounded encounter. Restore immediately:
    // only the hub and the completed gun's normal survey remain in the test.
    await restoreColony(r,{...world,started:true,outcome:4});
    const terrain=new Map(decodeObservation(r.observe()).tiles.map(tile=>[tile.cell,tile]));await r.restore(1,saved);
    let selected;
    for(const nest of world.nests)for(const [dx,dy]of[[1,0],[-1,0],[0,1],[0,-1]]) {
      const x=nest.x+dx*distance,y=nest.y+dy*distance,site=terrain.get(cell(x,y));
      const lane=Array.from({length:distance-1},(_,i)=>terrain.get(cell(nest.x+dx*(i+1),nest.y+dy*(i+1))));
      if(site?.terrain===1&&site.depositRate===0&&lane.every(Boolean)&&lane.some(tile=>tile.terrain===0)===blocked)
        selected??={nest,x,y};
    }
    assert.ok(selected,`seed has a ${blocked?'rock-blocked':'clear'} ${distance}-cell approach`);
    const {nest,x,y}=selected,id=world.nextId++;
    world.started=true;world.ore-=50;world.spent+=50;
    world.buildings=[{id,kind:2,x,y,level:1,hp:100,stock:0,stage:2,cooldown:0,
      aimX:x*40+20,aimY:y*40+20,armed:0,source:0,moveX:-1,moveY:-1}];
    world.surveys.push({x,y,radius:6});await restoreColony(r,world);
    assert.equal(world.surveys.length,2);assert.equal(world.buildings.length,1);assert.equal(world.buildings[0].kind,2);
    return {world,nest,id};
  }
  await test('an isolated turret sees and fires at a nest five and six cells away without any tower',async()=>{
    for(const distance of [5,6]) {
      const r=await fresh();try {
        const {world,nest,id}=await isolated(r,distance,false),seen=decodeObservation(r.observe());
        assert.ok(seen.nests.some(site=>site.id===nest.id),'the gun itself reveals the nest');
        await r.dispatch(1,r.command('match','advance'));const after=state(r),gun=after.buildings.find(b=>b.id===id);
        assert.ok(after.nests.find(n=>n.id===nest.id).hp<nest.hp);assert.equal(gun.cooldown,8);
        assert.deepEqual([gun.aimX,gun.aimY],[nest.x*40+20,nest.y*40+20]);assert.equal(after.spent,world.spent);
        const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);
      }finally{await r.close();}
    }
  });
  await test('self observation does not reveal or shoot a nest beyond the six-cell gun range',async()=>{
    const r=await fresh();try {
      const {nest,id}=await isolated(r,7,false);
      assert.equal(decodeObservation(r.observe()).nests.some(site=>site.id===nest.id),false);
      await r.dispatch(1,r.command('match','advance'));const after=state(r);
      assert.equal(after.nests.find(n=>n.id===nest.id).hp,nest.hp);assert.equal(after.buildings.find(b=>b.id===id).cooldown,0);
    }finally{await r.close();}
  });
  await test('a visible enemy behind intact rock remains unharmed by an isolated turret',async()=>{
    const r=await fresh();try {
      const saved=r.snapshot(1),world=state(r),hub=world.surveys[0];
      await restoreColony(r,{...world,started:true,outcome:4});
      const terrain=new Map(decodeObservation(r.observe()).tiles.map(tile=>[tile.cell,tile]));await r.restore(1,saved);
      let encounter;
      for(const tile of terrain.values()) {
        const x=tile.cell%MAP_WIDTH,y=Math.floor(tile.cell/MAP_WIDTH);
        if(tile.terrain!==1||tile.depositRate||Math.hypot(x-hub.x,y-hub.y)>10)continue;
        for(const [dx,dy]of[[1,0],[-1,0],[0,1],[0,-1]]) {
          const target=terrain.get(cell(x+dx*5,y+dy*5));
          if(target?.terrain===1&&[1,2,3,4].some(i=>terrain.get(cell(x+dx*i,y+dy*i))?.terrain===0))
            encounter??={x,y,tx:x+dx*5,ty:y+dy*5};
        }
      }
      assert.ok(encounter,'seed has a real rock barrier between ground endpoints');const {x,y,tx,ty}=encounter,id=world.nextId++;
      world.started=true;world.ore-=50;world.spent+=50;
      world.buildings=[{id,kind:2,x,y,level:1,hp:100,stock:0,stage:2,cooldown:0,
        aimX:x*40+20,aimY:y*40+20,armed:0,source:0,moveX:-1,moveY:-1}];
      const enemyId=world.nextId++;world.enemies=[{id:enemyId,x:tx*40+20,y:ty*40+20,hp:500,kind:0,target:id,path:[]}];
      world.surveys.push({x,y,radius:6});await restoreColony(r,world);
      assert.ok(decodeObservation(r.observe()).enemies.some(enemy=>enemy.id===enemyId));
      await r.dispatch(1,r.command('match','advance'));assert.equal(state(r).enemies.find(enemy=>enemy.id===enemyId).hp,500);
      assert.equal(state(r).buildings[0].cooldown,0);
    }finally{await r.close();}
  });
}
if(process.argv[1]===import.meta.filename){
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};
  let count=0;await checkTurretVision(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);console.log(`${count} isolated turret vision groups passed`);
}
