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
      assert.match(value.text,/^(?:[123UCTNFHPR]|Esc|Enter|Close)$/,`${value.key} shows its hotkey`);
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
  assert.equal(local().chooser,true);assert.deepEqual(runtime.snapshot(1),fresh);
  assert.ok(node('extractor'));assert.equal(node('tower'),undefined);popupControlsFit();
  await point(12,22);await command('confirm');assert.ok(node('tower')&&node('artillery')&&node('house'));
  assert.equal(node('extractor'),undefined);assert.deepEqual(runtime.snapshot(1),fresh);popupControlsFit();
  const unpaid=runtime.snapshot(2);await command('pause-menu');
  for(const confirming of [false,true]) {
    if(confirming)await command('restart');
    const covered=runtime.snapshot(2),stopped=runtime.snapshot(1);
    for(const [binding,args]of[['center',[]],['restart-seed',[42]],['choose',[3]],['home',[]],['preview',[4]],['confirm',[]]]) {
      await command(binding,args);assert.deepEqual(runtime.snapshot(2),covered,`${binding} preserves the unpaid selection behind the dialog`);
      assert.deepEqual(runtime.snapshot(1),stopped);
    }
    if(confirming){await command('resume');assert.deepEqual(runtime.snapshot(2),covered);await command('dismiss');assert.equal(world().paused,1);}
  }
  await command('resume');assert.deepEqual(runtime.snapshot(2),unpaid);assert.deepEqual(runtime.snapshot(1),fresh);
  await point(12,20);await command('confirm');await command('choose',[1]);
  assert.equal(siteAt(world(),12,20).kind,1);assert.equal(world().ore,120);assert.equal(local().chooser,false);assert.equal(local().buildKind,0);
  await advance(140);assert.equal(siteAt(world(),12,20).stage,2);await point(12,20,.94);await command('confirm');
  assert.ok(node('upgrade'));await command('improve');assert.equal(siteAt(world(),12,20).level,2);
  console.log('ok - selecting a deposit or empty site is free; choices and costs are contextual; existing buildings upgrade explicitly');

  await command('dismiss');await point(13,21);await command('confirm');
  const before=runtime.snapshot(1),submitted=await runtime.dispatch(2,runtime.command('client','choose',[3]));
  assert.equal(submitted.effects.length,2);assert.equal(local().buildKind,4);assert.deepEqual(runtime.snapshot(1),before);
  const pending=runtime.snapshot(2);
  for(const [binding,args]of[['choose',[2]],['center',[]],['home',[]],['fabricate',[]],['confirm',[]]]) {
    await command(binding,args);assert.deepEqual(runtime.snapshot(2),pending,`${binding} cannot replace an in-flight site`);
  }
  await command('pause-menu');assert.equal(world().paused,1);assert.equal(node('restart-menu').properties[1],0);
  await effects(submitted.effects);assert.equal(local().buildKind,0);assert.equal(local().lastKind,4);assert.ok(node('pause-dialog'));
  await command('resume');assert.equal(siteAt(world(),13,21).kind,4);assert.equal(local().chooser,false);
  const spent=world().spent;await point(14,21);await command('confirm');assert.equal(world().spent,spent);assert.equal(local().choiceKind,4);
  await command('confirm');assert.equal(world().spent,spent+8);await command('confirm');await command('confirm');
  assert.equal(world().spent,spent+8);assert.ok(node('cancel-build'),'occupied-site taps inspect without cancelling');
  console.log('ok - one in-flight order locks its site through settlement; accepted memory drives the next second-tap build');

  await command('dismiss');await point(15,21);await command('confirm');
  const failedWorld=runtime.snapshot(1),outgoing=await runtime.dispatch(2,runtime.command('client','choose',[2]));
  assert.equal(local().buildKind,2);await effects(outgoing.effects.filter(effect=>effect.owner===2));
  assert.deepEqual(runtime.snapshot(1),failedWorld);assert.equal(local().buildKind,0);assert.equal(local().choiceKind,2);assert.equal(local().lastKind,4);
  assert.equal(local().chooser,true);await command('confirm');assert.equal(siteAt(world(),15,21).kind,2);assert.equal(local().lastKind,2);
  console.log('ok - settlement without a durable reply keeps the exact attempted type retryable and changes memory only on acceptance');

  await runtime.restore(1,fresh);await command('center');await home();const unselected=runtime.snapshot(1);
  await command('fabricate');assert.deepEqual(runtime.snapshot(1),unselected);
  assert.equal(node('worker-menu'),undefined);await command('home');await animate();assert.deepEqual(runtime.snapshot(1),unselected);assert.ok(node('worker'));
  assert.deepEqual(node('worker').action.command,runtime.command('client','fabricate'));
  assert.deepEqual(manifest.settings.keys.f,['fabricate']);assert.equal(manifest.settings.keys.g,undefined);
  await command('fabricate');await command('fabricate');assert.equal(local().chooser,true);await command('dismiss');
  assert.equal(world().ore,110);assert.equal(local().chooser,false);await command('home');await animate();
  assert.ok(node('repair')&&node('worker'));assert.equal(node('close-context'),undefined);await command('fabricate');assert.equal(world().ore,85);await command('dismiss');
  console.log('ok - hub actions open without charge; repeated F hiring and hub repair use explicit typed requests');

  await home();
  for(let turn=0;turn<4;turn++){
    await command('rotate',[0,1]);assert.equal(runtime.view().scene.requestFrame,true);await command('animate',[50]);assert.ok(local().heading%90000!==0);
    await animate();await point(12,20);cursorAt(12,20);
    const m=runtime.view().scene.uniforms,{width,height}=local();
    const x=[m[0]*width,m[1]*height],y=[m[4]*width,m[5]*height];
    for(const axis of [x,y])assert.ok(Math.abs(Math.abs(axis[0]/axis[1])-2)<.0001,'quarter-turn ground edges have 2:1 screen slopes');
    assert.ok(Math.abs(Math.abs(x[0])-Math.abs(y[0]))<.0001,'diagonal yaw gives symmetric diamonds');
    const start=project(12,20);await command('drag',[32,-24]);const dragged=project(12,20);
    assert.ok(Math.abs(dragged[0]-start[0]-32)<=1&&Math.abs(dragged[1]-start[1]+24)<=1);await command('drag',[-32,24]);
  }
  console.log('ok - all four dimetric snaps project 2:1 ground diamonds with shared picking and smooth screen-space drag');
  for(const[width,height]of[[1100,760],[390,844],[640,360],[568,320],[320,568],[360,640]]){
    await command('viewport',[width,height]);await home();controlsFit(width,height);
    const right=placed('rail').left;await command('pause-menu');controlsFit(width,height);assert.ok(node('resume')&&node('restart-menu')&&node('handedness'));
    assert.deepEqual(node('rotate-left').action.command,runtime.command('client','turn',[-1]));
    assert.deepEqual(node('rotate-right').action.command,runtime.command('client','turn',[1]));
    await command('handedness');controlsFit(width,height);assert.equal(placed('rail').left,0);assert.ok(right>0);
    assert.ok(placed('rotate-left').left<placed('rotate-right').left,'Q stays physically left of E');
    await command('resume');await point(12,22);await command('confirm');controlsFit(width,height);popupControlsFit();assert.ok(node('tower')&&node('artillery')&&node('house'));
    const target=project(12,22),card=placed('context');assert.ok(target[0]-12<card.left||target[0]-12>=card.right||target[1]-16<card.top||target[1]-16>=card.bottom,'selected tile remains outside the popup');
    await command('home');await animate();controlsFit(width,height);await command('dismiss');await command('pause-menu');await command('handedness');await command('resume');
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
