// A three-bearing seed-one expedition uses paid public orders, ordinary sight and
// waves. This paid observation is not a general scouting AI or a claim
// about a normal player's completion time.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {loadWasm,instantiate,invokeEntry,closeInstance} from '../../src/lofi/compiler/execute.mjs';
import {colony,colonyBalance} from './colony-state.mjs';

const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json')));
const bytes=readFileSync(join(directory,manifest.module)),probe=instantiate(loadWasm(readFileSync(resolve(process.argv[3]))));
const results=[],orderJournal=[];
const query=(operation,seed,cell=0)=>invokeEntry(probe,[operation,seed,cell]);
const width=query(6,1),height=query(7,1),square=(a,b)=>(a.x-b.x)**2+(a.y-b.y)**2;
const ready=site=>site.stage===2||site.stage>=4;
const radius=site=>site.kind===4?0:site.kind===3?(site.level===1?7:10):4;
const hubOf=world=>world.surveys.find(survey=>survey.radius===9);
const pixelCell=entity=>({x:(entity.x-20)/40,y:(entity.y-20)/40});

function visible(world,point) {
  return square(hubOf(world),point)<=81||world.buildings.some(site=>ready(site)&&square(site,point)<=radius(site)**2)
    ||world.bots.some(bot=>square(pixelCell(bot),point)<=4);
}

function observe(world,known,nest) {
  for(const center of [hubOf(world),...world.buildings.filter(ready).map(site=>({...site,radius:radius(site)}))])
    for(let y=Math.max(0,center.y-center.radius);y<Math.min(height,center.y+center.radius+1);y++)
      for(let x=Math.max(0,center.x-center.radius);x<Math.min(width,center.x+center.radius+1);x++) {
        const cell=x+y*width;
        if(square(center,{x,y})<=center.radius**2&&!known.has(cell))known.set(cell,{x,y,value:query(0,world.seed,cell)});
      }
  return visible(world,nest)?nest:null;
}

function choices(world,known) {
  const hub=hubOf(world),threats=world.enemies.map(pixelCell).filter(point=>visible(world,point));
  return [...known.values()].filter(point=>point.value%10===1&&visible(world,point)
    &&(Math.abs(point.x-hub.x)>1||Math.abs(point.y-hub.y)>1)
    &&!world.buildings.some(site=>square(site,point)===0)&&!threats.some(enemy=>square(enemy,point)<=16));
}

function forward(point,hub,direction) {return (point.x-hub.x)*direction.x+(point.y-hub.y)*direction.y;}

async function purchase(runtime,world,name,args) {
  await runtime.dispatch(1,runtime.command('match',name,args));
  const next=colony(runtime.snapshot(1));
  if(next.spent!==world.spent)orderJournal.push({tick:world.tick,name,args,price:next.spent-world.spent});
  return next.spent!==world.spent;
}

async function place(runtime,world,points,kind) {
  for(const point of points.slice(0,12))
    if(await purchase(runtime,world,'build-cell',[kind,point.x+point.y*width]))return true;
  return false;
}

const remaining=(world,site)=>world.deposits.find(deposit=>deposit.cell===site.x+site.y*width)?.remaining??0;
const bearing=(point,hub,direction)=>forward(point,hub,direction)-Math.abs((point.x-hub.x)*direction.y-(point.y-hub.y)*direction.x)*0.7;

