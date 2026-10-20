// Bounded encounters establish access and exhaustion boundaries; actual compiled
// reducers own combat, construction, mining, threat, restore and observations.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {readRecord,saveContract} from '../../src/application/indexeddb.mjs';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {decodeObservation} from '../../apps/siegework/headless.mjs';
import {MAP_WIDTH,MAP_HEIGHT,colony,client,colonyBalance,restoreColony,restoreClient} from './colony-state.mjs';

const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json')));
const bytes=readFileSync(join(directory,manifest.module)),state=r=>colony(r.snapshot(1));
const cell=site=>site.x+site.y*MAP_WIDTH,reserve=(world,site)=>world.deposits.find(d=>d.cell===cell(site));
const send=(r,name,args=[])=>r.dispatch(1,r.command('match',name,args));
const observe=r=>decodeObservation(r.observe());
let passed=0;
async function test(name,run){await run();console.log(`ok ${++passed} - ${name}`);}
async function fresh(){const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);r.uiBridge.resize(936,608);return r;}
async function advance(r,count=1){for(let n=0;n<count;n++)await send(r,'advance');}
function structure(world,kind,x,y,stage=2){
  const site={id:world.nextId++,kind,x,y,level:1,hp:kind===1?140:kind===2?100:90,stock:0,stage,cooldown:0,
    aimX:x*40+20,aimY:y*40+20,armed:0,source:0,moveX:-1,moveY:-1};
  world.buildings.push(site);world.surveys.unshift({x,y,radius:kind===2?6:7});
  const cost=kind===2?50:25;world.spent+=cost;world.ore-=cost;world.started=true;return site;
}
function workerAt(bot,site,job=0,target=0){return {...bot,x:site.x*40+20,y:site.y*40+20,job,target,cargo:0,timer:0,path:[],order:0,source:0,flight:[]};}
function assertBalance(world){const sums=colonyBalance(world);assert.equal(world.ore,sums.bank);assert.equal(world.produced,sums.raw);}
function node(value,key){if(value.key===key)return value;for(const child of value.children){const found=node(child,key);if(found)return found;}}
async function center(r,site){await restoreClient(r,{...client(r.snapshot(2)),cameraX:site.x*1000,cameraY:site.y*1000,homing:false});}
async function surveyedWorld(r,world){
  await restoreColony(r,{...world,started:true,hull:0,outcome:1});
  const terrain=observe(r).tiles;
  world.surveys.push(...terrain.filter(t=>t.terrain===1&&t.cell%8===0&&Math.floor(t.cell/MAP_WIDTH)%8===0)
    .map(t=>({x:t.cell%MAP_WIDTH,y:Math.floor(t.cell/MAP_WIDTH),radius:10})));
  await restoreColony(r,world);return world;
}

