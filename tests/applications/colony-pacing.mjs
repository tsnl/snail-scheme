// A northward seed-one expedition uses paid public orders, ordinary sight and
// waves. This eager feasibility fixture is not a general scouting AI or a claim
// about a normal player's completion time.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {loadWasm,instantiate,invokeEntry,closeInstance} from '../../src/lofi/compiler/execute.mjs';
import {colony,colonyBalance} from './colony-state.mjs';

const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json')));
const bytes=readFileSync(join(directory,manifest.module)),probe=instantiate(loadWasm(readFileSync(resolve(process.argv[3]))));
const results=[];
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
  const next=colony(runtime.snapshot(1));return next.spent>world.spent;
}

async function place(runtime,world,points,kind) {
  for(const point of points.slice(0,12))
    if(await purchase(runtime,world,'build-cell',[kind,point.x+point.y*width]))return true;
  return false;
}

async function decide(runtime,world,known,direction,nest) {
  const hub=hubOf(world),sites=world.buildings,points=choices(world,known);
  const mines=sites.filter(site=>site.kind===1),guns=sites.filter(site=>site.kind===2),towers=sites.filter(site=>site.kind===3);
  const open=points.filter(point=>point.value===1),progress=point=>forward(point,hub,direction);
  if(!mines.length)return place(runtime,world,points.filter(point=>point.value>=10).sort((a,b)=>square(a,hub)-square(b,hub)),1);
  if(guns.length<2&&world.ore>=50)return place(runtime,world,open.filter(point=>square(point,hub)<=36)
    .sort((a,b)=>progress(b)-progress(a)),2);
  const mine=mines.find(site=>site.level===1&&ready(site));
  if(mine)return world.ore>=40&&purchase(runtime,world,'upgrade',[mine.x,mine.y]);
  if(world.bots.length<6&&world.bots.every(bot=>![4,6].includes(bot.job)))
    return world.ore>=25&&purchase(runtime,world,'fabricate-worker',[]);
  const rich=points.filter(point=>point.value>=30).sort((a,b)=>b.value-a.value||square(a,hub)-square(b,hub));
  if(mines.length<3&&rich.length)return world.ore>=40&&place(runtime,world,rich,1);
  const gun=guns.find(site=>site.level<3&&site.stage===2);
  if(gun&&world.ore>=65)if(await purchase(runtime,world,'upgrade',[gun.x,gun.y]))return true;
  if(!nest&&world.ore>=50&&!towers.some(site=>!ready(site))) {
    const frontier=open.filter(point=>towers.every(site=>square(site,point)>=25));
    if(await place(runtime,world,frontier.sort((a,b)=>progress(b)-progress(a)),3))return true;
  }
  if(world.ore>=75&&guns.length<12) {
    const target=nest??towers.filter(ready).sort((a,b)=>progress(b)-progress(a))[0]??hub;
    const front=open.filter(point=>square(point,target)<=25&&guns.every(site=>square(site,point)>=4));
    if(await place(runtime,world,front.sort((a,b)=>square(a,target)-square(b,target)),2))return true;
  }
  if(world.hull<240&&world.ore>=100)return purchase(runtime,world,'repair-hub',[]);
  return false;
}

for(const seed of [1]) {
  const runtime=new ReducerRuntime();await runtime.replace(runtime.prepare(bytes,manifest));
  await runtime.initialize(1);await runtime.initialize(2);await runtime.dispatch(1,runtime.command('match','new-run-seed',[seed]));
  const known=new Map(),hiddenNest={x:query(3,seed),y:query(4,seed)},checkpoints=[];
  let direction={x:0,y:-1},discovered=null,firstExtraction=null,firstShot=null,world=colony(runtime.snapshot(1));
  for(let tick=0;tick<=7200&&world.outcome===0;tick++) {
    if(tick%20===0) {
      world=colony(runtime.snapshot(1));const nest=observe(world,known,hiddenNest);
      if(nest&&discovered===null)discovered=world.tick;
      await decide(runtime,world,known,direction,discovered===null?null:hiddenNest);
      world=colony(runtime.snapshot(1));const balance=colonyBalance(world);
      assert.equal(world.ore,balance.bank);assert.equal(world.produced,balance.raw);
      if(firstExtraction===null&&world.produced>0)firstExtraction=world.tick;
      if(firstShot===null&&world.nestHp<1500)firstShot=world.tick;
      if(tick%600===0)checkpoints.push({minute:world.tick/600,ore:world.ore,produced:world.produced,spent:world.spent,
        hull:world.hull,nestHp:world.nestHp,buildings:world.buildings.length,workers:world.bots.length,kills:world.kills,lost:world.lost,frontier:Math.max(0,...world.buildings.map(site=>Math.sqrt(square(site,hubOf(world))))),mines:world.buildings.filter(site=>site.kind===1).map(site=>site.level)});
    }
    await runtime.dispatch(1,runtime.command('match','advance',[]));
    if(tick%20===19)world=colony(runtime.snapshot(1));
  }
  world=colony(runtime.snapshot(1));await runtime.restore(1,runtime.snapshot(1));
  assert.equal(world.outcome,3,'the paid northward expedition destroys the nest');
  assert.ok(discovered>0&&firstShot>=discovered&&world.tick<6000,'this eager fixture wins within ten minutes');
  assert.ok(world.produced>0&&world.spent>160,'the expedition funds expansion through extraction');
  const result={seed,outcome:world.outcome,minutes:world.tick/600,firstExtraction,discovered,firstShot,
    nestHp:world.nestHp,ore:world.ore,produced:world.produced,spent:world.spent,hull:world.hull,
    casualties:world.casualties,lost:world.lost,kills:world.kills,routeCells:query(5,seed),checkpoints};
  results.push(result);console.log(JSON.stringify(result));await runtime.close();
}
closeInstance(probe);
if(process.argv[4])writeFileSync(process.argv[4],JSON.stringify({generation:manifest.generation,
  policy:'Seed-one northward expedition; visible tiles only; paid public orders every two seconds; no snapshot edits, free ore or removed enemies. This is a feasibility fixture, not a general search strategy or normal-player duration.',results},null,2)+'\n');
