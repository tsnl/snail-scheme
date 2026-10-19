// Instrumented fresh-decode and reducer diagnostic, not an FPS benchmark.
// Every fixture is an explicitly funded legal World; all measured ticks execute.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,colonyWords,at,pixelAt,routeCell,restoreColony,withdrawReserves} from './colony-state.mjs';

function grown(world) {
  withdrawReserves(world,10000);world.delivered+=10000;world.ore+=10000;world.started=true;
  world.hubCapacityLevel=6;world.spent+=6300;world.ore-=6300;
  for(let y=11;y<=30&&world.buildings.length<64;y++)for(let x=1;x<=20&&world.buildings.length<64;x++) {
    if((x>=7&&x<=9&&y>=21&&y<=23)||(x===12&&y===20))continue;
    const point=at(world,x,y),aim=pixelAt(world,x,y);
    world.buildings.push({id:world.nextId++,kind:3,...point,level:1,hp:90,stock:0,stage:2,cooldown:0,
      aimX:aim.x,aimY:aim.y,armed:0,source:0,moveX:-1,moveY:-1});
    world.surveys.push({...point,radius:7});world.spent+=25;world.ore-=25;
  }
  while(world.bots.length<24){world.bots.push({...world.bots[0],id:world.nextId++,path:[]});world.spent+=25;world.ore-=25;}
  return world;
}
function crowd(world) {
  const path=Array.from({length:12},(_,index)=>routeCell(world,19-index,22));
  for(let i=0;i<128;i++)world.enemies.push({id:world.nextId++,...pixelAt(world,20,22),hp:80,
    kind:0,rank:0,burrower:false,target:0,path:[...path]});
  return world;
}
const summary=values=>{const sorted=values.toSorted((a,b)=>a-b);return{median:sorted[Math.floor(sorted.length/2)],p95:sorted[Math.ceil(sorted.length*.95)-1]};};
const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
for(const [name,prepare]of[['initial',world=>({...world,started:true})],['grown',grown],['crowd',world=>crowd(grown(world))]]) {
  const runtime=new ReducerRuntime();await runtime.replace(runtime.prepare(bytes,manifest));await runtime.initialize(1);await runtime.initialize(2);
  const world=prepare(colony(runtime.snapshot(1)));await restoreColony(runtime,world);
  const words=colonyWords(world),snapshots=new Map(runtime.stores),decodes=[],ticks=[];
  for(let sample=0;sample<43;sample++) {
    snapshots.set(1,words.slice());const start=performance.now();runtime.validateState(runtime.instance,snapshots);
    if(sample>=3)decodes.push(performance.now()-start);
  }
  for(let sample=0;sample<43;sample++) {
    const start=performance.now();await runtime.dispatch(1,runtime.command('match','advance'));
    if(sample>=3)ticks.push(performance.now()-start);
  }
  assert.equal(colony(runtime.snapshot(1)).tick,world.tick+43);
  console.log(JSON.stringify({generation:manifest.generation,fixture:name,worldBytes:words.length*4,
    deposits:world.deposits?.length??0,nests:world.nests?.length??1,freshDecodeMs:summary(decodes),fullTickMs:summary(ticks)}));
  await runtime.close();
}