await test('a real nest kill reveals one existing rich reserve; workers build, mine and exhaust it without a payout',async()=>{
  const r=await fresh();try{
    const w=await surveyedWorld(r,state(r)),nest=w.nests[0],site=structure(w,2,nest.x,nest.y+4);
    nest.hp=6;w.tick=9;await restoreColony(r,w);
    const before=observe(r).tiles.find(t=>t.cell===cell(nest));assert.equal(before.depositRate,0);assert.equal(before.oreRemaining,0);
    await send(r,'extract',[nest.x,nest.y]);assert.equal(state(r).notice,3);
    const stored=reserve(state(r),nest).remaining;assert.equal(stored,2400);
    await advance(r);let killed=state(r);assert.equal(killed.nests[0].hp,0);assert.equal(killed.ore,w.ore);assert.equal(killed.produced,0);
    assert.equal(reserve(killed,nest).remaining,stored);
    const exposed=observe(r).tiles.find(t=>t.cell===cell(nest));assert.equal(exposed.depositRate,8);assert.equal(exposed.oreRemaining,2400);
    await center(r,nest);const local=client(r.snapshot(2));await restoreClient(r,{...local,cursorX:nest.x,cursorY:nest.y});
    await r.dispatch(2,r.command('client','confirm'));assert.match(node(r.view().ui,'context-title').text,/deposit|ore/i);
    await send(r,'extract',[nest.x,nest.y]);assert.equal(state(r).notice,10);
    for(let step=0;step<500&&state(r).produced===0;step++)await advance(r);
    const mined=state(r),mine=mined.buildings.find(b=>b.kind===1);assert.equal(mine.stage,2);assert.ok(mined.produced>0);
    assert.equal(reserve(mined,nest).remaining,2400-mined.produced);assertBalance(mined);
    // Establish a final partial withdrawal without inventing collected material.
    const final=state(r),deposit=reserve(final,nest),removed=deposit.remaining-5;
    deposit.remaining=5;final.produced+=removed;final.lostOre+=removed;final.tick=19;final.lastRevealTick=-100;final.enemies=[];
    // Preserve any hauled ore by settling it into the hub ledger before placing workers.
    for(const bot of final.bots)if(bot.cargo){final.delivered+=bot.cargo;final.ore+=bot.cargo;}
    final.bots=final.bots.map((b,index)=>workerAt(b,nest,index===0?8:0,index===0?mine.id:0));
    final.buildings.find(b=>b.id===mine.id).stock=0;
    // Production may have left stock; account for it explicitly as loss.
    const difference=final.produced-colonyBalance(final).raw;final.lostOre+=difference;
    await restoreColony(r,final);await advance(r);const exhausted=state(r);
    assert.equal(reserve(exhausted,nest).remaining,0);assert.equal(exhausted.produced,final.produced+5);assertBalance(exhausted);
    const saved=r.snapshot(1);await r.restore(1,saved);await advance(r,30);assert.equal(state(r).produced,exhausted.produced);
    assert.equal(reserve(state(r),nest).remaining,0);assert.equal(state(r).nests[0].hp,0);
    assert.ok(state(r).buildings.some(b=>b.id===site.id));
  }finally{await r.close();}
});

await test('defeat reveals all map facts without survey growth, allows inspection and freezes gameplay purchases',async()=>{
  const r=await fresh();try{
    const w=state(r),nest=w.nests[1];w.started=true;w.tick=9;w.hull=1;
    w.enemies=[{id:w.nextId++,x:w.surveys[0].x*40+20,y:w.surveys[0].y*40+20,hp:80,kind:0,target:0,path:[]},
      {id:w.nextId++,x:nest.x*40+20,y:nest.y*40+20,hp:80,kind:0,target:0,path:[]}];
    await restoreColony(r,w);await center(r,nest);
    const playing=observe(r),beforeScene=r.view().scene;assert.equal(playing.enemies.length,1);assert.ok(playing.tiles.length<(MAP_WIDTH*MAP_HEIGHT));
    const surveys=structuredClone(w.surveys);await advance(r);const ended=state(r);assert.equal(ended.outcome,1);
    const known=observe(r);assert.equal(known.tiles.length,(MAP_WIDTH*MAP_HEIGHT));assert.ok(known.tiles.every(t=>t.visible===1));
    assert.equal(known.nests.length,3);assert.equal(known.enemies.length,2);assert.deepEqual(known.buildCandidates,[]);
    assert.deepEqual(ended.surveys,surveys);assert.ok(r.snapshot(1).length<5000,'no persisted per-cell reveal history');
    const revealed=r.view().scene;assert.notEqual(revealed.batches.find(b=>b.key===1).transforms,beforeScene.batches.find(b=>b.key===1).transforms);
    assert.ok(revealed.batches.find(b=>b.key===1).transforms.length>beforeScene.batches.find(b=>b.key===1).transforms.length);
    const same=r.snapshot(1);await advance(r,20);assert.deepEqual(r.snapshot(1),same);
    for(const [name,args] of [['extract',[nest.x,nest.y]],['fortify',[0,0]],['observe',[0,0]],['fabricate-worker',[]],
      ['repair-hub',[]],['upgrade',[w.surveys[0].x,w.surveys[0].y]],['cancel-building',[0,0]],['relocate-building',[0,1]]]){
      await send(r,name,args);const next=state(r);assert.deepEqual({...next,notice:ended.notice},ended);
    }
    const committed=r.snapshot(1);await center(r,{x:0,y:0});r.view();await center(r,{x:63,y:63});r.view();assert.deepEqual(r.snapshot(1),committed);
  }finally{await r.close();}
});

