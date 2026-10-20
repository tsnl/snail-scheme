// Actual reducers enforce the first construction order across UI, shortcuts and raw commands.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,client,fixtureCall,at,routeCell,restoreClient} from './colony-state.mjs';
const world=r=>colony(r.snapshot(1)),local=r=>client(r.snapshot(2));
function node(r,key,value=r.view().ui){if(value.key===key)return value;for(const child of value.children){const found=node(r,key,child);if(found)return found;}}
async function apply(r,result){for(const effect of result.effects)if(effect.kind==='send')await apply(r,await r.dispatch(effect.owner,r.effectCommand(effect)));}
async function command(r,name,args=[]){await apply(r,await r.dispatch(2,r.command('client',name,args)));}
async function select(r,x,y){const point=at(world(r),x,y);await restoreClient(r,{...local(r),cursorX:point.x,cursorY:point.y});await command(r,'confirm');}
async function ticks(r,count){for(let i=0;i<count;i++)await fixtureCall(r,'advance');}

export async function checkOpening(test,fresh,bytes){
  await test('before the first extractor every other direct purchase preserves the starting economy',async()=>{
    const r=await fresh(),initial=world(r),ordinary=routeCell(initial,12,22);
    const commands=[['fabricate-worker'],['repair-hub'],['upgrade',[8,22]],['upgrade',[12,22]],
      ['observe',[12,22]],['fortify',[12,22]],['build-cell',[2,ordinary]],['build-cell',[3,ordinary]]];
    for(const [name,args]of commands){await fixtureCall(r,name,args);assert.deepEqual(world(r),{...initial,notice:38},name);}
    for(const [name,args]of[['relocate-building',[routeCell(initial,12,22),routeCell(initial,13,22)]],['arm-tower',[12,22]],['cancel-building',[12,22]]]){
      await fixtureCall(r,name,args);const actual=world(r);assert.deepEqual({...actual,notice:0},initial,name);
    }
    await ticks(r,20);assert.equal(world(r).tick,0);assert.equal(world(r).ore,160);assert.equal(world(r).started,false);
    const saved=r.snapshot(1);await r.restore(1,saved);await r.replace(r.prepare(bytes,r.manifest));assert.deepEqual(r.snapshot(1),saved);await r.close();
  });
  await test('opening hub and construction actions explain the gate; keyboard dispatch cannot bypass it',async()=>{
    const r=await fresh();await command(r,'home');
    for(const key of ['worker','upgrade','repair'])assert.equal(node(r,key).properties[1],0,key);
    assert.match(node(r,'context-description').text,/extractor.*first/s);
    for(const key of ['fabricate','improve','repair']){await command(r,key);assert.equal(world(r).ore,160);assert.equal(world(r).started,false);}
    await command(r,'dismiss');await select(r,12,22);
    for(const key of ['tower','artillery']){assert.equal(node(r,key).properties[1],0);assert.match(node(r,key).help,/extractor.*first/);}
    for(const choice of [1,2]){
      await command(r,'choose',[choice]);assert.equal(local(r).failure,38);assert.equal(world(r).notice,38);
      assert.equal(world(r).buildings.length,0);assert.equal(world(r).spent,0);assert.equal(local(r).chooser,true);
    }
    const saved=r.snapshot(2);await r.restore(2,saved);assert.deepEqual(r.snapshot(2),saved);await r.close();
  });
  await test('only an accepted 25-ore extractor starts time, and later cancellation refunds its reservation',async()=>{
    const r=await fresh();await fixtureCall(r,'extract',[12,22]);assert.equal(world(r).notice,4);assert.equal(world(r).started,false);
    await select(r,12,20);const selected=r.snapshot(1);await ticks(r,10);assert.deepEqual(r.snapshot(1),selected);
    assert.equal(node(r,'extractor').properties[1],1);await command(r,'choose',[1]);
    assert.equal(world(r).started,true);assert.equal(world(r).ore,135);assert.equal(world(r).spent,25);assert.equal(world(r).tick,0);
    assert.equal(world(r).buildings.length,1);await fixtureCall(r,'cancel-building',[12,20]);
    assert.equal(world(r).started,true);assert.equal(world(r).ore,160);assert.equal(world(r).buildings.length,0);
    await ticks(r,1);assert.equal(world(r).tick,1);await command(r,'home');assert.equal(node(r,'worker').properties[1],1);
    await command(r,'fabricate');assert.equal(world(r).ore,135);assert.equal(world(r).bots.length,3);
    assert.equal(world(r).bots.filter(bot=>[4,6].includes(bot.job)).length,1);
    const saved=r.snapshot(1);await r.restore(1,saved);await r.replace(r.prepare(bytes,r.manifest));assert.deepEqual(r.snapshot(1),saved);await r.close();
  });
  await test('the visible timer advances only with active colony ticks',async()=>{
    const r=await fresh();assert.equal(node(r,'elapsed-time').text,'Time 0:00');
    await ticks(r,20);assert.equal(node(r,'elapsed-time').text,'Time 0:00');
    await select(r,12,20);await command(r,'choose',[1]);await ticks(r,10);
    assert.equal(node(r,'elapsed-time').text,'Time 0:01');await command(r,'pause-menu');
    await ticks(r,20);assert.equal(node(r,'elapsed-time').text,'Time 0:01');await command(r,'resume');
    await ticks(r,10);assert.equal(node(r,'elapsed-time').text,'Time 0:02');await r.close();
  });
  await test('camera, pause and seed controls stay usable before a valid extractor starts each seeded run',async()=>{
    const r=await fresh(),initial=r.snapshot(1);
    for(const [name,args]of[['pan',[1,1]],['zoom',[150]],['turn',[1]],['animate',[150]],['home',[]]])await command(r,name,args);
    assert.deepEqual(r.snapshot(1),initial);await command(r,'pause-menu');assert.equal(world(r).paused,1);assert.equal(world(r).started,false);
    await command(r,'resume');assert.equal(world(r).paused,0);assert.equal(world(r).started,false);
    for(const seed of [1,42,65535]){
      await fixtureCall(r,'new-run-seed',[seed]);await ticks(r,5);assert.equal(world(r).tick,0);assert.equal(world(r).ore,160);
      await fixtureCall(r,'extract',[12,20]);assert.equal(world(r).started,true);assert.equal(world(r).ore,135);
      await ticks(r,1);assert.equal(world(r).tick,1);
    }
    await r.close();
  });
}
if(process.argv[1]===import.meta.filename){
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};
  let count=0;await checkOpening(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh,bytes);console.log(`${count} extractor-first checks passed`);
}
