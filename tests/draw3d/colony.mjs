// Real Scheme selection, actions, picking and presentation ownership.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony, client, at, siteAt} from '../applications/colony-state.mjs';
const output = process.argv[2], manifest = JSON.parse(readFileSync(join(output, 'manifest.json')));
const bytes = readFileSync(join(output, manifest.module)), runtime = new ReducerRuntime();
await runtime.replace(runtime.prepare(bytes, manifest)); await runtime.initialize(1); await runtime.initialize(2);
const world = () => colony(runtime.snapshot(1));
const local = () => client(runtime.snapshot(2));
async function command(binding, args = []) {
  const result = await runtime.dispatch(2, runtime.command('client', binding, args));
  for (const effect of result.effects) if (effect.kind === 'send') await runtime.dispatch(1, runtime.effectCommand(effect));
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
      assert.match(value.text,/^(?:[123UCTNFHP](?: ·)? |Esc(?: |$)|Enter )/,`${value.key} shows its hotkey`);
    }
    const padding=value.kind===5?value.properties[6]:0;
    for(const child of value.children)walk(child,left+padding,top+padding);
  }
  for(const child of card.children)walk(child,card.properties[6],card.properties[6]);
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
  await command('orbit');assert.equal(local().scale,12000);await command('orbit');assert.equal(local().scale,1000);
  assert.deepEqual([local().cameraX,local().cameraY],center);
  assert.ok([3,7,11].every(index=>runtime.view().scene.uniforms[index]===0));assert.equal(runtime.view().scene.uniforms[15],1);
  console.log('ok - smooth home, screen-aligned bounded pan, retained entities and orthographic zoom preserve match state and look-at');

  await point(11.8,20,.63);cursorAt(12,20);assert.equal(node('context'),undefined);
  await command('fabricate');await command('preview',[2]);assert.equal(local().preview,0);assert.deepEqual(runtime.snapshot(1),fresh);
  await command('confirm');assert.equal(local().chooser,true);assert.deepEqual(runtime.snapshot(1),fresh);
  assert.match(node('context-title').text,/deposit/i);assert.ok(node('extractor'));assert.equal(node('build-chooser'),undefined);
  await command('confirm');assert.deepEqual(runtime.snapshot(1),fresh);
  await command('choose',[2]);assert.deepEqual(runtime.snapshot(1),fresh);
  await command('choose',[1]);assert.equal(siteAt(world(),12,20).kind,1);assert.equal(world().ore,120);
  await point(12,20);await command('confirm');const ordered=runtime.snapshot(1);assert.ok(node('cancel-build'));
  await command('dismiss');assert.equal(local().chooser,false);assert.deepEqual(runtime.snapshot(1),ordered);
  await command('confirm');await command('cancel');assert.equal(world().buildings.length,0);assert.equal(local().chooser,false);
  await command('confirm');await command('choose',[1]);await advance(140);assert.equal(siteAt(world(),12,20).stage,2);
  await point(12,20,.94);cursorAt(12,20);const completed=runtime.snapshot(1);await command('confirm');
  assert.deepEqual(runtime.snapshot(1),completed);assert.ok(node('upgrade'));await command('improve');assert.equal(siteAt(world(),12,20).level,2);
  console.log('ok - hover opens nothing; confirm only selects; numbered build, explicit upgrade and C cancellation change the world');

  await command('dismiss');await point(12,21);const beforeChoice=runtime.snapshot(1),selectedPoint=project(12,21,.08);
  await command('confirm');assert.deepEqual(runtime.snapshot(1),beforeChoice);popupControlsFit();
  const cardBounds=placed('context'),target=[local().targetX,local().targetY];
  const dx=Math.max(cardBounds.left-selectedPoint[0],selectedPoint[0]-cardBounds.right,0),dy=Math.max(cardBounds.top-selectedPoint[1],selectedPoint[1]-cardBounds.bottom,0);
  assert.ok(dx>0||dy>0);assert.ok(cardBounds.node.properties[9]>0);assert.ok(Math.hypot(dx,dy)<150);
  await point(13,21);assert.deepEqual(placed('context'),cardBounds);assert.deepEqual([local().targetX,local().targetY],target);
  await command('choose',[1]);assert.equal(local().chooser,false);assert.equal(siteAt(world(),12,21)?.kind,3);
  await point(13,22);await command('confirm');await command('choose',[2]);assert.equal(siteAt(world(),13,22)?.kind,3);assert.equal(siteAt(world(),13,22)?.level,2);
  await point(13,22);await command('confirm');await command('cancel');assert.equal(siteAt(world(),13,22),undefined);
  console.log('ok - one context card remains anchored to its selected cell while hover moves and explicit choices target that cell');

  await runtime.restore(1,fresh);await home();await point(9,23);await command('confirm');await command('choose',[1]);await advance(140);
  assert.equal(siteAt(world(),9,23).stage,2);assert.ok(world().ore>=50);await point(9,23,1.35);await command('confirm');await command('dismiss');
  const unselectedTower=runtime.snapshot(1);await command('arm');await command('improve');await command('cancel');await command('preview',[2]);
  assert.deepEqual(runtime.snapshot(1),unselectedTower);assert.equal(local().preview,0);
  await command('confirm');await command('arm');assert.notDeepEqual(runtime.snapshot(1),unselectedTower);
  console.log('ok - unselected structures ignore arm, improve, cancel and preview commands');

  await runtime.restore(1,fresh);await home();const unselected=runtime.snapshot(1);await command('fabricate');assert.deepEqual(runtime.snapshot(1),unselected);
  await command('home');await animate();const count=world().bots.length;await command('fabricate');await command('fabricate');
  assert.equal(world().bots.filter(bot=>bot.job===4||(bot.job===6&&bot.target>0)).length,2);
  await advance(31);assert.equal(world().bots.length,count+2);assert.equal(local().chooser,true);assert.match(node('context-title').text,/hub/i);assert.ok(node('worker'));
  await command('dismiss');const hired=runtime.snapshot(1);await command('fabricate');assert.deepEqual(runtime.snapshot(1),hired);
  console.log('ok - worker fabrication is hub-only and repeated hiring keeps the selected hub card open');

  await command('suspend',[1]);await home();
  for(let turn=0;turn<4;turn++){
    await command('rotate',[0,1]);assert.equal(runtime.view().scene.requestFrame,true);await command('animate',[50]);assert.ok(local().heading%90000!==0);
    await animate();assert.equal(runtime.view().scene.requestFrame,false);await point(12,20);cursorAt(12,20);
    const start=project(12,20);await command('drag',[32,-24]);const dragged=project(12,20);
    assert.ok(Math.abs(dragged[0]-start[0]-32)<=1&&Math.abs(dragged[1]-start[1]+24)<=1);await command('drag',[-32,24]);
    const before=project(12,20);await command('pan',[0,1]);const after=project(12,20);assert.ok(Math.abs(before[0]-after[0])<=1);assert.ok(after[1]<before[1]);
    await command('pan',[0,-1]);
  }
  assert.equal(local().heading,0);
  for(const[width,height]of[[1280,720],[390,844],[844,390],[640,360]]){
    await command('viewport',[width,height]);await home();
    for(const scale of [1000,12000]){
      if(local().scale!==scale)await command('orbit');
      const before=project(8,22);await command('drag',[60,-30]);const after=project(8,22);
      assert.ok(Math.abs(after[0]-before[0]-60)<=1&&Math.abs(after[1]-before[1]+30)<=1);
      await command('drag',[-60,30]);
    }
    await command('orbit');
    await command('viewport',[width,height]);await home();await point(9,23);await command('confirm');popupControlsFit();
    const bounds=placed('context');assert.ok(bounds.left>=0&&bounds.top>=0&&bounds.right<=width&&bounds.bottom<=height,`context fits ${width}x${height}`);
    assert.deepEqual(runtime.view().scene.viewport,[0,0,width,height]);await command('dismiss');await command('center');await point(12.4,20,.63);cursorAt(12,20);
  }
  console.log('ok - rotated and narrow-view picking remain accurate; every context action fits desktop, portrait and landscape');

  await command('suspend',[0]);await command('restart');assert.equal(world().paused,1);assert.ok(node('restart-dialog'));
  const modal=runtime.snapshot(1);await command('suspend',[-1]);assert.deepEqual(runtime.snapshot(1),modal);
  const restartCamera=[local().cameraX,local().cameraY];await command('viewport',[700,420]);
  await command('drag',[60,30]);
  assert.equal(local().restartMode,1);assert.deepEqual([local().cameraX,local().cameraY],restartCamera);assert.ok(node('restart-dialog'));
  await command('dismiss');assert.equal(world().paused,0);assert.equal(node('restart-dialog'),undefined);
  await command('suspend',[1]);await command('restart');await command('dismiss');assert.equal(world().paused,1);
  const committed=runtime.snapshot(1),selection=runtime.snapshot(2);
  await runtime.replace(runtime.prepare(bytes,manifest));await runtime.initialize(1);await runtime.initialize(2);
  assert.deepEqual(runtime.snapshot(1),committed);assert.deepEqual(runtime.snapshot(2),selection);
  if(process.argv[3]){
    const previous=JSON.parse(readFileSync(join(process.argv[3],'manifest.json'))),oldBytes=readFileSync(join(process.argv[3],previous.module));
    assert.notDeepEqual(oldBytes,bytes);await runtime.replace(runtime.prepare(oldBytes,previous));
    assert.deepEqual(runtime.snapshot(1),committed);assert.deepEqual(runtime.snapshot(2),selection);
    await runtime.replace(runtime.prepare(bytes,manifest));assert.deepEqual(runtime.snapshot(1),committed);assert.deepEqual(runtime.snapshot(2),selection);
  }
  await command('restart');await command('confirm');assert.equal(local().restartMode,0);assert.equal(world().buildings.length,0);
  console.log('ok - restart requires confirmation, restores prior pause on dismissal, and compatible reload preserves both owners');
} finally { await runtime.close(); }