async function decide(runtime,world,known,direction,nest) {
  const hub=hubOf(world),sites=world.buildings,points=choices(world,known);
  const mines=sites.filter(site=>site.kind===1),guns=sites.filter(site=>site.kind===2),towers=sites.filter(site=>site.kind===3);
  const open=points.filter(point=>point.value===1),progress=point=>bearing(point,hub,direction);
  const abandoned=towers.find(site=>!ready(site)&&!visible(world,site));
  if(abandoned)return purchase(runtime,world,'cancel-building',[abandoned.x,abandoned.y]);
  const resource=points.filter(point=>point.value>=10&&remaining(world,point)>0).sort((a,b)=>square(a,hub)-square(b,hub));
  if(!mines.length)return place(runtime,world,resource,1);
  const upgradeMine=mines.find(site=>site.level===1&&ready(site)&&remaining(world,site)>100);
  if(upgradeMine&&world.ore>=40)return purchase(runtime,world,'upgrade',[upgradeMine.x,upgradeMine.y]);
  const homeGuns=guns.filter(site=>square(site,hub)<=36);
  if(homeGuns.length<3) {
    if(world.ore<50)return false;
    const bearings=[{x:0,y:-1},{x:1,y:0.5},{x:-1,y:0.5}],toward=bearings[homeGuns.length];
    const preferred={x:hub.x+toward.x*3,y:hub.y+toward.y*3};
    return place(runtime,world,open.filter(point=>square(point,hub)<=16).sort((a,b)=>square(a,preferred)-square(b,preferred)),2);
  }
  if(world.ore>=40&&resource.length)return place(runtime,world,resource,1);
  const exposedMine=mines.find(site=>remaining(world,site)>0&&square(site,hub)>81&&guns.every(gun=>square(gun,site)>25));
  if(exposedMine) {
    if(world.ore<50)return false;
    return place(runtime,world,open.filter(point=>square(point,exposedMine)<=9).sort((a,b)=>square(a,exposedMine)-square(b,exposedMine)),2);
  }
  if(world.bots.length<(mines.length>1?6:4)&&world.ore>=65&&world.bots.every(bot=>![4,6].includes(bot.job)))
    return purchase(runtime,world,'fabricate-worker',[]);
  const homeUpgrade=homeGuns.find(site=>site.level<(mines.length>1?3:2)&&site.stage===2);
  if(homeUpgrade&&world.ore>=65)return purchase(runtime,world,'upgrade',[homeUpgrade.x,homeUpgrade.y]);
  if(world.hull<200&&world.ore>=100)return purchase(runtime,world,'repair-hub',[]);
  const forwardTowers=towers.filter(site=>ready(site)&&progress(site)>5).sort((a,b)=>progress(b)-progress(a));
  const frontier=nest??forwardTowers[0];
  if(frontier&&guns.every(site=>!ready(site)||square(site,frontier)>25)) {
    if(world.ore<90||guns.some(site=>!ready(site)&&square(site,frontier)<=25))return false;
    const candidates=open.filter(point=>square(point,frontier)<=9&&progress(point)>=progress(frontier));
    return place(runtime,world,candidates.sort((a,b)=>progress(b)-progress(a)),2);
  }
  const forwardGun=guns.find(site=>site.level<3&&site.stage===2&&progress(site)>5);
  if(forwardGun&&world.ore>=65)return purchase(runtime,world,'upgrade',[forwardGun.x,forwardGun.y]);
  if(nest&&world.ore>=90&&guns.filter(site=>square(site,nest)<=36).length<3) {
    const candidates=open.filter(point=>square(point,nest)<=25);
    if(await place(runtime,world,candidates.sort((a,b)=>square(a,nest)-square(b,nest)),2))return true;
  }
  if(!nest&&world.ore>=65&&!towers.some(site=>!ready(site))) {
    const candidates=open.filter(point=>towers.every(site=>square(site,point)>=25));
    const nextResource=[...known.values()].filter(point=>point.value>=10&&remaining(world,point)>0&&!mines.some(site=>square(site,point)===0))
      .sort((a,b)=>square(a,hub)-square(b,hub))[0];
    const score=nextResource?point=>-square(point,nextResource):progress;
    if(await place(runtime,world,candidates.sort((a,b)=>score(b)-score(a)),3))return true;
  }
  return false;
}

