// Actual World12 transitions own paid hub expansion, capacity and ore refunds.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,colonyBalance,restoreColony,fixtureCall,setWorker,addEnemy, withdrawReserves} from './colony-state.mjs';
const state=r=>colony(r.snapshot(1)),call=fixtureCall;
const expanding=bot=>[14,15].includes(bot.job)||(bot.job===7&&bot.timer===14);
function node(r,key,value=r.view().ui){if(value.key===key)return value;for(const child of value.children){const found=node(r,key,child);if(found)return found;}}
function fund(world,amount){withdrawReserves(world, amount);world.delivered+=amount;world.ore+=amount;return world;}
function population(world,count){
  while(world.bots.length<count){world.bots.push({...world.bots[0],id:world.nextId++});setWorker(world,world.bots.length-1);world.spent+=25;fund(world,25);world.ore-=25;}
  return world;
}
async function advance(r,count=1){for(let i=0;i<count;i++){await call(r,'advance');const w=state(r),balance=colonyBalance(w);assert.equal(w.ore,balance.bank);assert.equal(w.produced,balance.raw);}}
async function roundTrip(r){const saved=r.snapshot(1);await r.restore(1,saved);assert.deepEqual(r.snapshot(1),saved);}
async function upgrade(r){await call(r,'upgrade',[8,22]);}
async function running(fresh){const r=await fresh(),world=state(r);world.started=true;await restoreColony(r,world);return r;}
async function opened(fresh){const r=await fresh();await call(r,'extract',[12,20]);await call(r,'cancel-building',[12,20]);return r;}
function waitingForEconomy(r){
  const world=state(r);assert.equal(world.buildings[0].stage,0,'paid tower waits for a construction worker');
  assert.equal(world.bots.filter(expanding).length,1);assert.ok(world.bots.every(bot=>bot.order===0));
  assert.equal(world.ore,35);assert.equal(world.spent,125);
}
export async function checkHubCapacity(test,fresh,bytes){
  await test('assembling a hub expansion reserves the labor budget until its worker finishes',async()=>{
    const r=await opened(fresh);await upgrade(r);assert.equal(state(r).bots[0].job,15);
    await call(r,'observe',[12,22]);waitingForEconomy(r);await roundTrip(r);
    await advance(r,29);waitingForEconomy(r);assert.equal(state(r).hubCapacityLevel,0);
    await advance(r,2);assert.equal(state(r).hubCapacityLevel,1);assert.ok(!state(r).bots.some(expanding));
    assert.ok(state(r).buildings[0].stage>0,'the completed expansion releases its worker for the paid tower');
    assert.equal(state(r).bots.filter(bot=>bot.order>0||[3,5,11].includes(bot.job)).length,1);
    assert.equal(state(r).ore,35);assert.equal(state(r).spent,125);await roundTrip(r);await r.close();
  });
  for(const phase of ['returning','fleeing'])await test(`a ${phase} hub expansion still reserves the construction labor budget`,async()=>{
    const r=await opened(fresh),away=state(r);away.bots.forEach((bot,index)=>setWorker(away,index,{x:12,y:20}));
    await restoreColony(r,away);await upgrade(r);assert.equal(state(r).bots[0].job,14);
    if(phase==='fleeing'){
      const interrupted=state(r);Object.assign(interrupted.bots[0],{job:7,timer:14,path:[]});await restoreColony(r,interrupted);
    }
    await call(r,'observe',[12,22]);waitingForEconomy(r);await roundTrip(r);
    await advance(r);waitingForEconomy(r);await upgrade(r);assert.equal(state(r).notice,35);
    assert.equal(state(r).spent,125);await roundTrip(r);await r.close();
  });
  await test('six paid hub expansions double prices and stop at24 without creating workers',async()=>{
    const r=await running(fresh);await restoreColony(r,fund(state(r),6400));const initial=state(r).ore;let spent=0;
    for(const [level,price]of[100,200,400,800,1600,3200].entries()){
      await upgrade(r);spent+=price;assert.equal(state(r).ore,initial-spent);assert.equal(state(r).spent,spent);
      assert.equal(state(r).hubCapacityLevel,level);assert.equal(state(r).bots.filter(expanding).length,1);
      assert.equal(state(r).bots.find(expanding).target,price);assert.equal(state(r).bots.find(expanding).timer,30);
      await upgrade(r);assert.equal(state(r).notice,35);assert.equal(state(r).spent,spent);
      await advance(r,29);assert.equal(state(r).hubCapacityLevel,level);await advance(r);
      assert.equal(state(r).hubCapacityLevel,level+1);assert.equal(state(r).bots.length,3);assert.ok(!state(r).bots.some(expanding));await roundTrip(r);
    }
    assert.equal(spent,6300);const before=state(r);await upgrade(r);assert.deepEqual(state(r),{...before,notice:36});
    assert.match(node(r,'worker-capacity').text,/3 \/ 24/);await restoreColony(r,population(state(r),23));
    await call(r,'fabricate-worker');assert.match(node(r,'worker-capacity').text,/24 \/ 24/);const bank=state(r).ore;
    await call(r,'fabricate-worker');assert.equal(state(r).notice,8);assert.equal(state(r).ore,bank);await advance(r,30);assert.equal(state(r).bots.length,24);await roundTrip(r);await r.close();
  });
  await test('pending upgrades grant no slots; pending hires reserve completed capacity and still require assembly',async()=>{
    const r=await running(fresh);await restoreColony(r,population(state(r),12));await upgrade(r);
    await call(r,'fabricate-worker');assert.equal(state(r).notice,8);assert.match(node(r,'worker-capacity').text,/12 \/ 12/);
    await advance(r,30);assert.match(node(r,'worker-capacity').text,/12 \/ 14/);
    for(let i=0;i<2;i++)await call(r,'fabricate-worker');assert.equal(state(r).bots.length,12);assert.equal(state(r).ore,10);
    assert.match(node(r,'worker-capacity').text,/14 \/ 14/);await call(r,'fabricate-worker');assert.equal(state(r).notice,8);assert.equal(state(r).ore,10);
    await roundTrip(r);await advance(r,30);assert.equal(state(r).bots.length,14);assert.equal(state(r).spent,375);await r.close();
  });
  await test('unaffordable and unstaffed upgrades preserve ore and create no pending order',async()=>{
    const r=await running(fresh),poor=state(r);poor.ore=99;poor.spent=61;await restoreColony(r,poor);await upgrade(r);
    assert.deepEqual(state(r),{...poor,notice:7});await restoreColony(r,fund(state(r),200));
    for(let i=0;i<3;i++)await call(r,'fabricate-worker');const before=state(r);await upgrade(r);
    assert.deepEqual(state(r),{...before,notice:27});assert.ok(!state(r).bots.some(expanding));await r.close();
  });
  await test('travelling expansion delivers ordinary cargo and survives reload, code replacement and pause',async()=>{
    const r=await running(fresh),world=state(r);world.bots.length=1;withdrawReserves(world, (16) - world.produced);
    setWorker(world,0,{x:12,y:20,job:2,cargo:16,path:[971,970,969,968,1016,1064]});await restoreColony(r,world);await upgrade(r);
    assert.equal(state(r).bots[0].job,14);assert.equal(state(r).bots[0].cargo,16);assert.equal(state(r).ore,60);await roundTrip(r);
    const before=r.snapshot(1);await r.replace(r.prepare(bytes,r.manifest));
    assert.deepEqual(r.snapshot(1),before);
    for(let i=0;i<200&&state(r).bots[0].job!==15;i++)await advance(r);
    assert.equal(state(r).bots[0].job,15);assert.equal(state(r).delivered,16);assert.equal(state(r).ore,76);assert.equal(state(r).bots[0].timer,30);
    await call(r,'pause-colony',[1]);const paused=r.snapshot(1);await advance(r,40);assert.deepEqual(r.snapshot(1),paused);await roundTrip(r);
    await call(r,'pause-colony',[0]);await advance(r,30);assert.equal(state(r).hubCapacityLevel,1);assert.equal(state(r).bots.length,1);await r.close();
  });
  await test('a fleeing expansion remains unique and death refunds its price once while carried ore is lost',async()=>{
    const r=await running(fresh),world=state(r);world.bots.length=1;withdrawReserves(world, (16) - world.produced);
    setWorker(world,0,{x:12,y:20,job:2,cargo:16,path:[971,970,969,968,1016,1064]});await restoreColony(r,world);await upgrade(r);
    const fleeing=state(r);Object.assign(fleeing.bots[0],{job:7,timer:14,path:[],hp:7});fleeing.tick=9;await restoreColony(r,fleeing);
    await upgrade(r);assert.equal(state(r).notice,35);assert.equal(state(r).spent,100);await roundTrip(r);
    await addEnemy(r,{x:12,y:20});await advance(r);assert.equal(state(r).hubCapacityLevel,0);assert.equal(state(r).ore,160);assert.equal(state(r).spent,0);assert.equal(state(r).lostOre,16);
    assert.equal(state(r).casualties,1);await advance(r,5);assert.equal(state(r).ore,160);await roundTrip(r);await r.close();
  });
  await test('the decoder rejects impossible hub tiers, unpaid investment and conflicting pending owners atomically',async()=>{
    const r=await running(fresh);await upgrade(r);const saved=r.snapshot(1);
    const edits=[w=>w.hubCapacityLevel=-1,w=>w.hubCapacityLevel=7,w=>w.hubCapacityLevel=6,
      w=>w.bots.find(expanding).target=200,w=>w.bots.find(expanding).timer=0,
      w=>w.bots.find(expanding).cargo=1,w=>w.bots.find(expanding).x+=40,
      w=>{Object.assign(w.bots[1],w.bots[0],{id:w.bots[1].id});},
      w=>{w.spent--;w.ore++;},w=>population(w,13)];
    for(const edit of edits){const invalid=colony(saved);edit(invalid);await assert.rejects(()=>restoreColony(r,invalid),WebAssembly.RuntimeError);assert.deepEqual(r.snapshot(1),saved);}
    await advance(r,30);const completed=r.snapshot(1),unpaid=state(r);unpaid.spent=0;unpaid.ore=160;
    await assert.rejects(()=>restoreColony(r,unpaid),WebAssembly.RuntimeError);assert.deepEqual(r.snapshot(1),completed);await r.close();
  });
  await test('hub controls expose prices and retain repeated hiring; house construction is absent',async()=>{
    const r=await running(fresh);await r.dispatch(2,r.command('client','home'));assert.ok(node(r,'worker'));assert.ok(node(r,'upgrade'));assert.ok(node(r,'repair'));
    assert.match(node(r,'context-description').text,/12 → 14/);assert.match(node(r,'upgrade-caption').text,/100 ore/);
    await upgrade(r);assert.equal(node(r,'upgrade').properties[1],0);assert.match(node(r,'context-description').text,/100 ore paid/);
    await call(r,'fabricate-worker');assert.ok(node(r,'worker'));await call(r,'fabricate-worker');assert.ok(node(r,'worker'));assert.equal(state(r).ore,10);
    assert.ok(!r.manifest.applications.find(app=>app.owner==='match').handlers.some(h=>['build-house','build-wall'].includes(h.binding)));
    const before=state(r);await call(r,'build-cell',[4,0]);assert.deepEqual(state(r),before);await r.close();
  });
}
if(process.argv[1]===import.meta.filename){const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};let count=0;await checkHubCapacity(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh,bytes);console.log(`${count} hub capacity checks passed`);}
