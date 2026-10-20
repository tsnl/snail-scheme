// Direct placement through real game Wasm, BrowserApplication and LocalState.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {BrowserApplication} from '../../src/browser/application.mjs';
import {LocalState} from '../../src/application/local.mjs';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {establishColony,colony,client,colonyWords,restoreClient,restoreColony,at,routeCell,siteAt,setWorker} from './colony-state.mjs';
const world=h=>colony(h.runtime.snapshot(1)),state=h=>client(h.runtime.snapshot(2));
const deferred=()=>{let resolve;const promise=new Promise(yes=>{resolve=yes;});return{promise,resolve};};
function node(h,key,value=h.runtime.view().ui){if(value.key===key)return value;for(const child of value.children){const found=node(h,key,child);if(found)return found;}}
async function host(fresh,started=true){
  const runtime=await fresh(),errors=[],orders=[],controls={commit:()=>{}};
  if(started)await establishColony(runtime);
  const app=Object.assign(Object.create(BrowserApplication.prototype),{runtime,manifest:runtime.manifest,updates:Promise.resolve(),closing:false,localWork:0,dirty:false,note:()=>{},report:error=>errors.push(error)});
  const local=new LocalState(runtime,{commit:(...args)=>controls.commit(...args),publish:output=>app.queueEffects(output.effects)});
  app.session={submit:command=>{orders.push(command);return local.submit(command);}};
  return{app,runtime,local,controls,errors,orders};
}
async function action(h,name,args=[]){await h.app.local(name,args);await h.app.drainUpdates();}
async function point(h,x,y){const cell=at(world(h),x,y);await restoreClient(h.runtime,{...state(h),cursorX:cell.x,cursorY:cell.y});}
async function select(h,x,y){await point(h,x,y);await action(h,'confirm');}
function delaySave(h){const entered=deferred(),saved=deferred();h.controls.commit=()=>{h.controls.commit=()=>{};entered.resolve();return saved.promise;};return{entered:entered.promise,release:saved.resolve};}
function failSave(h){h.controls.commit=()=>{h.controls.commit=()=>{};throw new Error('controlled construction save failure');};}
const construction=h=>h.orders.filter(command=>command.handler===h.runtime.command('match','build-cell',[1,0]).handler);