await test('World15 refuses old geography and incomplete current deposit records without replacing live state',async()=>{
  const r=await fresh();try{
    const saved=r.snapshot(1);
    assert.equal(saved[0],15);assert.equal(r.manifest.settings.id,'siegework-colony-v15');
    for(const name of ['siegework-world12.json','siegework-world12-revision1.json','siegework-world13.json','siegework-world14.json']){
      const fixture=JSON.parse(readFileSync(new URL('./fixtures/'+name,import.meta.url)));
      assert.throws(()=>readRecord(fixture.record,r.manifest.settings.id,saveContract(r.manifest)));
      await assert.rejects(()=>r.restore(1,fixture.record.snapshot.state));assert.deepEqual(r.snapshot(1),saved);
    }
    await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);assertBalance(state(r));
    for(const edit of [w=>w.deposits.pop(),w=>w.deposits.reverse(),w=>w.deposits[0].cell++,w=>w.deposits.push(w.deposits[0])]){
      const broken=state(r);edit(broken);await assert.rejects(()=>restoreColony(r,broken),WebAssembly.RuntimeError);
      assert.deepEqual(r.snapshot(1),saved);
    }
  }finally{await r.close();}
});

await test('cleared fronts subtract two strength levels each while preserving real wave timing and existing wounds',async()=>{
  const r=await fresh();try{
    for(const [dead,tick,tier,elapsed,span,seconds] of [[1,10,1,10,2700,269],[1,1799,1,1799,2700,91],
      [1,1800,1,1800,2700,90],[1,2699,1,2699,2700,1],[1,2700,2,0,900,90],
      [2,3599,1,3599,4500,91],[2,4500,2,0,900,90],[1,35999,38,899,900,1],
      [1,36000,39,1,1,0],[2,43200,37,1,1,0]]){
      const w=state(r);w.started=true;w.tick=tick;w.lastRevealTick=-100;
      w.nests.forEach((nest,index)=>nest.hp=index<dead?0:900);w.enemies=[];
      await restoreColony(r,w);const dial=node(r.view().ui,'difficulty');
      assert.equal(dial.text,String(tier));assert.equal(dial.properties[3],elapsed);assert.equal(dial.properties[5],span);
      assert.equal(dial.help,seconds?`Difficulty ${tier}; increases in ${seconds} seconds`:'Maximum difficulty reached');
    }
    for(const [dead,tick,rank] of [[1,1050,0],[1,2850,1],[2,4650,1],[1,5400,4],[1,10800,6]]){
      const w=state(r);w.started=true;w.tick=tick-1;w.lastRevealTick=-100;w.enemies=[];
      w.nests.forEach((nest,index)=>nest.hp=index<dead?0:900);
      await restoreColony(r,w);await advance(r);const spawned=state(r);
      assert.equal(spawned.tick,tick);assert.ok(spawned.enemies.length>0);
      assert.ok(spawned.enemies.every(enemy=>enemy.rank<=rank));
      const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);
      await advance(r);assert.equal(state(r).enemies.length,spawned.enemies.length);
    }
    const w=state(r);w.tick=36000;w.enemies[0].hp=7;const maximum=w.enemies[0].maxHp;
    w.nests[1].hp=0;await restoreColony(r,w);await advance(r);
    assert.equal(state(r).enemies[0].hp,7);assert.equal(state(r).enemies[0].maxHp,maximum);
  }finally{await r.close();}
});

await test('importing a different cleared front invalidates cached reserve geometry even when the clear count is unchanged',async()=>{
  const r=await fresh();try{
    const w=state(r);w.started=true;w.nests.forEach(n=>w.surveys.push({x:n.x,y:n.y,radius:4}));
    w.nests[0].hp=0;await restoreColony(r,w);await center(r,w.nests[0]);
    const before=Array.from(r.view().scene.batches.find(b=>b.key===7).transforms),nest=w.nests[0];
    const containsSite=transforms=>transforms.some((_,index)=>index%12===3
      &&Math.abs(transforms[index]-nest.x)<1e-6&&Math.abs(transforms[index+4]+nest.y)<1e-6);
    assert.ok(containsSite(before),'cleared front has a crystal instance at its reserve');
    w.nests[0].hp=900;w.nests[1].hp=0;await restoreColony(r,w);
    const after=Array.from(r.view().scene.batches.find(b=>b.key===7).transforms);
    assert.notDeepEqual(after,before);assert.equal(containsSite(after),false,'the sealed reserve loses its crystal instance');
  }finally{await r.close();}
});

console.log(`${passed} nest reward and defeat checks passed`);
