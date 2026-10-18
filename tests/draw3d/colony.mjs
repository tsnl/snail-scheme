// Real Scheme selection, actions, picking and presentation ownership.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony, client, at, siteAt, restoreClient} from '../applications/colony-state.mjs';
const output = process.argv[2], manifest = JSON.parse(readFileSync(join(output, 'manifest.json')));
const bytes = readFileSync(join(output, manifest.module)), runtime = new ReducerRuntime();
await runtime.replace(runtime.prepare(bytes, manifest)); await runtime.initialize(1); await runtime.initialize(2);
runtime.uiBridge.resize(936,608);
const world = () => colony(runtime.snapshot(1));
const local = () => client(runtime.snapshot(2));
async function command(binding, args = []) {
  if(binding==='viewport')runtime.uiBridge.resize(args[0]-24,args[1]-32);
  const result = await runtime.dispatch(2, runtime.command('client', binding, args));
  await effects(result.effects);
}
async function advance(ticks) {
  for (let i = 0; i < ticks; i++) await runtime.dispatch(1, runtime.command('match', 'advance'));
}
async function animate() {
  for (let i = 0; i < 80 && (local().homing || local().turnElapsed < 300); i++) await command('animate',[50]);
  assert.equal(local().homing,false); assert.equal(local().turnElapsed,300);
}
async function home() { await command('home'); await animate(); await command('dismiss'); }
function project(x, y, z = 0) {
  ({x,y}=at(world(),x,y));
  const scene = runtime.view().scene, m = scene.uniforms, state = local(), v = scene.viewport ?? [0,0,state.width,state.height];
  return [Math.round(v[0]+(m[0]*x-m[4]*y+m[8]*z+m[12]+1)*v[2]/2),
    Math.round(v[1]+(1-(m[1]*x-m[5]*y+m[9]*z+m[13]))*v[3]/2)];
}
const point = (x,y,z) => command('move',project(x,y,z));
function cursorAt(x,y) { const target=at(world(),x,y); assert.equal(local().cursorX,target.x); assert.equal(local().cursorY,target.y); }
function node(key, value=runtime.view().ui) {
  if (value.key===key) return value;
  for (const child of value.children) { const found=node(key,child); if(found)return found; }
}
function placed(key,value=runtime.view().ui,x=0,y=0) {
  const left=x+value.rect[0],top=y+value.rect[1];
  if(value.key===key)return{node:value,left,top,right:left+value.rect[2],bottom:top+value.rect[3]};
  for(const child of value.children){const found=placed(key,child,left,top);if(found)return found;}
}
function popupControlsFit() {
  const card=node('context');assert.ok(card);const width=card.rect[2],height=card.rect[3];
  function walk(value,left,top) {
    left+=value.rect[0];top+=value.rect[1];
    if(value.kind===5)assert.equal(value.properties[8],0,`${value.key} must not scroll`);
    if(value.kind===2){
      assert.ok(left>=0&&top>=0&&left+value.rect[2]<=width&&top+value.rect[3]<=height,`${value.key} must fit its card`);
      assert.match(value.text,/^(?:[123UCTNFHPR]|Esc|Enter)$/,`${value.key} shows its hotkey`);
    }
    const padding=value.kind===5?value.properties[6]:0;
    for(const child of value.children)walk(child,left+padding,top+padding);
  }
  for(const child of card.children)walk(child,card.properties[6],card.properties[6]);
}
async function effects(values) {
  for(const effect of values)if(effect.kind==='send') {
    const result=await runtime.dispatch(effect.owner,runtime.effectCommand(effect));await effects(result.effects);
    if(effect.owner===1&&['new-run','new-run-seed'].some(name=>effect.command.handler===runtime.command('match',name,name==='new-run-seed'?[1]:[]).handler))
      await command('reset-presentation');
  }
}
async function plan(kind,cells) {
  await command('choose',[kind]);for(const [x,y] of cells){await point(x,y);await command('confirm');}
}
function controlsFit(width,height) {
  function walk(value,x=0,y=0) {
    x+=value.rect[0];y+=value.rect[1];
    if((value.kind===2&&value.key!=='dialog-backdrop'&&!value.key.startsWith('attack-inspect-'))||value.kind===6) {
      const menu=['resume','restart-menu','handedness','dismiss-restart','accept-restart'].includes(value.key);
      assert.deepEqual(value.rect.slice(2),menu?[208,48]:[56,56],value.key);
      assert.ok(x>=0&&y>=0&&x+value.rect[2]<=width-24&&y+value.rect[3]<=height-32,`${value.key} fits ${width}×${height}: ${x},${y}`);
    }
    const padding=value.kind===5?value.properties[6]:0;
    for(const child of value.children)walk(child,x+padding,y+padding);
  }
  walk(runtime.view().ui);
}
try {
  const fresh=runtime.snapshot(1),frame=runtime.view();
  assert.ok(frame.scene.batches.reduce((n,b)=>n+b.vertices.length,0)>1000);
  assert.deepEqual(runtime.snapshot(1),fresh);assert.equal(node('context'),undefined);
  assert.equal(manifest.settings.controller,undefined);assert.equal(manifest.settings.controllerAxes,undefined);
  for(const direction of [[1,0],[-1,0],[0,1],[0,-1],[1,-1]]){
    await home();const retained=runtime.view().scene,before=project(8,22);await command('pan',direction);
    for(const key of [0,3,10])assert.equal(runtime.view().scene.batches.find(b=>b.key===key),retained.batches.find(b=>b.key===key));
    const after=project(8,22),dx=after[0]-before[0],dy=after[1]-before[1];
    assert.ok(dx*direction[0]+dy*direction[1]<-20);assert.ok(Math.abs(dx*direction[1]-dy*direction[0])<=1);
    await command('pan',direction.map(v=>v*10000));const bounded=local();await command('pan',direction);
    await command('drag',direction.map(v=>-100*v));
    assert.equal(local().cameraX,bounded.cameraX);assert.equal(local().cameraY,bounded.cameraY);
  }
  const distant=local();await command('home');const travelling=local();
  assert.equal(travelling.cameraX,distant.cameraX);assert.equal(travelling.cameraY,distant.cameraY);assert.equal(travelling.homing,true);
  await command('animate',[16]);assert.notDeepEqual([local().cameraX,local().cameraY],[distant.cameraX,distant.cameraY]);
  await animate();const hub=at(world(),8,22);
  assert.deepEqual([local().cameraX,local().cameraY],[hub.x*1000,hub.y*1000]);assert.match(node('context-title').text,/hub/i);
  await command('dismiss');assert.deepEqual(runtime.snapshot(1),fresh);
  const center=[local().cameraX,local().cameraY];await command('zoom',[250]);assert.ok(local().scale>1000);
  await command('zoom',[-250]);assert.equal(local().scale,1000);
  assert.equal(manifest.settings.keys.v,undefined);assert.equal(manifest.settings.keys.o,undefined);
  assert.equal(manifest.applications.find(app=>app.owner==='client').handlers.some(h=>h.binding==='orbit'),false);
  assert.deepEqual([local().cameraX,local().cameraY],center);
  assert.ok([3,7,11].every(index=>runtime.view().scene.uniforms[index]===0));assert.equal(runtime.view().scene.uniforms[15],1);
  console.log('ok - smooth home, screen-aligned bounded pan, retained entities and orthographic zoom preserve match state and look-at');

  await command('center');await point(12,20);await command('confirm');
  assert.equal(local().chooser,false);assert.deepEqual(runtime.snapshot(1),fresh);
  assert.match(node('onboarding-help').text,/Build.*extractor brush.*deposit.*Done/);
  await command('build-menu');assert.ok(node('extractor'));await command('choose',[1]);
  await point(12,20);await command('confirm');assert.equal(local().plan.length,1);assert.deepEqual(runtime.snapshot(1),fresh);
  await command('confirm');assert.equal(local().plan.length,0);await command('confirm');
  await command('choose',[2]);assert.equal(local().brush,1,'a nonempty plan locks the selected type');
  const unpaid=runtime.snapshot(2);await command('pause-menu');
  for(const confirming of [false,true]) {
    if(confirming)await command('restart');
    const covered=runtime.snapshot(2),stopped=runtime.snapshot(1);
    for(const [binding,args]of[['center',[]],['clear-plan',[]],['restart-seed',[42]],['choose',[3]],['done-plan',[]],['home',[]],['preview',[4]]]) {
      await command(binding,args);assert.deepEqual(runtime.snapshot(2),covered,`${binding} preserves the unpaid plan behind the dialog`);
      assert.deepEqual(runtime.snapshot(1),stopped);
    }
    if(confirming){await command('resume');assert.deepEqual(runtime.snapshot(2),covered);await command('dismiss');assert.equal(world().paused,1);}
  }
  await command('resume');assert.deepEqual(runtime.snapshot(2),unpaid);assert.deepEqual(runtime.snapshot(1),fresh);
  await command('clear-plan');assert.equal(local().plan.length,0);assert.deepEqual(runtime.snapshot(1),fresh);
  await plan(1,[[12,20]]);await command('accept');assert.equal(siteAt(world(),12,20).kind,1);assert.equal(world().ore,120);
  assert.equal(local().pending.length,0);assert.equal(local().plan.length,0);await command('clear-plan');
  await advance(140);assert.equal(siteAt(world(),12,20).stage,2);await point(12,20,.94);await command('confirm');
  assert.ok(node('upgrade'));await command('improve');assert.equal(siteAt(world(),12,20).level,2);
  console.log('ok - empty selection is free; brush tiles toggle, type locks, Cancel is unpaid, and Done alone orders construction');

  await command('dismiss');await plan(4,[[13,21],[14,21]]);
  const beforePlan=runtime.snapshot(1),submitted=await runtime.dispatch(2,runtime.command('client','done-plan'));
  assert.equal(submitted.effects.length,4);assert.equal(local().pending.length,2);assert.deepEqual(runtime.snapshot(1),beforePlan);
  const pending=runtime.snapshot(2);
  for(const [binding,args]of[['clear-plan',[]],['choose',[3]],['restart',[]],['center',[]]]) {
    await command(binding,args);assert.deepEqual(runtime.snapshot(2),pending,`${binding} cannot replace an in-flight plan`);
  }
  await command('pause-menu');assert.equal(world().paused,1);assert.equal(node('restart-menu').properties[1],0);
  const coveredPlan=runtime.snapshot(2),pausedPlan=runtime.snapshot(1);
  for(const [binding,args]of[['clear-plan',[]],['center',[]],['restart-seed',[2]],['choose',[3]],['hire',[]],['pan',[1,1]],['zoom',[200]],['turn',[1]],['done-plan',[]],['build-menu',[]],['worker-menu',[]],['confirm',[]],['activate',[]]]) {
    await command(binding,args);assert.deepEqual(runtime.snapshot(2),coveredPlan,`${binding} stays behind the pause menu`);assert.deepEqual(runtime.snapshot(1),pausedPlan);
  }
  await advance(10);assert.deepEqual(runtime.snapshot(1),pausedPlan,'the authoritative clock stops while the menu is open');
  const first=await runtime.dispatch(1,runtime.effectCommand(submitted.effects[0]));await effects(first.effects);
  assert.equal(local().pending.length,2,'a reply alone does not unlock the batch');
  assert.equal(local().resolution,1);await effects([submitted.effects[1]]);assert.equal(local().pending.length,1);
  await effects(submitted.effects.slice(2));assert.equal(local().pending.length,0);assert.equal(local().plan.length,0);
  assert.ok(siteAt(world(),13,21)&&siteAt(world(),14,21));assert.equal(node('restart-menu').properties[1],1);
  await command('resume');await command('clear-plan');
  const bank=world().ore;await plan(4,[[8,22],[15,21]]);await command('done-plan');
  assert.equal(local().pending.length,0);assert.equal(local().plan.length,1);assert.equal(local().rejected,1);
  assert.equal(world().ore,bank-8);assert.ok(siteAt(world(),15,21));await command('clear-plan');assert.equal(world().ore,bank-8);
  console.log('ok - typed per-cell commits settle in order; accepted cells clear and rejected cells remain without extra charges');

  await runtime.restore(1,fresh);await command('center');await plan(4,[[13,21],[14,21],[15,21]]);
  const outgoing=await runtime.dispatch(2,runtime.command('client','done-plan'));
  await effects(outgoing.effects.slice(0,2));
  // A failed save publishes no reply. Its already-authored settlement still runs.
  await effects([outgoing.effects[3]]);await effects(outgoing.effects.slice(4));
  assert.equal(local().pending.length,0);assert.equal(local().unconfirmed,1);assert.equal(local().plan.length,1);
  assert.equal(siteAt(world(),14,21),undefined);assert.equal(world().ore,144);assert.match(node('plan-price').text,/Unconfirmed/);
  const retryable=runtime.snapshot(2);await point(14,21);await command('confirm');
  assert.equal(local().plan.length,0);assert.equal(local().unconfirmed,0);assert.equal(local().rejected,0);
  assert.doesNotMatch(node('plan-price').text,/Unconfirmed|retry/);
  await runtime.restore(2,retryable);await command('done-plan');assert.equal(local().plan.length,0);assert.equal(local().unconfirmed,0);assert.equal(world().ore,136);
  await command('clear-plan');console.log('ok - settlement without a durable reply retains a retryable cell and unlocks only after the batch drains');

  await runtime.restore(1,fresh);await command('center');await home();const unselected=runtime.snapshot(1);
  await command('fabricate');assert.deepEqual(runtime.snapshot(1),unselected);
  await command('worker-menu');assert.deepEqual(runtime.snapshot(1),unselected);assert.ok(node('worker'));
  assert.deepEqual(node('worker').action.command,runtime.command('client','hire'));
  assert.deepEqual(manifest.settings.keys.f,['hire']);assert.deepEqual(manifest.settings.keys.g,['worker-menu']);
  await command('hire');await command('hire');await command('dismiss');
  assert.equal(world().ore,110);assert.equal(local().chooser,false);await command('home');await animate();
  assert.ok(node('repair')&&node('worker'));assert.equal(node('close-context'),undefined);await command('fabricate');assert.equal(world().ore,85);await command('dismiss');
  console.log('ok - worker actions open without charge; repeated F hiring and hub repair use explicit typed requests');

  await home();
  for(let turn=0;turn<4;turn++){
    await command('rotate',[0,1]);assert.equal(runtime.view().scene.requestFrame,true);await command('animate',[50]);assert.ok(local().heading%90000!==0);
    await animate();await point(12,20);cursorAt(12,20);
    const start=project(12,20);await command('drag',[32,-24]);const dragged=project(12,20);
    assert.ok(Math.abs(dragged[0]-start[0]-32)<=1&&Math.abs(dragged[1]-start[1]+24)<=1);await command('drag',[-32,24]);
  }
  for(const[width,height]of[[1100,760],[390,844],[640,360],[568,320],[320,568],[360,640]]){
    await command('viewport',[width,height]);await home();controlsFit(width,height);
    const right=placed('rail').left;await command('pause-menu');controlsFit(width,height);assert.ok(node('resume')&&node('restart-menu')&&node('handedness'));
    assert.deepEqual(node('rotate-left').action.command,runtime.command('client','turn',[-1]));
    assert.deepEqual(node('rotate-right').action.command,runtime.command('client','turn',[1]));
    await command('handedness');controlsFit(width,height);assert.equal(placed('rail').left,0);assert.ok(right>0);
    assert.ok(placed('rotate-left').left<placed('rotate-right').left,'Q stays physically left of E');
    await command('resume');await command('build-menu');controlsFit(width,height);assert.ok(node('extractor')&&node('tower')&&node('artillery')&&node('wall'));
    await command('choose',[3]);controlsFit(width,height);assert.ok(node('done-plan')&&node('clear-plan'));
    await command('pause-menu');controlsFit(width,height);assert.ok(node('done-plan')&&node('clear-plan'));await command('resume');
    await command('clear-plan');await command('worker-menu');controlsFit(width,height);await command('dismiss');await command('pause-menu');await command('handedness');await command('resume');
  }
  console.log('ok - same 56px controls fit desktop, portrait and short landscape; handedness mirrors the entire rail and attached panels');

  await command('pause-menu');assert.equal(world().paused,1);assert.ok(node('pause-dialog'));
  await command('restart');assert.equal(local().dialog,2);assert.ok(node('restart-dialog'));
  const modal=runtime.snapshot(1);await command('resume');assert.deepEqual(runtime.snapshot(1),modal);
  await command('dismiss');assert.equal(world().paused,1);assert.ok(node('pause-dialog'));assert.equal(node('restart-dialog'),undefined);
  const committed=runtime.snapshot(1),selection=runtime.snapshot(2);await runtime.replace(runtime.prepare(bytes,manifest));
  assert.deepEqual(runtime.snapshot(1),committed);assert.deepEqual(runtime.snapshot(2),selection);
  await restoreClient(runtime,{...local(),dialog:0});await command('reset-presentation');
  assert.equal(local().dialog,1);assert.ok(node('resume'),'the committed restore hook synchronizes saved pause');
  await command('resume');assert.equal(world().paused,0);assert.equal(node('pause-dialog'),undefined);
  await command('pause-menu');await command('restart');await command('accept');assert.equal(local().dialog,0);assert.equal(world().buildings.length,0);
  console.log('ok - Pause resumes explicitly; restart cancellation returns to pause; paused reload exposes Resume and confirmation accepts Enter');
} finally {await runtime.close();}
