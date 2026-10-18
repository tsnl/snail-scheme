// Chromium input, WebGPU readback and durable reopen for either 3D package.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {colony, client, siteAt, colonyWords} from '../applications/colony-state.mjs';
const origin = process.argv[2], devtools = process.argv[3] ?? 'http://127.0.0.1:9452';
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const target = await (await fetch(`${devtools}/json/new?about:blank`, {method: 'PUT'})).json();
const ws = new WebSocket(target.webSocketDebuggerUrl), pending = new Map(); let sequence = 0;
await new Promise(resolve => ws.addEventListener('open', resolve, {once: true}));
ws.onmessage = event => { const data = JSON.parse(event.data); if (data.id) { pending.get(data.id)?.(data); pending.delete(data.id); } };
function call(method, params = {}) {
  return new Promise((resolve, reject) => { const id = ++sequence;
    const timeout = setTimeout(() => reject(new Error(`CDP timeout: ${method}`)), 30000);
    pending.set(id, data => { clearTimeout(timeout); data.error ? reject(new Error(data.error.message)) : resolve(data.result); });
    ws.send(JSON.stringify({id, method, params})); });
}
async function evaluate(expression) {
  const result = await call('Runtime.evaluate', {expression, awaitPromise: true, returnByValue: true});
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.exception?.description ?? result.exceptionDetails.text);
  return result.result.value;
}
async function until(test, message, timeout = 30000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) { const value = await test(); if (value) return value; await pause(100); }
  throw new Error(message);
}
const world = async () => colony(await evaluate('snailApp.runtime.snapshot(1)'));
const local = async () => client(await evaluate('snailApp.runtime.snapshot(2)'));
const has = key => evaluate(`!!document.querySelector('[data-ui-key="${key}"]')`);
const command = async (binding,args=[]) => {await evaluate(`snailApp.local(${JSON.stringify(binding)},${JSON.stringify(args)})`);await settled();};
const displayFrame = () => evaluate('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))');
// Freeze only the fixture clock; a paused World now correctly opens its menu.
const settled = async () => {await evaluate('snailApp.drainUpdates()');await evaluate('snailApp.session.stopClock()');await until(() => evaluate('!snailApp.localWork && !snailApp.dirty'), 'input did not settle');};
async function press(position) {
  await call('Input.dispatchMouseEvent', {type: 'mousePressed', ...position, button: 'left', clickCount: 1});
  await call('Input.dispatchMouseEvent', {type: 'mouseReleased', ...position, button: 'left', clickCount: 1}); await settled();
}
async function click(key) {
  const position = await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="${key}"]').getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);
  await press(position);
}
async function pointCell(x, y, click = false, z = 0) {
  const hub=(await world()).surveys.find(s=>s.radius===9); x+=hub.x-8; y+=hub.y-22;
  const position = await evaluate(`(()=>{const scene=snailApp.runtime.view().scene,m=scene.uniforms,r=snailApp.canvas.getBoundingClientRect(),v=scene.viewport??[0,0,r.width,r.height];
    return{x:r.x+v[0]+(m[0]*${x}-m[4]*${y}+m[8]*${z}+m[12]+1)*v[2]/2,y:r.y+v[1]+(1-(m[1]*${x}-m[5]*${y}+m[9]*${z}+m[13]))*v[3]/2}})()`);
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', ...position}); await settled();
  if (click) await press(position);
  return position;
}
async function frameCell(x,y) {
  const hub=(await world()).surveys.find(s=>s.radius===9);
  await command('inspect-attack',[hub.x+x-8,hub.y+y-22]);
  await until(async()=>!(await local()).homing,'frame selected test cell');
  const point=await pointCell(x,y);
  if(!await evaluate(`document.elementFromPoint(${point.x},${point.y})===snailApp.canvas`))
    await command('drag',[0,Math.round((await local()).height*.22)]);
}
async function capture(suffix='') {
  if(await has('dialog-backdrop')){await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:2,y:2});await displayFrame();}
  const layout=await evaluate(`(()=>{
    const controls=[...document.querySelectorAll('[data-ui] button:not([data-ui-key="dialog-backdrop"]):not([data-ui-key^="attack-inspect-"]),[data-ui] .snail-ui-kind-6')];
    const invalid=controls.map(node=>{const r=node.getBoundingClientRect();return{key:node.dataset.uiKey,x:r.x,y:r.y,width:r.width,height:r.height,right:r.right,bottom:r.bottom}})
      .filter(r=>{const menu=['resume','restart-menu','handedness','dismiss-restart','accept-restart'].includes(r.key);
        return r.x<0||r.y<0||r.right>innerWidth+.5||r.bottom>innerHeight+.5||r.width!==(menu?208:56)||r.height!==(menu?48:56)});
    const clipped=[...document.querySelectorAll('.snail-ui-button-label,[data-ui-key$="-caption"],[data-ui-key$="-readout-label"]')]
      .filter(node=>node.scrollWidth>node.clientWidth+1||node.scrollHeight>node.clientHeight+1).map(node=>({key:node.closest('[data-ui-key]').dataset.uiKey,text:node.textContent}));
    const overlap=(a,b)=>a.left<b.right&&b.left<a.right&&a.top<b.bottom&&b.top<a.bottom;
    const boxes=[...document.querySelectorAll('[data-ui-key^="attack-toast-"]')].map(node=>({key:node.dataset.uiKey,rect:node.getBoundingClientRect()}));
    const obstacles=[...document.querySelectorAll('[data-ui] button:not([data-ui-key^="attack-inspect-"]):not([data-ui-key="dialog-backdrop"]),[data-ui] .snail-ui-kind-6,[data-ui-key="context"],[data-ui-key="plan-status"],[data-ui-key="onboarding"]')];
    const covered=boxes.flatMap(box=>obstacles.filter(node=>!node.closest('[data-ui-key^="attack-toast-"]')&&overlap(box.rect,node.getBoundingClientRect())).map(node=>({toast:box.key,control:node.dataset.uiKey})));
    const insetSizes=(snailApp.runtime.view().scene.insets??[]).map(inset=>inset.rect.slice(2));
    const dismissOverlap=(snailApp.runtime.view().scene.insets??[]).filter(inset=>{const r=inset.rect,b=document.querySelector('[data-ui-key="attack-dismiss-'+inset.key+'"]')?.getBoundingClientRect();
      return b&&overlap({left:r[0],top:r[1],right:r[0]+r[2],bottom:r[1]+r[3]},b);});
    const escaped=(snailApp.runtime.view().scene.insets??[]).filter(inset=>{const b=boxes.find(box=>box.key==='attack-toast-'+inset.key)?.rect,r=inset.rect;
      return !b||r[0]<b.left||r[1]<b.top||r[0]+r[2]>b.right||r[1]+r[3]>b.bottom;});
    const dimAlerts=[...document.querySelectorAll('[data-ui-key^="attack-label-"]')].filter(node=>getComputedStyle(node).color!=='rgb(255, 255, 255)').map(node=>node.dataset.uiKey);
    const hint=document.querySelector('[data-ui-key="onboarding"]'),build=document.querySelector('[data-ui-key="build-menu"]');
    const anchored=!hint?null:(()=>{const h=hint.getBoundingClientRect(),b=build.getBoundingClientRect(),left=hint.dataset.arrow==='1';
      return{centerDelta:h.y+h.height/2-b.y-b.height/2,gap:left?h.left-b.right:b.left-h.right,
        inside:h.left>=0&&h.right<=innerWidth&&h.top>=0&&h.bottom<=innerHeight};})();
    const shade=document.querySelector('[data-ui-key="dialog-backdrop"]'),backdrop=!shade?null:(()=>{const r=shade.getBoundingClientRect(),color=getComputedStyle(shade).backgroundColor;
      return{rect:[r.x,r.y,r.width,r.height],alpha:color.startsWith('rgba(')?parseFloat(color.split(',').at(-1)):1};})();
    const dialog=document.querySelector('[data-ui-key="pause-dialog"],[data-ui-key="restart-dialog"]');
    const blocked=![...document.querySelectorAll('[data-ui-key="pause-dialog"] button:enabled,[data-ui-key="restart-dialog"] button:enabled')]
      .every(button=>{const r=button.getBoundingClientRect();return button.contains(document.elementFromPoint(r.x+r.width/2,r.y+r.height/2));});
    const error=document.querySelector('.connection[data-state="error"]');
    const errorCoversMenu=!!(dialog&&error&&overlap(dialog.getBoundingClientRect(),error.getBoundingClientRect()));
    return{invalid,clipped,covered,escaped,dimAlerts,insetSizes,dismissOverlap,anchored,backdrop,blocked,errorCoversMenu,scrollWidth:document.documentElement.scrollWidth,width:document.documentElement.clientWidth};})()`);
  assert.deepEqual(layout.invalid,[],'circles and labeled menu rows keep their touch size and stay on screen');
  assert.equal(layout.blocked,false,'enabled menu actions remain reachable above shell overlays');
  assert.equal(layout.errorCoversMenu,false,'save errors remain outside the menu');
  if(layout.backdrop){assert.ok(layout.backdrop.alpha>0&&layout.backdrop.alpha<1,'hovering the backdrop keeps the world visible');const expected=await evaluate('[0,0,innerWidth,innerHeight]');assert.ok(layout.backdrop.rect.every((value,index)=>Math.abs(value-expected[index])<=1),'the dim backdrop covers the viewport within CSS subpixel rounding');}
  if(layout.anchored)assert.deepEqual(layout.anchored,{centerDelta:0,gap:14,inside:true},'the callout points directly at Build');
  assert.deepEqual(layout.clipped,[],'visible hotkeys, costs and readout labels fit');
  assert.deepEqual(layout.dismissOverlap,[],'dismiss targets stay beside the thumbnails');
  assert.deepEqual(layout.dimAlerts,[],'attack labels retain white-on-red contrast');
  assert.deepEqual(layout.covered,[],'attack notifications do not cover controls or selected panels');
  assert.deepEqual(layout.escaped,[],'attack thumbnails stay within their toast bounds');
  for(const size of layout.insetSizes)assert.deepEqual(size,[64,48],'attack thumbnails remain small on every viewport');
  assert.equal(layout.scrollWidth,layout.width,'the page does not scroll sideways');
  if(!process.argv[4])return;
  const shot=await call('Page.captureScreenshot',{format:'png'});
  writeFileSync(process.argv[4].replace('.png',`${suffix}.png`),Buffer.from(shot.data,'base64'));
}
async function touchAt(position) {
  await call('Input.dispatchTouchEvent', {type:'touchStart',touchPoints:[{...position,id:1}]});await displayFrame();
  await call('Input.dispatchTouchEvent', {type:'touchEnd',touchPoints:[]});await displayFrame();await settled();
}
async function touchControl(key) {
  await touchAt(await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="${key}"]').getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`));
}
async function key(key, code) {
  await evaluate('document.activeElement?.blur()');
  const windowsVirtualKeyCode=key==='Enter'?13:key==='Escape'?27:key===' '?32:key.toUpperCase().charCodeAt(0);
  await call('Input.dispatchKeyEvent', {type: 'keyDown', key, code,windowsVirtualKeyCode,...(key==='Enter'?{text:'\r'}:{})});
  await call('Input.dispatchKeyEvent', {type: 'keyUp', key, code,windowsVirtualKeyCode}); await settled();
}
async function resize(width,height,dpr=1) {
  await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:dpr,mobile:width<700});
  await pause(200);await settled();
}
async function holdNextSave() {
  await evaluate(`(()=>{const store=snailApp.session.store,commit=store.commit;globalThis.menuWriteCount=0;delete globalThis.releaseMenuSave;
    store.commit=(...args)=>{menuWriteCount++;return new Promise(resolve=>{globalThis.releaseMenuSave=()=>{store.commit=commit;resolve(commit.apply(store,args));};});};})()`);
}
async function failNextSave() {
  await evaluate(`(()=>{const store=snailApp.session.store,commit=store.commit;store.commit=(...args)=>{store.commit=commit;return Promise.reject(new Error('controlled menu save failure'));};})()`);
}
async function complete(ticks=180) {
  await evaluate(`(async()=>{snailApp.session.stopClock();for(let i=0;i<${ticks};i++)await snailApp.session.local.submit(snailApp.runtime.command('match','advance'));})()`);
  await settled();
}
try {
  await call('Runtime.enable');await call('Network.enable');await call('Network.setCacheDisabled',{cacheDisabled:true});
  await call('Page.navigate',{url:origin});await call('Page.bringToFront');await until(()=>evaluate('!!globalThis.snailApp'),'3D startup');
  await resize(1100,760);if(await has('pause-dialog'))await command('resume');
  await command('restart-seed',[1]);await evaluate('snailApp.session.stopClock()');await command('center');
  assert.equal((await world()).buildings.length,0);assert.equal(await has('context'),false);
  assert.equal(await evaluate('!!snailApp.manifest.settings.controller || !!snailApp.manifest.settings.controllerAxes'),false);
  assert.equal(await evaluate('snailApp.manifest.settings.rotationHandler??null'),null);
  assert.ok(await has('rotate-left')&&await has('rotate-right'),'rotation buttons are immediately available');
  await evaluate('snailApp.session.stopClock()');
  const freshHint=await world(),hintHub=freshHint.surveys.find(s=>s.radius===9),hintAlerts=structuredClone(freshHint);
  hintAlerts.alerts=[0,1,4].map((kind,index)=>({x:hintHub.x+index*2,y:hintHub.y,kind,tick:hintAlerts.tick}));
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(hintAlerts))})`);await settled();
  for(const [width,height]of[[320,568],[390,844],[568,320],[640,360],[1100,760]]) {
    await resize(width,height);assert.ok(await has('onboarding'));await capture(`-hint-${width}x${height}`);
    await click('pause');await capture(`-pause-${width}x${height}`);await click('handedness');await click('resume');
    await capture(`-hint-${width}x${height}-left`);
    assert.equal(await evaluate(`document.querySelector('[data-ui-key="rotate-left"]').getBoundingClientRect().left<document.querySelector('[data-ui-key="rotate-right"]').getBoundingClientRect().left`),true);
    await click('pause');await click('handedness');await click('resume');
  }
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(freshHint))})`);await settled();
  const uploads=await evaluate('globalThis.retainedScene=snailApp.runtime.view().scene;snailApp.renderer.resources.uploads');
  await command('drift',[1,0]);assert.equal(await evaluate('snailApp.renderer.resources.uploads'),uploads);
  assert.equal(await evaluate('[0,3,10].every(key=>snailApp.runtime.view().scene.batches.find(b=>b.key===key)===retainedScene.batches.find(b=>b.key===key))'),true);
  await command('home');await until(async()=>!(await local()).homing,'smooth home');await key('Escape','Escape');
  const center=[(await local()).cameraX,(await local()).cameraY],scale=(await local()).scale;
  const wheel=await pointCell(9,23);await call('Input.dispatchMouseEvent',{type:'mouseWheel',...wheel,deltaX:0,deltaY:200});
  await until(async()=>(await local()).scale>scale,'wheel zoom');
  const wheelScale=(await local()).scale;await key('v','KeyV');assert.equal((await local()).scale,wheelScale);
  assert.equal(await has('orbit'),false);await command('zoom',[-200]);assert.ok((await local()).scale<wheelScale,'zooming back reduces scale without an Orbit reset');
  await click('rotate-right');await until(async()=>(await local()).turnElapsed===300,'visible clockwise rotation');assert.equal((await local()).heading,90000);
  await click('rotate-left');await until(async()=>(await local()).turnElapsed===300,'visible counterclockwise rotation');assert.equal((await local()).heading,0);
  assert.deepEqual([(await local()).cameraX,(await local()).cameraY],center);
  console.log('ok - pan retains geometry; wheel zoom preserves look-at; visible rotation buttons make quarter turns');

  await pointCell(12,20,true);assert.equal(await has('context'),false);
  const unbuilt=await evaluate('snailApp.runtime.snapshot(1)');await click('build-menu');await capture('-brush-picker');await click('extractor');
  await frameCell(12,20);await pointCell(12,20,true);assert.equal((await local()).plan.length,1);
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),unbuilt,'ghosts are unpaid');await capture('-planned-extractor');
  const planned=(await local()).plan;await click('pause');assert.equal((await world()).paused,1);await capture('-pause-plan');
  const stopped=await evaluate('snailApp.runtime.snapshot(1)'),covered=await evaluate('snailApp.runtime.snapshot(2)');
  for(const binding of ['center','clear-plan','done-plan'])await command(binding);
  await command('restart-seed',[42]);await key('f','KeyF');await key('e','KeyE');await key('4','Digit4');
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),stopped);assert.deepEqual(await evaluate('snailApp.runtime.snapshot(2)'),covered);
  await holdNextSave();await evaluate(`document.querySelector('[data-ui-key="resume"]').click()`);
  await until(()=>evaluate('!!globalThis.releaseMenuSave'),'delayed Resume save');assert.equal((await local()).dialogPending,2);assert.equal((await world()).paused,1);
  await until(()=>evaluate(`document.querySelector('[data-ui-key="resume"]').textContent.includes('Resuming')`),'pending Resume label did not render');
  await evaluate(`void snailApp.local('restart');void snailApp.local('resume')`);await evaluate('releaseMenuSave()');await settled();
  assert.equal(await evaluate('menuWriteCount'),1);assert.equal((await world()).paused,0);assert.equal((await local()).dialog,0);assert.deepEqual((await local()).plan,planned);
  await click('pause');await failNextSave();await click('resume');assert.equal((await world()).paused,1);assert.equal((await local()).dialog,1);assert.deepEqual((await local()).plan,planned);
  await resize(568,320);await capture('-failed-resume-568x320');await click('handedness');await capture('-failed-resume-568x320-left');
  await click('handedness');await resize(1100,760);
  await click('resume');await click('pause');
  await click('restart-menu');await capture('-restart-plan');await command('restart-seed',[42]);await command('resume');
  assert.ok(await has('restart-dialog'));const beforeFailedReset=await evaluate('snailApp.runtime.snapshot(1)');
  await failNextSave();await click('accept-restart');assert.ok(await has('restart-dialog'));assert.equal((await local()).dialogPending,0);
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),beforeFailedReset);assert.deepEqual((await local()).plan,planned);
  await resize(568,320);await capture('-failed-restart-568x320');await click('dismiss-restart');await click('handedness');await click('restart-menu');
  await capture('-failed-restart-568x320-left');await click('dismiss-restart');await click('handedness');await click('restart-menu');await resize(1100,760);
  await key('Escape','Escape');assert.ok(await has('pause-dialog'));assert.equal((await world()).paused,1);
  await press({x:20,y:20});assert.equal((await world()).paused,0);assert.deepEqual((await local()).plan,planned);
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),unbuilt);await evaluate('snailApp.session.stopClock()');
  await pointCell(12,20,true);assert.equal((await local()).plan.length,0);await pointCell(12,20,true);
  await click('done-plan');assert.equal(siteAt(await world(),12,20)?.kind,1);assert.equal((await local()).pending.length,0);
  await click('clear-plan');await complete();assert.equal(siteAt(await world(),12,20)?.stage,2);
  await pointCell(12,20,true,.94);assert.equal(await has('upgrade'),true);await click('upgrade');assert.equal(siteAt(await world(),12,20)?.level,2);
  await key('Escape','Escape');
  console.log('ok - brush clicks toggle unpaid ghosts; Done commits and settles; existing buildings retain explicit upgrades');

  await key('4','Digit4');await frameCell(13,21);const planSpent=(await world()).spent;
  await pointCell(13,21,true);await pointCell(14,21,true);assert.equal((await local()).plan.length,2);
  await click('done-plan');assert.ok(siteAt(await world(),13,21)&&siteAt(await world(),14,21));assert.equal((await world()).spent,planSpent+16);
  await click('clear-plan');const hireBank=(await world()).ore;
  await click('worker-menu');assert.equal((await world()).ore,hireBank);await capture('-worker-panel');
  await click('worker');assert.equal((await world()).ore,hireBank-25);await key('f','KeyF');assert.equal((await world()).ore,hireBank-50);
  assert.equal(await has('worker-panel'),true);await key('Escape','Escape');assert.equal(await has('worker-panel'),false);
  await key('h','KeyH');await until(async()=>!(await local()).homing,'home selects hub');assert.equal(await has('repair'),true);assert.equal(await has('worker'),true);assert.equal(await has('close-context'),false);await capture('-hub');
  await key('Escape','Escape');await key('e','KeyE');await until(async()=>(await local()).turnElapsed===300,'keyboard rotation');
  await frameCell(12,20);await pointCell(12,20,true,.94);assert.match(await evaluate('document.querySelector("[data-ui-key=context-title]").textContent'),/extractor/i);
  await key('q','KeyQ');await until(async()=>(await local()).turnElapsed===300,'return rotation');await key('Escape','Escape');
  const ignored=await evaluate('({world:snailApp.runtime.snapshot(1),client:snailApp.runtime.snapshot(2)})');
  await evaluate(`(()=>{const pad={index:0,id:'ignored gamepad',connected:true,axes:[.8,-.8],buttons:Array.from({length:16},()=>({pressed:true}))};
    Object.defineProperty(navigator,'getGamepads',{configurable:true,value:()=>[pad]});snailApp.input.pollController(performance.now(),0);delete navigator.getGamepads;})()`);
  await settled();assert.deepEqual(await evaluate('({world:snailApp.runtime.snapshot(1),client:snailApp.runtime.snapshot(2)})'),ignored);
  console.log('ok - multi-cell Done pays once per cell; worker panel opens freely, F matches hiring, and rotated picking remains accurate');

  const pixels=await evaluate(`(async()=>{const frame=snailApp.runtime.view(),p=await snailApp.renderer.readPixels(frame.scene);return{
    vertices:frame.scene.batches.reduce((n,b)=>n+b.vertices.length/10,0),bytes:p.bytes.length,colors:new Set(Array.from(p.bytes).filter((_,i)=>i%4!==3)).size};})()`);
  assert.ok(pixels.colors>30&&pixels.vertices>1000);console.log('ok - real WebGPU scene has varied pixels and geometry',pixels);
  await click('pause');await click('restart-menu');assert.equal(await has('restart-dialog'),true);assert.equal((await world()).paused,1);await capture('-restart');
  await press({x:20,y:20});assert.ok(await has('pause-dialog'));assert.equal((await world()).paused,1);
  const committed=await evaluate('snailApp.runtime.snapshot(1)');await evaluate('globalThis.fixtureReload=true');await call('Page.reload');
  await until(()=>evaluate('!globalThis.fixtureReload && !!globalThis.snailApp'),'durable reopen');await settled();
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),committed);assert.ok(await has('resume'));assert.ok(await has('pause-dialog'));
  assert.equal((await local()).dialog,1,'the restore hook synchronizes committed World pause');await capture('-paused-reload');
  await click('resume');await evaluate('snailApp.session.stopClock()');assert.equal((await world()).paused,0);assert.equal(await has('pause-dialog'),false);

  const alerts=await world(),hub=alerts.surveys.find(value=>value.radius===9);
  alerts.alerts=[0,1,4].map((kind,index)=>({x:hub.x+index*2,y:hub.y,kind,tick:alerts.tick}));
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(alerts))})`);await settled();
  await call('Emulation.setTouchEmulationEnabled',{enabled:true,maxTouchPoints:2});
  for(const [width,height,dpr] of [[390,844,3],[640,360,2],[568,320,2],[320,568,2],[360,640,2]]) {
    await resize(width,height,dpr);await command('center');await command('home');await until(async()=>!(await local()).homing,'responsive hub');await capture(`-${width}x${height}`);
    assert.ok(await evaluate(`document.querySelectorAll('[data-ui-key^="attack-toast-"]').length>0`),'visible attack notifications remain available');
    const heading=(await local()).heading,turnWorld=await evaluate('snailApp.runtime.snapshot(1)');
    await touchControl('rotate-right');await until(async()=>(await local()).turnElapsed===300,'touch clockwise turn');
    assert.equal((await local()).heading,(heading+90000)%360000);
    await touchControl('rotate-left');await until(async()=>(await local()).turnElapsed===300,'touch counterclockwise turn');
    assert.equal((await local()).heading,heading);assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),turnWorld);
    const native=await evaluate('({width:snailApp.canvas.width,height:snailApp.canvas.height})');
    assert.deepEqual(native,{width:width*dpr,height:height*dpr});
    await touchControl('pause');await capture(`-${width}x${height}-pause`);
    await touchControl('handedness');assert.equal((await local()).leftHanded,true);await touchControl('resume');await capture(`-${width}x${height}-left`);
    await touchControl('pause');await touchControl('handedness');await touchControl('resume');await key('Escape','Escape');
    await touchControl('build-menu');await capture(`-${width}x${height}-brushes`);await touchControl('wall');
    await frameCell(15,21);const bank=(await world()).ore;await touchAt(await pointCell(15,21));
    assert.equal((await local()).plan.length,1);assert.equal((await world()).ore,bank);await capture(`-${width}x${height}-plan`);
    await touchAt(await pointCell(15,21));assert.equal((await local()).plan.length,0);await touchControl('clear-plan');
  }
  const firstAlert=(await world()).alerts[0],alertKey=(firstAlert.x+firstAlert.y*384)*8+firstAlert.kind;
  const beforeDismiss=await evaluate('snailApp.runtime.snapshot(1)');await touchControl(`attack-dismiss-${alertKey}`);
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),beforeDismiss);assert.equal(await has(`attack-toast-${alertKey}`),false);
  const repeat=await world();repeat.tick++;repeat.alerts=repeat.alerts.map(alert=>({...alert,tick:repeat.tick}));
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(repeat))})`);await settled();
  assert.equal(await has(`attack-toast-${alertKey}`),false,'ongoing fire stays dismissed');
  repeat.tick+=79;repeat.alerts=repeat.alerts.map(alert=>({...alert,tick:repeat.tick}));
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(repeat))})`);await settled();
  assert.equal(await has(`attack-toast-${alertKey}`),true,'later attack is visible again');
  const inspect=await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="attack-inspect-${alertKey}"]').getBoundingClientRect();return{x:r.x+24,y:r.y+48}})()`);
  await touchAt(inspect);await until(async()=>!(await local()).homing,'toast thumbnail inspects attack');
  assert.deepEqual([(await local()).cameraX,(await local()).cameraY],[firstAlert.x*1000,firstAlert.y*1000]);
  await resize(390,844,3);await command('center');await frameCell(15,21);await touchControl('build-menu');await touchControl('wall');
  await touchAt(await pointCell(15,21));await touchControl('done-plan');assert.ok(siteAt(await world(),15,21));await touchControl('clear-plan');
  await touchAt(await pointCell(15,21));assert.equal(await has('cancel-build'),true);await touchControl('cancel-build');assert.equal(siteAt(await world(),15,21),undefined);
  await key('Escape','Escape');const beforeDrag=await pointCell(12,20),dragWorld=await evaluate('snailApp.runtime.snapshot(1)');
  await call('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{id:1,x:100,y:610}]});await displayFrame();
  await call('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{id:1,x:120,y:620}]});await displayFrame();
  await call('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{id:1,x:160,y:650}]});await displayFrame();
  await call('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await displayFrame();await settled();
  const afterDrag=await pointCell(12,20);assert.ok(Math.abs(afterDrag.x-beforeDrag.x-60)<=2&&Math.abs(afterDrag.y-beforeDrag.y-40)<=2);
  assert.equal((await local()).chooser,false);assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),dragWorld);
  const beforePinch=await evaluate('snailApp.runtime.snapshot(1)'),beforeScale=(await local()).scale,pinchCenter=[(await local()).cameraX,(await local()).cameraY];
  await call('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:[{id:1,x:100,y:610},{id:2,x:190,y:610}]});await displayFrame();
  await call('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:[{id:1,x:65,y:610},{id:2,x:225,y:610}]});await displayFrame();
  await call('Input.dispatchTouchEvent',{type:'touchEnd',touchPoints:[]});await displayFrame();await settled();
  assert.ok((await local()).scale<beforeScale);assert.equal((await local()).chooser,false);assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),beforePinch);
  assert.deepEqual([(await local()).cameraX,(await local()).cameraY],pinchCenter);
  await call('Emulation.setTouchEmulationEnabled',{enabled:false});await resize(1100,760);await command('center');await capture();
  console.log('ok - centered Pause preserves plans; cancellation stays paused; durable paused reopen, native DPR, touch plans and mirrored rail fit 320–1100px without clipping');
  await click('pause');await click('restart-menu');const oldMarker=(await world()).runMarker;await holdNextSave();
  await evaluate(`document.querySelector('[data-ui-key="accept-restart"]').click()`);await until(()=>evaluate('!!globalThis.releaseMenuSave'),'delayed Restart save');
  assert.equal((await local()).dialogPending,3);assert.equal((await world()).runMarker,oldMarker);await until(()=>evaluate(`document.querySelector('[data-ui-key="accept-restart"]').textContent.includes('Restarting')`),'pending Restart label did not render');
  await evaluate(`void snailApp.local('accept-restart');void snailApp.local('accept');void snailApp.local('dismiss')`);await evaluate('releaseMenuSave()');await settled();
  assert.equal(await evaluate('menuWriteCount'),1);assert.equal((await world()).runMarker,oldMarker+1);assert.equal((await local()).dialog,0);assert.equal((await local()).dialogPending,0);
  console.log('ok - real IndexedDB delays keep Resume/Restart locked; failures retain the plan and repeated confirmation creates one colony');
  await evaluate("dispatchEvent(new PageTransitionEvent('pagehide'))");
  await until(()=>evaluate('snailApp.renderer.resources.closed && snailApp.renderer.resources.textures===0'),'page exit did not drain GPU resources');
  console.log('ok - page exit closes the browser session and disposes GPU resources');
} finally {ws.close();await fetch(`${devtools}/json/close/${target.id}`);}
