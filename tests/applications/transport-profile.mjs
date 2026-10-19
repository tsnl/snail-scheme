// Instrumented CPU diagnostic, not a frame-rate or isolated algorithm benchmark.
// Each checked seed-1 fixture is a long parent chain over the open home region.
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {performance} from 'node:perf_hooks';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,colonyWords,at,routeCell,restoreColony,fixtureCall} from './colony-state.mjs';

const directory=resolve(process.argv[2]);
const manifest=JSON.parse(readFileSync(join(directory,'manifest.json')));
const bytes=readFileSync(join(directory,manifest.module));
function fixture(world,count) {
  world.produced+=100000;world.delivered+=100000;world.ore+=100000;
  world.started=true;world.tracks=[];world.rails=[];
  const cells=[];
  for(let y=11;y<=30;y++)for(let column=0;column<20;column++) {
    const x=y%2?column+1:20-column;
    if((x>=7&&x<=9&&y>=21&&y<=23)||(x===12&&y===20))continue;
    cells.push([x,y]);
  }
  let parent={id:0,x:8,y:22};
  for(const [x,y] of cells.slice(0,count)) {
    const id=world.nextId++,site={id,kind:3,...at(world,x,y),level:1,hp:90,stock:0,stage:2,cooldown:0,
      aimX:at(world,x,y).x*40+20,aimY:at(world,x,y).y*40+20,armed:0,source:0,moveX:-1,moveY:-1};
    world.buildings.push(site);world.surveys.push({...at(world,x,y),radius:7});world.spent+=25;world.ore-=25;
    const path=[routeCell(world,x,y)];let px=x,py=y;
    while(py!==parent.y){py+=Math.sign(parent.y-py);path.push(routeCell(world,px,py));}
    while(px!==parent.x){px+=Math.sign(parent.x-px);path.push(routeCell(world,px,py));}
    world.rails.push({source:id,parent:parent.id,progress:0,returning:0,cargo:0,path});parent={id,x,y};
  }
  return world;
}
const summary=values=>{const sorted=values.toSorted((a,b)=>a-b);return{median:sorted[Math.floor(sorted.length/2)],p95:sorted[Math.ceil(sorted.length*.95)-1]};};
for(const count of [16,64,256]) {
  const runtime=new ReducerRuntime();await runtime.replace(runtime.prepare(bytes,manifest));
  await runtime.initialize(1);await runtime.initialize(2);
  await fixtureCall(runtime,'new-run-seed',[1]);
  const world=fixture(colony(runtime.snapshot(1)),count);await restoreColony(runtime,world);
  const snapshots=new Map(runtime.stores),words=colonyWords(world),decode=[];
  for(let sample=0;sample<15;sample++) {
    snapshots.set(1,words.slice());const begin=performance.now();runtime.validateState(runtime.instance,snapshots);
    if(sample>=3)decode.push(performance.now()-begin);
  }
  const cold=performance.now();await fixtureCall(runtime,'advance');const coldTick=performance.now()-cold,ticks=[];
  for(let sample=0;sample<12;sample++){const begin=performance.now();await fixtureCall(runtime,'advance');ticks.push(performance.now()-begin);}
  console.log(JSON.stringify({generation:manifest.generation,depots:count,chainDecodeMs:summary(decode),
    coldFullTickMs:coldTick,warmFullTickMs:summary(ticks),rails:colony(runtime.snapshot(1)).rails.length}));
  await runtime.close();
}