for(const seed of [1]) {
  const runtime=new ReducerRuntime();await runtime.replace(runtime.prepare(bytes,manifest));
  await runtime.initialize(1);await runtime.initialize(2);await runtime.dispatch(1,runtime.command('match','new-run-seed',[seed]));
  const known=new Map(),checkpoints=[],discoveries=new Map(),clearTicks=new Map(),depletionTicks=new Map();
  const bearings=[{x:0,y:-1},{x:1,y:0.5},{x:-1,y:0.5}];
  let firstExtraction=null,firstShot=null,orders=0,world=colony(runtime.snapshot(1));
  const terrainDeposits=[];
  for(let cell=0;cell<width*height;cell++)if(query(0,seed,cell)>=10)terrainDeposits.push({cell,remaining:query(8,seed,cell)});
  assert.deepEqual(world.deposits.toSorted((a,b)=>a.cell-b.cell),terrainDeposits,'saved sites enumerate the independently queried terrain');
  const originalOre=terrainDeposits.reduce((sum,site)=>sum+site.remaining,0);
  for(let tick=0;tick<=7200&&world.outcome===0;tick++) {
    if(tick%20===0) {
      world=colony(runtime.snapshot(1));observe(world,known,world.nests[0]);
      for(const nest of world.nests) {
        if(visible(world,nest)&&!discoveries.has(nest.id))discoveries.set(nest.id,world.tick);
        if(nest.hp===0&&!clearTicks.has(nest.id))clearTicks.set(nest.id,world.tick);
      }
      for(const deposit of world.deposits)if(deposit.remaining===0&&!depletionTicks.has(deposit.cell))depletionTicks.set(deposit.cell,world.tick);
      const front=world.nests.find(nest=>nest.hp>0),direction=bearings[front?.id??0];
      if(await decide(runtime,world,known,direction,front&&discoveries.has(front.id)?front:null))orders++;
      world=colony(runtime.snapshot(1));const balance=colonyBalance(world);
      assert.equal(world.ore,balance.bank);assert.equal(world.produced,balance.raw);
      assert.equal(world.produced+world.deposits.reduce((sum,site)=>sum+site.remaining,0),originalOre);
      if(firstExtraction===null&&world.produced>0)firstExtraction=world.tick;
      if(firstShot===null&&world.nests.some(nest=>nest.hp<900))firstShot=world.tick;
      if(tick%600===0)checkpoints.push({minute:world.tick/600,ore:world.ore,produced:world.produced,delivered:world.delivered,spent:world.spent,
        hull:world.hull,nests:world.nests.map(nest=>nest.hp),sites:world.buildings.map(site=>({x:site.x,y:site.y,kind:site.kind,stage:site.stage,level:site.level})),buildings:world.buildings.length,workers:world.bots.length,kills:world.kills,lost:world.lost,
        mines:world.buildings.filter(site=>site.kind===1).map(site=>({x:site.x,y:site.y,level:site.level,remaining:remaining(world,site)}))});
    }
    await runtime.dispatch(1,runtime.command('match','advance',[]));
    if(tick%20===19)world=colony(runtime.snapshot(1));
  }
  world=colony(runtime.snapshot(1));await runtime.restore(1,runtime.snapshot(1));
  for(const nest of world.nests)if(nest.hp===0&&!clearTicks.has(nest.id))clearTicks.set(nest.id,world.tick);
  assert.ok(world.produced>600&&world.spent>160,'the expedition funds expansion beyond its finite starter');
  assert.ok(depletionTicks.size>0&&checkpoints.some(sample=>sample.mines.length>1),'ordinary orders reach a second mine and exhaust a deposit');
  const result={seed,outcome:world.outcome,minutes:world.tick/600,firstExtraction,discoveries:[...discoveries],firstShot,
    clears:[...clearTicks],depletions:[...depletionTicks],orders,nests:world.nests.map(nest=>nest.hp),ore:world.ore,produced:world.produced,
    delivered:world.delivered,localSpent:world.localSpent,lostOre:world.lostOre,spent:world.spent,hull:world.hull,casualties:world.casualties,lost:world.lost,kills:world.kills,
    orderJournal,routeCells:world.nests.map(nest=>query(5,seed,nest.id)),checkpoints};
  results.push(result);console.log(JSON.stringify(result));await runtime.close();
}
closeInstance(probe);
if(process.argv[4])writeFileSync(process.argv[4],JSON.stringify({generation:manifest.generation,
  policy:'Seed-one north, southeast, southwest expedition; visible tiles only; paid public orders every two seconds; no snapshot edits, free ore or removed enemies. Losses and clear times are reported without requiring victory. Discovery and depletion are observed every two seconds. This is a pressure observation, not a general search strategy or normal-player duration.',results},null,2)+'\n');
