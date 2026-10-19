// Real game Wasm, browser admission and LocalState persistence. Storage delays
// expose menu ordering; no alternate reducer or receipt implementation lives here.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {BrowserApplication} from '../../src/browser/application.mjs';
import {LocalState} from '../../src/application/local.mjs';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,client,colonyWords,restoreColony,pixelAt,fixtureCall} from './colony-state.mjs';
const world=h=>colony(h.runtime.snapshot(1)),state=h=>client(h.runtime.snapshot(2));
const deferred=()=>{let resolve;const promise=new Promise(yes=>{resolve=yes;});return{promise,resolve};};
function node(h,key,value=h.runtime.view().ui){if(value.key===key)return value;for(const child of value.children){const found=node(h,key,child);if(found)return found;}}
async function host(fresh){
  const runtime=await fresh(),errors=[],orders=[],controls={commit:()=>{}};
  const app=Object.assign(Object.create(BrowserApplication.prototype),{runtime,manifest:runtime.manifest,updates:Promise.resolve(),closing:false,localWork:0,dirty:false,note:()=>{},report:error=>errors.push(error)});
  const local=new LocalState(runtime,{commit:(...args)=>controls.commit(...args),publish:output=>app.queueEffects(output.effects)});
  app.session={submit:async command=>{
    orders.push(runtime.manifest.applications.find(a=>a.owner==='match').handlers.find(h=>h.id===command.handler).binding);
    const result=await local.submit(command);
    if(['new-run','new-run-seed'].includes(orders.at(-1)))void app.local(runtime.manifest.settings.resetPresentation);
    return result;
  }};
  return{app,runtime,local,controls,errors,orders};
}
async function action(h,name,args=[]){await h.app.local(name,args);await h.app.drainUpdates();}
async function select(h){await action(h,'nudge',[1,1]);await action(h,'confirm');assert.equal(state(h).chooser,true);}
const selection=h=>[state(h).chooser,state(h).targetX,state(h).targetY,state(h).choiceKind];
function delaySave(h){const entered=deferred(),saved=deferred();h.controls.commit=()=>{h.controls.commit=()=>{};entered.resolve();return saved.promise;};return{entered:entered.promise,release:saved.resolve};}
function failSave(h){h.controls.commit=()=>{h.controls.commit=()=>{};throw new Error('controlled storage failure');};}
async function importWorld(h,value){await h.local.restore(colonyWords(value));await h.app.localTransition(h.runtime.command('client',h.runtime.manifest.settings.resetPresentation));}

