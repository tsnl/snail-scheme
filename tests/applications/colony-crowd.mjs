// Linked Scheme reducers own separation, route splicing and combat. Fixtures
// only supply valid starting populations and ordinary adjacent walking paths.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {establishColony,colony,restoreColony,fixtureCall,pixelAt,routeCell,setWorker} from './colony-state.mjs';

export async function checkCrowd(test,fresh,bytes) {
  const state=r=>colony(r.snapshot(1)),call=fixtureCall;
  const span=(enemies,axis)=>Math.max(...enemies.map(enemy=>enemy[axis]))-Math.min(...enemies.map(enemy=>enemy[axis]));
  const line=(world,x,y,dx,dy,count)=>Array.from({length:count},(_,i)=>routeCell(world,x+dx*(i+1),y+dy*(i+1)));
  function crowd(world,count,point,path,extra={}) {
    world.started=true;
    world.enemies=Array.from({length:count},()=>({id:world.nextId++,...point,hp:80,kind:0,target:0,path:[...path],...extra}));
    return world;
  }
  async function advance(r,count=1) {
    for(let i=0;i<count;i++)await call(r,'advance');
  }
  async function approach(count) {
    const r=await fresh(),world=state(r),point=pixelAt(world,20,22);
    await restoreColony(r,crowd(world,count,point,line(world,20,22,-1,0,12)));
    let width=0;
    for(let i=0;i<64;i++) {
      await advance(r); width=Math.max(width,span(state(r).enemies,'y'));
      assert.ok(state(r).enemies.every(enemy=>enemy.path.length<=14));
    }
    assert.ok(state(r).enemies.every(enemy=>enemy.x<=point.x-160),'every member keeps advancing');
    for(let i=0;i<160&&state(r).hull===300;i++)await advance(r);
    assert.ok(state(r).hull<300,'the spread crowd reaches and attacks the hub');
    await r.close();return width;
  }
  await test('isolated enemies retain exact speed and cell-center route completion',async()=>{
    for(const [kind,speed] of [[0,5],[1,7],[2,5]]) {
      const r=await fresh(),world=state(r),point=pixelAt(world,20,22),path=line(world,20,22,-1,0,12);
      await restoreColony(r,crowd(world,1,point,path,{kind}));await advance(r);
      assert.deepEqual([state(r).enemies[0].x,state(r).enemies[0].y],[point.x-speed,point.y]);
      await advance(r,Math.ceil(40/speed)-1);
      assert.equal(state(r).enemies[0].x,point.x-40);assert.deepEqual(state(r).enemies[0].path,path.slice(1));
      await r.close();
    }
  });
  await test('larger overlapping groups occupy wider lanes and still reach their target',async()=>{
    const small=await approach(2),large=await approach(16);
    assert.ok(small>=40,`two enemies separate into neighboring cells: ${small}`);
    assert.ok(large===80&&large>small,`large crowd width ${large} exceeds small crowd width ${small}`);
    console.log(`crowd approach widths: 2 enemies ${small}px, 16 enemies ${large}px`);
  });
  await test('crowd movement is independent of list order and survives pause, restore and replacement',async()=>{
    const r=await fresh(),copy=await fresh(),world=state(r);
    crowd(world,16,pixelAt(world,20,22),line(world,20,22,-1,0,12));await restoreColony(r,world);
    world.enemies.reverse();await restoreColony(copy,world);await advance(r,48);await advance(copy,48);
    const reordered=state(copy);reordered.enemies.reverse();assert.deepEqual(state(r),reordered);
    await call(r,'pause-colony',[1]);const saved=r.snapshot(1);await advance(r,8);assert.deepEqual(r.snapshot(1),saved);
    await r.replace(r.prepare(bytes,r.manifest));assert.deepEqual(r.snapshot(1),saved);
    await copy.restore(1,saved);assert.deepEqual(copy.snapshot(1),saved);
    await call(r,'pause-colony',[0]);await call(copy,'pause-colony',[0]);await advance(r,32);await advance(copy,32);
    assert.deepEqual(r.snapshot(1),copy.snapshot(1));await r.close();await copy.close();
  });
  await test('ordinary and fast enemies finish a saved lane before choosing another detour',async()=>{
    for(const [kind,speed] of [[0,5],[1,7]]) {
      const r=await fresh(),world=state(r),point=pixelAt(world,20,22),path=line(world,20,22,-1,0,12);
      crowd(world,16,point,path,{kind});const id=world.enemies[0].id,cellTicks=Math.ceil(40/speed);
      await restoreColony(r,world);await advance(r,cellTicks);
      const side=state(r).enemies.find(enemy=>enemy.id===id);
      assert.deepEqual([side.x,side.y],[point.x,point.y-40]);
      const saved=r.snapshot(1);await r.restore(1,saved);await r.replace(r.prepare(bytes,r.manifest));
      assert.deepEqual(r.snapshot(1),saved);await advance(r);
      const forward=state(r).enemies.find(enemy=>enemy.id===id);
      assert.deepEqual([forward.x,forward.y],[point.x-speed,point.y-40]);
      await advance(r,9*cellTicks-1);const joined=state(r).enemies.find(enemy=>enemy.id===id);
      assert.deepEqual([joined.x,joined.y],[point.x-320,point.y]);assert.deepEqual(joined.path,path.slice(8));
      await r.close();
    }
  });
  await test('lake banks reject sideways crowd lanes without interrupting forward movement',async()=>{
    const r=await fresh(),world=state(r),point={x:73*40+20,y:8*40+20};
    const path=Array.from({length:20},(_,i)=>73+(9+i)*128);
    await restoreColony(r,crowd(world,16,point,path));let width=0;
    for(let i=0;i<80;i++) {
      await advance(r);const enemies=state(r).enemies;width=Math.max(width,span(enemies,'x'));
      assert.ok(enemies.every(enemy=>enemy.x<=point.x),'the lake rejects the eastern parallel lane');
      if(i%16===0){const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);}
    }
    assert.equal(width,40);assert.ok(state(r).enemies.every(enemy=>enemy.y>point.y+160));await r.close();
  });
  await test('a crowd cooperates on rock and traverses the saved one-cell breach',async()=>{
    const r=await fresh(),world=state(r),point=pixelAt(world,6,11),cell=routeCell(world,6,10);
    await restoreColony(r,crowd(world,8,point,line(world,6,11,0,-1,9),{burrower:true}));
    await advance(r,39);assert.deepEqual(state(r).excavations,[{cell,remaining:2}]);assert.deepEqual(state(r).breaches,[]);
    assert.ok(state(r).enemies.every(enemy=>enemy.x===point.x&&enemy.y===point.y));
    await advance(r);assert.deepEqual(state(r).breaches,[cell]);assert.deepEqual(state(r).excavations,[]);
    await advance(r,24);assert.ok(state(r).enemies.every(enemy=>enemy.x===point.x&&enemy.y<point.y-80));
    const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);await r.close();
  });
  await test('spread crowds can destroy an ordinary tower while approaching the hub',async()=>{
    const r=await fresh();await call(r,'observe',[10,22]);
    for(let i=0;i<80&&state(r).buildings[0].stage!==2;i++)await advance(r);
    const world=state(r),tower=world.buildings[0];assert.equal(tower.stage,2);world.tick=0;world.lastRevealTick=-100;
    for(let i=0;i<world.bots.length;i++)setWorker(world,i);
    await restoreColony(r,crowd(world,4,pixelAt(world,20,22),line(world,20,22,-1,0,12)));
    let attacked=false;
    for(let i=0;i<280&&state(r).buildings.some(site=>site.id===tower.id);i++) {
      await advance(r);const after=state(r),standing=after.buildings.find(site=>site.id===tower.id);
      attacked ||= !standing||standing.hp<tower.hp;
    }
    assert.ok(attacked);assert.ok(!state(r).buildings.some(site=>site.id===tower.id));
    assert.ok(state(r).alerts.some(alert=>alert.kind===3));await r.close();
  });
  await test('a full 1024-cell route waits for space before adding its two lane steps',async()=>{
    const r=await fresh(),world=state(r),point=pixelAt(world,20,22);
    const path=[...line(world,20,22,-1,0,12),...Array.from({length:1012},(_,i)=>routeCell(world,8,i%2===0?23:22))];
    await restoreColony(r,crowd(world,8,point,path));await advance(r);
    assert.ok(state(r).enemies.every(enemy=>enemy.y===point.y&&enemy.path.length===1024));
    await advance(r,16);assert.ok(state(r).enemies.some(enemy=>enemy.y!==point.y&&enemy.path.length===1024));
    assert.ok(state(r).enemies.every(enemy=>enemy.path.length<=1024));
    const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);await r.close();
  });
  await test('the 128-enemy bound keeps real crowd transitions and serialized paths bounded',async()=>{
    const r=await fresh(),world=state(r),point=pixelAt(world,15,12);
    await restoreColony(r,crowd(world,128,point,line(world,15,12,0,1,23)));
    const times=[];
    for(let i=0;i<96;i++) {
      const before=performance.now();await advance(r);times.push(performance.now()-before);
      assert.equal(state(r).enemies.length,128);assert.ok(state(r).enemies.every(enemy=>enemy.path.length<=25));
    }
    assert.ok(state(r).enemies.every(enemy=>enemy.y>=point.y+160),'even the dense crowd keeps advancing');
    const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);
    times.sort((a,b)=>a-b);console.log(`128-enemy dispatch median ${times[48].toFixed(2)}ms; p95 ${times[91].toFixed(2)}ms`);
    await r.close();
  });
}

if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json')));
  const bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return establishColony(r);};
  let count=0;await checkCrowd(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh,bytes);
  console.log(`${count} crowd checks passed`);
}