export async function checkDirectBuild(test,fresh){
  await test('one site selection exposes its own costs without spending or starting time',async()=>{
    const h=await host(fresh,false),before=h.runtime.snapshot(1);
    await select(h,12,20);assert.ok(node(h,'extractor'));assert.equal(node(h,'tower'),undefined);assert.equal(state(h).choiceKind,0);
    assert.match(node(h,'extractor-caption').text,/Free/);
    await select(h,12,22);assert.equal(node(h,'extractor'),undefined);for(const key of ['tower','artillery'])assert.ok(node(h,key));
    assert.deepEqual([node(h,'tower').text,node(h,'artillery').text],['1','2']);
    assert.equal(state(h).choiceKind,0);assert.match(node(h,'context-description').text,/Choose a building/);assert.ok(node(h,'close-context'));
    for(const key of ['tower','artillery'])assert.equal(node(h,key).properties[2],0,'one-shot construction is not a mode toggle');
    await action(h,'dismiss');assert.equal(state(h).chooser,false);assert.deepEqual(h.runtime.snapshot(1),before);assert.equal(world(h).started,false);
    for(const old of ['build-menu','done-plan','clear-plan'])assert.equal(node(h,old),undefined);await h.app.close();
  });
  await test('repeated tile activation never builds; an explicit choice builds once',async()=>{
    const h=await host(fresh);await select(h,12,22);const cell=routeCell(world(h),12,22);
    for(let i=0;i<3;i++)await action(h,'confirm');assert.equal(siteAt(world(h),12,22),undefined);assert.equal(construction(h).length,0);await action(h,'choose',[1]);assert.equal(siteAt(world(h),12,22).kind,3);assert.equal(world(h).ore,135);assert.equal(state(h).chooser,false);
    for(let i=0;i<3;i++)await action(h,'confirm');await action(h,'construct',[3,cell]);
    assert.equal(world(h).buildings.length,1);assert.equal(world(h).ore,135);assert.equal(construction(h).length,1);assert.ok(node(h,'cancel-build'));assert.ok(node(h,'close-context'));
    const occupied=h.runtime.snapshot(1);await action(h,'dismiss');assert.equal(state(h).chooser,false);assert.deepEqual(h.runtime.snapshot(1),occupied);
    const revealed=world(h);revealed.surveys.unshift({x:59,y:37,radius:7});await restoreColony(h.runtime,revealed);
    await restoreClient(h.runtime,{...state(h),cursorX:59,cursorY:37});await action(h,'confirm');
    assert.ok(node(h,'close-context'));assert.equal(node(h,'tower'),undefined);assert.match(node(h,'context-title').text,/nest/i);
    const nest=h.runtime.snapshot(1);await action(h,'dismiss');assert.equal(state(h).chooser,false);assert.deepEqual(h.runtime.snapshot(1),nest);await h.app.close();
  });
  await test('new sites remain neutral after construction and hover previews never order a building',async()=>{
    const h=await host(fresh);await select(h,12,22);await action(h,'choose',[2]);
    await select(h,13,22);assert.equal(state(h).choiceKind,0);assert.equal(state(h).preview,0);
    const before=h.runtime.snapshot(1);
    for(const kind of [3,2,0]){await action(h,'preview',[kind]);assert.equal(state(h).preview,kind);assert.deepEqual(h.runtime.snapshot(1),before);}
    await action(h,'confirm');assert.deepEqual(h.runtime.snapshot(1),before);assert.equal(state(h).choiceKind,0);
    await select(h,12,20);assert.equal(state(h).choiceKind,0);await action(h,'choose',[1]);assert.equal(siteAt(world(h),12,20).kind,1);
    await select(h,14,22);assert.equal(state(h).choiceKind,0);assert.equal(state(h).preview,0);await h.app.close();
  });
  await test('slow placement locks repeat taps and stale explicit buttons cannot charge a retargeted site',async()=>{
    const h=await host(fresh);await select(h,12,22);const cell=routeCell(world(h),12,22),gate=delaySave(h),placing=h.app.local('construct',[3,cell]);await gate.entered;
    assert.equal(state(h).buildKind,3);assert.equal(world(h).ore,160);
    const repeats=[h.app.local('confirm'),h.app.local('construct',[3,cell]),h.app.local('nudge',[1,0]),h.app.local('confirm')];
    gate.release();await Promise.all([placing,...repeats]);await h.app.drainUpdates();assert.equal(world(h).ore,135);assert.equal(construction(h).length,1);
    await select(h,13,22);const before=h.runtime.snapshot(1);await action(h,'construct',[3,cell]);assert.deepEqual(h.runtime.snapshot(1),before);assert.equal(state(h).chooser,true);await h.app.close();
  });
  await test('failed and rejected construction retain useful feedback but require an explicit retry',async()=>{
    const h=await host(fresh);await select(h,12,22);const cell=routeCell(world(h),12,22),before=h.runtime.snapshot(1);
    failSave(h);await action(h,'construct',[2,cell]);assert.deepEqual(h.runtime.snapshot(1),before);assert.equal(state(h).buildKind,0);assert.equal(state(h).choiceKind,2);assert.equal(state(h).lastKind,3);assert.equal(state(h).chooser,true);assert.equal(state(h).failure,34);assert.match(node(h,'context-description').text,/not saved/);
    await action(h,'confirm');assert.equal(siteAt(world(h),12,22),undefined);await action(h,'choose',[2]);assert.equal(siteAt(world(h),12,22).kind,2);assert.equal(state(h).lastKind,3);assert.equal(world(h).ore,110);
    const poor=world(h);poor.spent+=poor.ore;poor.ore=0;await restoreColony(h.runtime,poor);await select(h,13,22);await action(h,'choose',[1]);
    assert.equal(state(h).choiceKind,3);assert.equal(state(h).lastKind,3);assert.equal(state(h).buildKind,0);assert.equal(state(h).chooser,true);assert.equal(world(h).notice,7);assert.equal(world(h).ore,0);await h.app.close();
  });
  await test('Pause can cover a placement while its committed result settles without closing the menu',async()=>{
    const h=await host(fresh);await select(h,12,22);const gate=delaySave(h),placing=h.app.local('choose',[1]);await gate.entered;
    const pause=h.app.local('pause-menu');gate.release();await Promise.all([placing,pause]);await h.app.drainUpdates();
    assert.equal(world(h).ore,135);assert.equal(world(h).paused,1);assert.equal(state(h).dialog,1);assert.equal(state(h).buildKind,0);assert.equal(state(h).lastKind,3);assert.equal(state(h).chooser,false);
    await action(h,'resume');assert.equal(world(h).paused,0);await h.app.close();
  });
  await test('an authoritative import supersedes an older placement reply and preserves imported pause',async()=>{
    const h=await host(fresh);await select(h,12,22);const imported={...world(h),paused:1},gate=delaySave(h),placing=h.app.local('choose',[1]);await gate.entered;
    const replace=h.app.update(async()=>{await h.local.restore(colonyWords(imported));await h.app.localTransition(h.runtime.command('client','reset-presentation'));
      assert.equal(state(h).buildKind,3);assert.equal(state(h).buildResult,3);assert.equal(state(h).chooser,false);});
    gate.release();await Promise.all([placing,replace]);await h.app.drainUpdates();assert.deepEqual(world(h),imported);assert.equal(state(h).lastKind,3);assert.equal(state(h).buildKind,0);assert.equal(state(h).dialog,1);
    await action(h,'resume');assert.equal(world(h).paused,0);await h.app.close();
  });
  await test('a late explicit choice after a failed save retries the unpaid site once',async()=>{
    const h=await host(fresh);await select(h,12,22);const entered=deferred(),release=deferred();let writes=0,clock;
    h.controls.commit=()=>{if(++writes===1){clock=h.local.submit(h.runtime.command('match','advance'));throw new Error('controlled first write failure');}
      if(writes===2){entered.resolve();return release.promise;}};
    const placing=h.app.local('choose',[1]);await entered.promise;await placing;
    const retry=h.app.local('choose',[1]);release.resolve();await Promise.all([clock,retry]);await h.app.drainUpdates();
    assert.equal(h.errors.length,1);assert.equal(construction(h).length,2);assert.equal(world(h).buildings.length,1);assert.equal(world(h).ore,135);assert.equal(state(h).lastKind,3);await h.app.close();
  });
  await test('the selected popup retains the actual surveyed-route rejection after unrelated world notices',async()=>{
    const h=await host(fresh),isolated=world(h);isolated.surveys.unshift({...at(isolated,12,8),radius:4});setWorker(isolated,0,{x:12,y:12});await restoreColony(h.runtime,isolated);
    await select(h,12,11);await action(h,'choose',[1]);assert.equal(state(h).failure,32);assert.equal(world(h).ore,160);assert.match(node(h,'context-description').text,/No worker route through surveyed ground/);
    await h.local.submit(h.runtime.command('match','repair-hub'));await h.app.drainUpdates();assert.equal(world(h).notice,29);assert.equal(state(h).failure,32);assert.match(node(h,'context-description').text,/Extend tower coverage/);
    await h.app.close();
  });
  await test('the hub owns repeated hiring and no separate worker control remains',async()=>{
    const h=await host(fresh);assert.equal(node(h,'worker-menu'),undefined);assert.equal(node(h,'worker-panel'),undefined);
    const initial=h.runtime.snapshot(1);await action(h,'fabricate');assert.deepEqual(h.runtime.snapshot(1),initial);
    await action(h,'home');await action(h,'fabricate');await action(h,'fabricate');assert.equal(world(h).ore,110);assert.equal(state(h).chooser,true);assert.ok(node(h,'worker'));assert.ok(node(h,'home'));
    assert.equal(node(h,'worker-menu'),undefined);await h.app.close();
  });
  await test('attack notifications expose location and dismissal without rendering thumbnail scenes',async()=>{
    const h=await host(fresh),alerted=world(h),hub=alerted.surveys[0];alerted.alerts=[{x:hub.x,y:hub.y,kind:0,tick:0}];await restoreColony(h.runtime,alerted);
    const key=(hub.x+hub.y*128)*8;assert.ok(node(h,`attack-inspect-${key}`));assert.ok(node(h,`attack-dismiss-${key}`));assert.equal(h.runtime.view().scene.insets,undefined);
    await action(h,'dismiss-attack',[key]);assert.equal(node(h,`attack-inspect-${key}`),undefined);await h.app.close();
  });
  await test('upgrade waiting markers follow authoritative pending upgrades and disappear on cancellation',async()=>{
    const h=await host(fresh);await select(h,12,22);await action(h,'choose',[1]);
    for(let i=0;i<150&&world(h).buildings[0].stage!==2;i++)await h.local.submit(h.runtime.command('match','advance'));
    await h.app.drainUpdates();await select(h,12,22);await action(h,'improve');const id=world(h).buildings[0].id;
    assert.ok(node(h,`upgrade-wait-${id}`));await action(h,'cancel');assert.equal(node(h,`upgrade-wait-${id}`),undefined);await h.app.close();
  });
}
if(process.argv[1]===import.meta.filename){
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json'))),bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return r;};
  let count=0;await checkDirectBuild(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);console.log(`${count} direct construction checks passed`);
}