export async function checkColonyMenus(test,fresh){
  await test('camera guards read Client only on an established 128-enemy colony',async()=>{
    const h=await host(fresh);await fixtureCall(h.runtime,'extract',[12,20]);
    for(let i=0;i<140;i++)await fixtureCall(h.runtime,'advance');
    const value=world(h);value.enemies=Array.from({length:128},()=>({id:value.nextId++,...pixelAt(value,8,22),hp:80,kind:0,target:0,path:[],rank:0}));
    await restoreColony(h.runtime,value);const before=h.runtime.snapshot(1),read=h.runtime.read.bind(h.runtime);let reads=0;
    h.runtime.read=(owner,index)=>{if(owner===1&&h.runtime.active.owner===2&&!h.runtime.active.readOnly)reads++;return read(owner,index);};
    for(const [name,args]of[['drift',[1,0]],['drag',[8,-4]],['pan',[1,0]],['zoom',[1]],['turn',[1]],['rotate',[0,-1]],['animate',[16]],['viewport',[390,844]]])await action(h,name,args);
    assert.equal(reads,0,'camera input does not decode World');assert.deepEqual(h.runtime.snapshot(1),before);await h.app.close();
  });
  await test('pending Pause rejects rapid Resume and Restart until its ordered settlement',async()=>{
    const h=await host(fresh);await select(h);const unpaid=selection(h),gate=delaySave(h),pause=h.app.local('pause-menu');await gate.entered;
    assert.equal(world(h).paused,0);assert.equal(state(h).dialogPending,1);assert.equal(node(h,'pause-title').text,'Pausing…');
    const resume=h.app.local('resume'),restart=h.app.local('restart');gate.release();await Promise.all([pause,resume,restart]);await h.app.drainUpdates();
    assert.deepEqual(h.orders,['pause-colony']);assert.equal(world(h).paused,1);assert.equal(state(h).dialog,1);assert.equal(state(h).dialogPending,0);assert.deepEqual(selection(h),unpaid);
    await action(h,'restart');await action(h,'pause-state',[0]);assert.equal(state(h).dialog,2,'an unrelated unpause reply cannot close confirmation');await h.app.close();
  });
  await test('failed Pause, Resume and Restart remain retryable without spending the unpaid selection',async()=>{
    const h=await host(fresh);await select(h);const unpaid=selection(h),before=h.runtime.snapshot(1);
    failSave(h);await action(h,'pause-menu');assert.equal(state(h).dialog,0);assert.deepEqual(h.runtime.snapshot(1),before);assert.deepEqual(selection(h),unpaid);
    await action(h,'pause-menu');const paused=h.runtime.snapshot(1);failSave(h);await action(h,'resume');
    assert.equal(state(h).dialog,1);assert.equal(state(h).dialogPending,0);assert.deepEqual(h.runtime.snapshot(1),paused);assert.deepEqual(selection(h),unpaid);
    await action(h,'resume');assert.equal(world(h).paused,0);await action(h,'pause-menu');await action(h,'restart');
    failSave(h);await action(h,'accept-restart');assert.equal(state(h).dialog,2);assert.equal(state(h).dialogPending,0);assert.deepEqual(h.runtime.snapshot(1),paused);assert.deepEqual(selection(h),unpaid);
    assert.equal(h.errors.length,3);await action(h,'accept-restart');assert.equal(world(h).runMarker,colony(before).runMarker+1);assert.equal(state(h).dialog,0);assert.equal(state(h).chooser,false);await h.app.close();
  });
  await test('Resume remains covered through commit and settlement while newer menu input is queued',async()=>{
    const h=await host(fresh);await select(h);await action(h,'pause-menu');const unpaid=selection(h),gate=delaySave(h),resume=h.app.local('resume');await gate.entered;
    assert.equal(world(h).paused,1);assert.equal(state(h).dialogPending,2);assert.equal(node(h,'resume').text,'Resuming…');assert.equal(node(h,'restart-menu').properties[1],0);
    const restart=h.app.local('restart'),again=h.app.local('resume'),clear=h.app.local('center');gate.release();await Promise.all([resume,restart,again,clear]);await h.app.drainUpdates();
    assert.deepEqual(h.orders,['pause-colony','pause-colony']);assert.equal(world(h).paused,0);assert.equal(state(h).dialog,0);assert.equal(state(h).dialogPending,0);assert.deepEqual(selection(h),unpaid);await h.app.close();
  });
  await test('repeated confirmation during a slow reset issues exactly one durable new run',async()=>{
    const h=await host(fresh);await select(h);await action(h,'pause-menu');await action(h,'restart');const marker=world(h).runMarker,unpaid=selection(h),gate=delaySave(h);
    const reset=h.app.local('accept-restart');await gate.entered;assert.equal(state(h).dialogPending,3);assert.equal(node(h,'accept-restart').text,'Restarting…');assert.equal(node(h,'dismiss-restart').properties[1],0);
    assert.equal(world(h).runMarker,marker);assert.deepEqual(selection(h),unpaid);
    const repeats=[h.app.local('accept-restart'),h.app.local('accept'),h.app.local('dismiss'),h.app.local('restart-seed',[42])];gate.release();await Promise.all([reset,...repeats]);await h.app.drainUpdates();
    assert.equal(h.orders.filter(name=>name==='new-run').length,1);assert.equal(world(h).runMarker,marker+1);assert.equal(state(h).dialogPending,0);assert.equal(state(h).dialog,0);assert.equal(state(h).chooser,false);await h.app.close();
  });
  await test('a committed import supersedes older Resume replies without releasing its occupied slot',async()=>{
    const h=await host(fresh);await select(h);await action(h,'pause-menu');const imported=world(h),gate=delaySave(h),resume=h.app.local('resume');await gate.entered;
    const importedTurn=h.app.update(async()=>{await importWorld(h,imported);assert.equal(state(h).dialogPending,2);assert.equal(state(h).dialogResult,2);assert.equal(state(h).dialog,1);});
    gate.release();await Promise.all([resume,importedTurn]);await h.app.drainUpdates();assert.equal(world(h).paused,1);assert.equal(state(h).dialog,1);assert.equal(state(h).dialogPending,0);
    await action(h,'resume');assert.equal(world(h).paused,0);assert.equal(state(h).dialog,0);await h.app.close();
  });
  await test('an imported paused colony synchronizes its menu while earlier build replies still drain',async()=>{
    const h=await host(fresh);await select(h);const imported={...world(h),paused:1},gate=delaySave(h),done=h.app.local('choose',[1]);await gate.entered;
    const importedTurn=h.app.update(async()=>{await importWorld(h,imported);assert.equal(state(h).buildKind,3);assert.equal(state(h).buildResult,3);assert.equal(state(h).dialog,1);});
    gate.release();await Promise.all([done,importedTurn]);await h.app.drainUpdates();assert.equal(state(h).buildKind,0);assert.equal(world(h).paused,1);assert.equal(state(h).dialog,1);assert.equal(node(h,'resume').properties[1],1);
    await action(h,'resume');assert.equal(world(h).paused,0);assert.equal(state(h).dialog,0);await h.app.close();
  });
}
if(process.argv[1]===import.meta.filename){
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};
  let count=0;await checkColonyMenus(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);console.log(`${count} asynchronous menu checks passed`);
}
