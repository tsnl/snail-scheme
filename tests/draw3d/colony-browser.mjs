// Chromium input, WebGPU readback and durable reopen for either 3D package.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {MAP_WIDTH,colony, client, siteAt, colonyWords, clientWords, at, pixelAt, setWorker, withdrawReserves} from '../applications/colony-state.mjs';
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
const selection = async () => {const s=await local();return[s.chooser,s.targetX,s.targetY,s.choiceKind];};
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
async function doubleClick(position) {
  const events=[1,2].flatMap(clickCount=>['mousePressed','mouseReleased'].map(type=>({type,...position,button:'left',clickCount})));
  await Promise.all(events.map(event=>call('Input.dispatchMouseEvent',event)));await settled();
}
async function tileIsTappable(x,y) {
  const point=await pointCell(x,y);
  assert.equal(await evaluate(`document.elementFromPoint(${point.x},${point.y})===snailApp.canvas`),true,`the selected tile stays tappable: ${JSON.stringify(await evaluate(`({point:[${point.x},${point.y}],hit:document.elementFromPoint(${point.x},${point.y})?.closest('[data-ui-key]')?.dataset.uiKey})`))}`);return point;
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
// A unit-width green frame belongs to the building; a worker at the same
// cell has a narrower frame and may be flying above its roof.
async function buildingHealthHeight(site) {
  const heights=await evaluate(`(()=>{const heights=[];
    for(const batch of snailApp.runtime.view().scene.batches.filter(b=>b.key===30||b.key===31))
      for(const draw of batch.draws)if(draw.mesh.vertices.length>40&&draw.mesh.vertices[47]>draw.mesh.vertices[46])
        for(let index=draw.first;index<draw.first+draw.count;index++) {
          const m=batch.transforms.slice(index*12,index*12+12);
          if(Math.abs(m[3]-${site.x})<.0001&&Math.abs(m[7]+${site.y})<.0001
            &&Math.abs(Math.hypot(m[0],m[4],m[8])-1)<.0001)heights.push(m[11]);
        }
    return heights;})()`);
  assert.equal(heights.length,1,'the selected building has one green health frame');return heights[0];
}
async function frameCell(x,y) {
  const hub=(await world()).surveys.find(s=>s.radius===9);
  await command('inspect-attack',[hub.x+x-8,hub.y+y-22]);
  await until(async()=>!(await local()).homing,'frame selected test cell');
  const point=await pointCell(x,y);
  if(!await evaluate(`document.elementFromPoint(${point.x},${point.y})===snailApp.canvas`)) {
    const free=await evaluate(`[[.18,.65],[.82,.65],[.5,.82],[.18,.82],[.82,.82]].map(([x,y])=>({x:Math.round(innerWidth*x),y:Math.round(innerHeight*y)})).find(p=>document.elementFromPoint(p.x,p.y)===snailApp.canvas)`);
    assert.ok(free,'the fixture must choose an exposed world target');await command('drag',[Math.round(free.x-point.x),Math.round(free.y-point.y)]);
  }

}
async function capture(suffix='') {
  if(await has('dialog-backdrop')){await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:2,y:2});await displayFrame();}
  const layout=await evaluate(`(()=>{
    const controls=[...document.querySelectorAll('[data-ui] button:not([data-ui-key="dialog-backdrop"]):not([data-ui-key^="attack-inspect-"]),[data-ui] .snail-ui-kind-6')];
    const invalid=controls.map(node=>{const r=node.getBoundingClientRect();return{key:node.dataset.uiKey,x:r.x,y:r.y,width:r.width,height:r.height,right:r.right,bottom:r.bottom}})
      .filter(r=>{const menu=['resume','restart-menu','resign-menu','dismiss-restart','accept-restart','dismiss-resign','accept-resign'].includes(r.key);
        return r.x<0||r.y<0||r.right>innerWidth+.5||r.bottom>innerHeight+.5||r.width!==(['right-handed','left-handed','restart-menu','resign-menu'].includes(r.key)?100:menu?208:56)||r.height!==(menu||['right-handed','left-handed'].includes(r.key)?48:56)});
    const clipped=[...document.querySelectorAll('.snail-ui-button-label,[data-ui-key$="-caption"],[data-ui-key$="-readout-label"],[data-ui-key="context-description"],[data-ui-key="onboarding-help"],[data-ui-key="frontier-hint"]')]
      .filter(node=>node.scrollWidth>node.clientWidth+1||node.scrollHeight>node.clientHeight+1).map(node=>({key:node.closest('[data-ui-key]').dataset.uiKey,text:node.textContent,width:node.clientWidth,scrollWidth:node.scrollWidth,height:node.clientHeight,scrollHeight:node.scrollHeight,font:getComputedStyle(node).fontSize,padding:getComputedStyle(node.parentElement).padding}));
    const overlap=(a,b)=>a.left<b.right&&b.left<a.right&&a.top<b.bottom&&b.top<a.bottom;
    const boxes=[...document.querySelectorAll('[data-ui-key^="attack-toast-"]')].map(node=>({key:node.dataset.uiKey,rect:node.getBoundingClientRect()}));
    const obstacles=[...document.querySelectorAll('[data-ui] button:not([data-ui-key^="attack-inspect-"]):not([data-ui-key="dialog-backdrop"]),[data-ui] .snail-ui-kind-6,[data-ui-key="context"],[data-ui-key="result"],[data-ui-key="onboarding"]')];
    const covered=boxes.flatMap(box=>obstacles.filter(node=>!node.closest('[data-ui-key^="attack-toast-"]')&&overlap(box.rect,node.getBoundingClientRect())).map(node=>({toast:box.key,control:node.dataset.uiKey})));
    const insetSizes=(snailApp.runtime.view().scene.insets??[]).map(inset=>inset.rect.slice(2));
    const dimAlerts=[...document.querySelectorAll('[data-ui-key^="attack-label-"]')].filter(node=>getComputedStyle(node).color!=='rgb(255, 255, 255)').map(node=>node.dataset.uiKey);
    const hint=document.querySelector('[data-ui-key="onboarding"]');
    const anchored=!hint?null:(()=>{const h=hint.getBoundingClientRect(),rail=document.querySelector('[data-ui-key="rail"]').getBoundingClientRect();
      return{arrow:Number(hint.dataset.arrow),clear:!overlap(h,rail),inside:h.left>=0&&h.right<=innerWidth&&h.top>=0&&h.bottom<=innerHeight};})();
    const shade=document.querySelector('[data-ui-key="dialog-backdrop"]'),backdrop=!shade?null:(()=>{const r=shade.getBoundingClientRect(),color=getComputedStyle(shade).backgroundColor;
      return{rect:[r.x,r.y,r.width,r.height],alpha:color.startsWith('rgba(')?parseFloat(color.split(',').at(-1)):1};})();
    const dialog=document.querySelector('[data-ui-key="pause-dialog"],[data-ui-key="restart-dialog"],[data-ui-key="resign-dialog"]');
    const blocked=![...document.querySelectorAll('[data-ui-key="pause-dialog"] button:enabled,[data-ui-key="restart-dialog"] button:enabled,[data-ui-key="resign-dialog"] button:enabled,[data-ui-key="context"] button:enabled,[data-ui-key="result"] button:enabled')]
      .every(button=>{const r=button.getBoundingClientRect();return button.contains(document.elementFromPoint(r.x+r.width/2,r.y+r.height/2));});
    const error=document.querySelector('.connection[data-state="error"]');
    const errorCoversMenu=!!(dialog&&error&&overlap(dialog.getBoundingClientRect(),error.getBoundingClientRect()));
    return{invalid,clipped,covered,dimAlerts,insetSizes,anchored,backdrop,blocked,errorCoversMenu,scrollWidth:document.documentElement.scrollWidth,width:document.documentElement.clientWidth};})()`);
  assert.deepEqual(layout.invalid,[],'circles and labeled menu rows keep their touch size and stay on screen');
  assert.equal(layout.blocked,false,'enabled menu actions remain reachable above shell overlays');
  assert.equal(layout.errorCoversMenu,false,'save errors remain outside the menu');
  if(layout.backdrop){assert.ok(layout.backdrop.alpha>0&&layout.backdrop.alpha<1,'hovering the backdrop keeps the world visible');const expected=await evaluate('[0,0,innerWidth,innerHeight]');assert.ok(layout.backdrop.rect.every((value,index)=>Math.abs(value-expected[index])<=1),'the dim backdrop covers the viewport within CSS subpixel rounding');}
  if(layout.anchored)assert.ok(layout.anchored.arrow>0&&layout.anchored.clear&&layout.anchored.inside,'guidance points toward the deposit and leaves the rail clear');
  assert.deepEqual(layout.clipped,[],'visible hotkeys, costs and readout labels fit');
  assert.deepEqual(layout.dimAlerts,[],'attack labels retain white-on-red contrast');
  assert.deepEqual(layout.covered,[],'attack notifications do not cover controls or selected panels');
  assert.deepEqual(layout.insetSizes,[],'attack notifications allocate no scene thumbnails');
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
async function checkResolution(width,height,dpr) {
  const {ratio,...actual}=await evaluate(`(()=>{const canvas=snailApp.canvas,ui=document.querySelector('[data-ui]'),label=document.querySelector('.snail-ui-button-label');
    const box=canvas.getBoundingClientRect();return{ratio:devicePixelRatio,backing:[canvas.width,canvas.height],logical:snailApp.viewport,
      input:[snailApp.inputSettings.width,snailApp.inputSettings.height],css:[box.width,box.height],
      canvasFilter:getComputedStyle(canvas).imageRendering,uiFilter:getComputedStyle(ui).imageRendering,
      uiTransform:getComputedStyle(ui).transform,labelSize:getComputedStyle(label).fontSize};})()`);
  actual.css=actual.css.map(Math.floor); // The host preserves its existing integer CSS viewport contract.
  assert.ok(Math.abs(ratio-dpr)<.000001,'emulation reports the requested DPR within its floating-point precision');
  assert.deepEqual(actual,{backing:[Math.round(width*ratio),Math.round(height*ratio)],logical:[width,height],
    input:[width,height],css:[width,height],canvasFilter:'auto',uiFilter:'auto',uiTransform:'none',labelSize:'11px'});
  const shot=Buffer.from((await call('Page.captureScreenshot',{format:'png'})).data,'base64');
  assert.deepEqual([shot.readUInt32BE(16),shot.readUInt32BE(20)],[width*dpr,height*dpr],'DOM composition retains native HiDPI pixels');
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
function depositFixture(original,remaining) {
  const value=structuredClone(original),deposit=value.deposits[0],removed=deposit.remaining-remaining;
  deposit.remaining=remaining;value.produced+=removed;value.lostOre+=removed;value.started=true;
  value.surveys.push({x:deposit.cell%MAP_WIDTH,y:Math.floor(deposit.cell/MAP_WIDTH),radius:4});return value;
}
async function checkUnitBars() {
  const original=await world(),camera=await local(),cell=original.deposits[0].cell;
  const centered={...camera,cameraX:(cell%MAP_WIDTH)*1000,cameraY:Math.floor(cell/MAP_WIDTH)*1000,homing:false};
  try {
    for(const [width,height] of [[1100,760],[390,844]])for(const remaining of [600,60,0]) {
      await resize(width,height);const value=depositFixture(original,remaining);value.hull=150;value.bots[0].hp=7;
      await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(value))})`);
      await evaluate(`snailApp.runtime.restore(2,${JSON.stringify(clientWords(centered))})`);await command('viewport',[width,height]);
      const result=await evaluate(`(()=>{const scene=snailApp.runtime.view().scene,bars=scene.batches.filter(b=>b.key===30||b.key===31),body=scene.batches.find(b=>b.key===3);
        return{labels:document.querySelectorAll('[data-ui-key^="deposit-ore-"]').length,opaque:bars.every(b=>b.opacity===1&&!b.pulse),
          unlit:bars.every(b=>b.draws.every(d=>d.mesh.vertices.every((v,i)=>i%10!==9||v===1))),
          instanced:bars.every(b=>b.unordered&&b.draws.length<=4),sharedClock:bars.every(b=>b.motionClock===body.motionClock),lost:snailApp.renderer.resources.lost};})()`);
      assert.deepEqual(result,{labels:0,opaque:true,unlit:true,instanced:true,sharedClock:true,lost:false});
      await capture(`-bars-${width}x${height}-${remaining}`);
    }
    await click('pause');const frozen=await evaluate('snailApp.runtime.snapshot(1)');
    await evaluate('globalThis.fixtureBarBody=snailApp.runtime.view().scene.batches.find(b=>b.key===3)');
    const pausedCamera=await local();await evaluate(`snailApp.runtime.restore(2,${JSON.stringify(clientWords({...pausedCamera,heading:90000,turnFrom:90000,turnTo:90000,turnElapsed:300,scale:750}))})`);
    await settled();await displayFrame();
    assert.equal(await evaluate('snailApp.runtime.view().scene.batches.find(b=>b.key===3)===fixtureBarBody'),true);
    assert.equal(await evaluate('snailApp.runtime.view().scene.batches.filter(b=>b.key===30||b.key===31).every(b=>b.motionClock===fixtureBarBody.motionClock)'),true);
    await pause(150);await displayFrame();assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),frozen);
    console.log('ok - desktop/portrait health and reserve bars stay opaque and quiet, use shared instancing and preserve paused motion through camera changes');
  } finally {
    await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(original))})`);
    await evaluate(`snailApp.runtime.restore(2,${JSON.stringify(clientWords(camera))})`);await command('viewport',[1100,760]);
    await evaluate('delete globalThis.fixtureBarBody');
  }
}

try {
  await call('Runtime.enable');await call('Network.enable');await call('Network.setCacheDisabled',{cacheDisabled:true});
  await call('Page.navigate',{url:origin});await call('Page.bringToFront');await until(()=>evaluate('!!globalThis.snailApp'),'3D startup');
  assert.deepEqual(await evaluate(`({recording:!!snailApp.recording,capture:!!snailApp.runtime.recording,
    controls:!!document.querySelector('.snail-recording'),loaded:performance.getEntriesByType('resource').some(r=>r.name.includes('/recording.')||r.name.includes('/playback.'))})`),
    {recording:false,capture:false,controls:false,loaded:false},'recording remains disabled without loading its UI or history code');
  await resize(1100,760);if(await has('pause-dialog'))await command('resume');
  await command('restart-seed',[1]);await evaluate('snailApp.session.stopClock()');await command('center');
  for(const dpr of [1,2,3]){await resize(1101,761,dpr);await checkResolution(1101,761,dpr);}
  await resize(1100,760);
  const replacement=await evaluate(`(async()=>{const app=snailApp,manifest=app.manifest,renderer=app.renderer;
    clearTimeout(app.session.reloading);const state=()=>JSON.stringify([app.runtime.snapshot(1),app.runtime.snapshot(2)]),before=state();
    const next={...manifest,generation:manifest.generation+'-replacement',settings:{...manifest.settings,width:640,height:480}};
    try{app.session.checkManifest(next);await app.prepareGeneration(next,++app.reloadTicket);
      const native=[app.canvas.width,app.canvas.height],filter=app.canvas.style.imageRendering;
      let rejected=false;try{await app.prepareGeneration({...next,generation:'invalid-settings',settings:{...next.settings,width:0}},++app.reloadTicket);}catch{rejected=true;}
      const retained=app.generation===next.generation&&app.inputSettings.width===1100;
      await app.prepareGeneration(manifest,++app.reloadTicket);
      return{native,filter,rejected,retained,sameState:state()===before,sameRenderer:renderer===app.renderer,
        restored:[app.canvas.width,app.canvas.height],restoredFilter:app.canvas.style.imageRendering};
    }finally{await app.session.reload();}})()`);
  assert.deepEqual(replacement,{native:[1100,760],filter:'',rejected:true,retained:true,sameState:true,sameRenderer:true,
    restored:[1100,760],restoredFilter:''});
  console.log('ok - native HiDPI world and DOM keep logical input at odd sizes through DPR-only changes and accepted/rejected hot replacement');
  assert.equal((await world()).buildings.length,0);assert.equal(await has('context'),false);
  assert.equal(await evaluate('!!snailApp.manifest.settings.controller || !!snailApp.manifest.settings.controllerAxes'),false);
  assert.equal(await evaluate('snailApp.manifest.settings.rotationHandler??null'),null);
  assert.ok(await has('rotate-left')&&await has('rotate-right'),'rotation buttons are immediately available');
  await evaluate('snailApp.session.stopClock()');
  await checkUnitBars();
  const freshHint=await world(),hintHub=freshHint.surveys.find(s=>s.radius===9),hintAlerts=structuredClone(freshHint);
  hintAlerts.alerts=[0,1,4].map((kind,index)=>({x:hintHub.x+index*2,y:hintHub.y,kind,tick:hintAlerts.tick}));
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(hintAlerts))})`);await settled();
  for(const [width,height]of[[320,568],[390,844],[568,320],[640,360],[1100,760]]) {
    await resize(width,height);assert.ok(await has('onboarding'));await capture(`-hint-${width}x${height}`);
    const beforeReadout=await evaluate('snailApp.runtime.snapshot(1)');
    const readout=await evaluate(`(()=>{const n=document.querySelector('[data-ui-key="ore"]'),r=n.getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);
    assert.equal(await evaluate(`document.elementFromPoint(${readout.x},${readout.y})===snailApp.canvas`),false);await doubleClick(readout);
    assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),beforeReadout,'readout taps cannot construct on the map underneath');
    const hintPoint=await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="onboarding"]').getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);
    assert.equal(await evaluate(`document.elementFromPoint(${hintPoint.x},${hintPoint.y})===snailApp.canvas`),false);await doubleClick(hintPoint);
    assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),beforeReadout,'the painted hint consumes taps without a hidden order');
    await click('pause');await capture(`-pause-${width}x${height}`);
    assert.equal(await evaluate(`document.querySelector('[data-ui-key="right-handed"]').getAttribute('aria-pressed')`),'true');
    await click('right-handed');assert.equal((await local()).leftHanded,false);
    await click('left-handed');assert.equal((await local()).leftHanded,true);
    assert.equal(await evaluate(`document.querySelector('[data-ui-key="left-handed"]').getAttribute('aria-pressed')`),'true');
    await click('left-handed');assert.equal((await local()).leftHanded,true);await click('resume');
    await capture(`-hint-${width}x${height}-left`);
    assert.equal(await evaluate(`(()=>{const q=document.querySelector('[data-ui-key="rotate-left"]').getBoundingClientRect(),e=document.querySelector('[data-ui-key="rotate-right"]').getBoundingClientRect();return q.left<e.left&&Math.abs(q.top-e.top)<1})()`),true);
    await click('pause');await click((await local()).leftHanded?'right-handed':'left-handed');await click('resume');
  }
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(freshHint))})`);await settled();
  const resources=await evaluate('globalThis.retainedScene=snailApp.runtime.view().scene;snailApp.renderer.resources');
  assert.ok(resources.instancedDraws>0&&resources.instances>resources.meshes,'product occurrences share GPU model buffers');
  await command('drift',[1,0]);const cameraResources=await evaluate('snailApp.renderer.resources');
  assert.ok(cameraResources.uploads-resources.uploads<=2,'camera changes upload at most the two billboard batches');
  assert.equal(cameraResources.meshUploads,resources.meshUploads);
  assert.equal(await evaluate('[0,3,10].every(key=>snailApp.runtime.view().scene.batches.find(b=>b.key===key)===retainedScene.batches.find(b=>b.key===key))'),true);
  const repeated=structuredClone(freshHint);repeated.started=true;repeated.surveys.unshift({...repeated.surveys[0]});
  for(const x of [10,11,12]) {
    const point=at(repeated,x,22),aim=pixelAt(repeated,x,22);
    repeated.buildings.push({id:repeated.nextId++,kind:3,...point,level:1,hp:90,stock:0,stage:2,
      cooldown:0,aimX:aim.x,aimY:aim.y,armed:0,source:0,moveX:-1,moveY:-1});
    repeated.surveys.push({...point,radius:7});repeated.spent+=25;repeated.ore-=25;
  }
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(repeated))})`);await settled();
  await complete(1);
  const instanced=await evaluate(`(async()=>{const renderer=snailApp.renderer,device=renderer.device,calls=[],original=device.createCommandEncoder;
    device.createCommandEncoder=function(...args){const encoder=original.apply(this,args),begin=encoder.beginRenderPass.bind(encoder);
      encoder.beginRenderPass=(...args)=>{const pass=begin(...args),draw=pass.drawIndexed.bind(pass);
        pass.drawIndexed=(...args)=>{calls.push(args.slice(0,2));return draw(...args);};return pass;};return encoder;};
    try{await renderer.readPixels(snailApp.runtime.view().scene);return{calls,resources:renderer.resources};}
    finally{device.createCommandEncoder=original;}})()`);
  assert.ok(instanced.calls.some(([indices,count])=>indices>108&&count===3),'three towers share one indexed GPU draw');
  assert.ok(instanced.calls.some(([indices,count])=>indices===108&&count===3),'three worker bodies share one indexed GPU draw');
  assert.ok(instanced.calls.some(([indices,count])=>indices===6&&count>20),'terrain tiles use repeated fixed-mesh instances');
  await complete(1);const tickResources=await evaluate('snailApp.renderer.resources');
  assert.equal(tickResources.meshUploads,instanced.resources.meshUploads);assert.ok(tickResources.uploads>instanced.resources.uploads);
  console.log('ok - product tile, tower and worker draws share fixed GPU meshes; a new tick uploads only occurrences',
    {draws:instanced.calls,meshes:instanced.resources.meshes,instances:instanced.resources.instances});
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(freshHint))})`);await settled();
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

  await call('Emulation.setTouchEmulationEnabled',{enabled:true,maxTouchPoints:2});
  for(const [width,height]of[[320,568],[568,320]]) {
    await resize(width,height);await command('home');await until(async()=>!(await local()).homing,'opening hub');
    for(const control of ['worker','upgrade','repair']) {
      assert.equal(await evaluate(`document.querySelector('[data-ui-key="${control}"]').disabled`),true);
      await touchControl(control);
    }
    for(const [pressed,code]of[['f','KeyF'],['u','KeyU'],['r','KeyR']])await key(pressed,code);
    assert.equal((await world()).ore,160);assert.equal((await world()).started,false);assert.equal((await world()).tick,0);
    await capture(`-opening-hub-${width}x${height}`);await key('Escape','Escape');await frameCell(12,22);await pointCell(12,22,true);
    for(const control of ['tower','artillery'])assert.equal(await evaluate(`document.querySelector('[data-ui-key="${control}"]').disabled`),true);
    await key('1','Digit1');assert.equal((await local()).failure,38);assert.equal((await world()).ore,160);
    await capture(`-opening-build-${width}x${height}`);await key('Escape','Escape');
  }
  await call('Emulation.setTouchEmulationEnabled',{enabled:false});await resize(1100,760);
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(freshHint))})`);await settled();await command('center');
  console.log('ok - mobile opening disables non-extractor purchases and keyboard actions preserve all starting ore and frozen time');

  const unbuilt=await evaluate('snailApp.runtime.snapshot(1)');await pointCell(12,20,true);
  assert.ok(await has('extractor'));assert.equal(await has('tower'),false);assert.ok(await has('close-context'));await capture('-deposit');
  await click('close-context');assert.equal(await has('context'),false);assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),unbuilt);await pointCell(12,20,true);
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),unbuilt,'the first tap only selects the deposit');
  const selected=await selection();await click('pause');assert.equal((await world()).paused,1);await capture('-pause-selection');
  const stopped=await evaluate('snailApp.runtime.snapshot(1)'),covered=await evaluate('snailApp.runtime.snapshot(2)');
  for(const binding of ['center','confirm'])await command(binding);
  await command('restart-seed',[42]);await key('f','KeyF');await key('e','KeyE');await key('3','Digit3');
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),stopped);assert.deepEqual(await evaluate('snailApp.runtime.snapshot(2)'),covered);
  await holdNextSave();await evaluate(`document.querySelector('[data-ui-key="resume"]').click()`);
  await until(()=>evaluate('!!globalThis.releaseMenuSave'),'delayed Resume save');assert.equal((await local()).dialogPending,2);assert.equal((await world()).paused,1);
  await until(()=>evaluate(`document.querySelector('[data-ui-key="resume"]').textContent.includes('Resuming')`),'pending Resume label did not render');
  assert.equal(await evaluate(`['right-handed','left-handed'].every(k=>document.querySelector('[data-ui-key="'+k+'"]').disabled)`),true);
  await evaluate(`void snailApp.local('handedness',[1]);void snailApp.local('restart');void snailApp.local('resume')`);await evaluate('releaseMenuSave()');await settled();
  assert.equal(await evaluate('menuWriteCount'),1);assert.equal((await world()).paused,0);assert.equal((await local()).dialog,0);assert.deepEqual(await selection(),selected);
  await click('pause');await failNextSave();await click('resume');assert.equal((await world()).paused,1);assert.equal((await local()).dialog,1);assert.deepEqual(await selection(),selected);
  await resize(568,320);await capture('-failed-resume-568x320');await click((await local()).leftHanded?'right-handed':'left-handed');await capture('-failed-resume-568x320-left');
  await click((await local()).leftHanded?'right-handed':'left-handed');await resize(1100,760);
  await click('resume');await click('pause');
  await click('restart-menu');await capture('-restart-selection');await command('restart-seed',[42]);await command('resume');
  assert.ok(await has('restart-dialog'));const beforeFailedReset=await evaluate('snailApp.runtime.snapshot(1)');
  await failNextSave();await click('accept-restart');assert.ok(await has('restart-dialog'));assert.equal((await local()).dialogPending,0);
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),beforeFailedReset);assert.deepEqual(await selection(),selected);
  await resize(568,320);await capture('-failed-restart-568x320');await click('dismiss-restart');await click((await local()).leftHanded?'right-handed':'left-handed');await click('restart-menu');
  await capture('-failed-restart-568x320-left');await click('dismiss-restart');await click((await local()).leftHanded?'right-handed':'left-handed');await click('restart-menu');await resize(1100,760);
  await key('Escape','Escape');assert.ok(await has('pause-dialog'));assert.equal((await world()).paused,1);
  await press({x:20,y:20});assert.equal((await world()).paused,0);assert.deepEqual(await selection(),selected);
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),unbuilt);await evaluate('snailApp.session.stopClock()');
  await tileIsTappable(12,20);await pointCell(12,20,true);await click('extractor');
  assert.equal(siteAt(await world(),12,20)?.kind,1);assert.equal((await local()).buildKind,0);assert.equal((await local()).chooser,false);
  await complete();assert.equal(siteAt(await world(),12,20)?.stage,2);
  await pointCell(12,20,true,.7);assert.equal(await has('upgrade'),true);await click('upgrade');assert.equal(siteAt(await world(),12,20)?.level,2);
  const inspected=await evaluate('snailApp.runtime.snapshot(1)');await click('close-context');assert.equal(await has('context'),false);assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),inspected);
  console.log('ok - deposit selection exposes only its extractor; an explicit extractor action builds once; explicit upgrades stay separate');

  const buildingFunds=await world();buildingFunds.ore+=100;withdrawReserves(buildingFunds,100);buildingFunds.delivered+=100;
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(buildingFunds))})`);await settled();
  await frameCell(13,21);await pointCell(13,21,true);const beforeOrder=(await world()).spent;
  assert.ok(await has('tower')&&await has('artillery')&&!(await has('house')));assert.equal(await has('extractor'),false);assert.ok(await has('close-context'));await capture('-construction');
  await click('close-context');assert.equal(await has('context'),false);await pointCell(13,21,true);assert.equal((await world()).spent,beforeOrder);
  const neutralPreview=await evaluate('JSON.stringify(snailApp.runtime.view().scene.batches.find(batch=>batch.key===5))');
  for(const [key,kind]of[['tower',3],['artillery',2]]){
    const hover=await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="${key}"]').getBoundingClientRect();return{x:r.x+r.width/2,y:r.y+r.height/2}})()`);
    await call('Input.dispatchMouseEvent',{type:'mouseMoved',...hover});await settled();assert.equal((await local()).preview,kind);
    assert.notEqual(await evaluate('JSON.stringify(snailApp.runtime.view().scene.batches.find(batch=>batch.key===5))'),neutralPreview);
    assert.equal((await world()).spent,beforeOrder);
  }
  await pointCell(13,21);assert.equal((await local()).preview,0);
  assert.equal(await evaluate('JSON.stringify(snailApp.runtime.view().scene.batches.find(batch=>batch.key===5))'),neutralPreview);

  await holdNextSave();await evaluate(`document.querySelector('[data-ui-key="tower"]').click()`);await until(()=>evaluate('!!globalThis.releaseMenuSave'),'delayed construction save');
  assert.equal((await local()).buildKind,3);assert.equal((await world()).spent,beforeOrder);
  await evaluate(`void snailApp.local('confirm');void snailApp.local('choose',[1])`);await evaluate('releaseMenuSave()');await settled();
  assert.equal(await evaluate('menuWriteCount'),1);assert.equal((await world()).spent,beforeOrder+25);assert.equal((await local()).lastKind,3);
  const fastSite=await pointCell(14,21);await doubleClick(fastSite);assert.equal(siteAt(await world(),14,21),undefined);assert.equal((await local()).choiceKind,0);await click('tower');assert.equal(siteAt(await world(),14,21)?.kind,3);assert.equal((await world()).spent,beforeOrder+50);
  await doubleClick(fastSite);assert.equal((await world()).spent,beforeOrder+50);assert.ok(await has('cancel-build'),'doubleclick tail inspects the ordered site');
  await key('Escape','Escape');await pointCell(15,21,true);const free=(await world()).spent;
  await pointCell(15,22,true);assert.equal((await world()).spent,free,'a different tile retargets without charging');
  await failNextSave();await click('artillery');assert.equal((await world()).spent,free);assert.equal((await local()).choiceKind,2);assert.equal((await local()).lastKind,3);
  for(const left of [false,true]) {
    await resize(568,320);if(left){await click('pause');await click((await local()).leftHanded?'right-handed':'left-handed');await click('resume');}
    await frameCell(15,22);await pointCell(15,22,true);await capture(`-failed-construction-568x320${left?'-left':''}`);await tileIsTappable(15,22);
  }
  await click('pause');await click((await local()).leftHanded?'right-handed':'left-handed');await click('resume');await resize(1100,760);await frameCell(15,22);await pointCell(15,22,true);
  // Re-selecting is neutral; an explicit retry names the failed gun.
  await click('artillery');assert.equal(siteAt(await world(),15,22)?.kind,2);assert.equal((await local()).lastKind,3);
  await key('Escape','Escape');
  const supplied=await world(),extra=200-supplied.ore;supplied.ore+=extra;supplied.delivered+=extra;withdrawReserves(supplied,extra);
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(supplied))})`);await settled();const hireBank=(await world()).ore;
  assert.equal(await has('worker-menu'),false);assert.equal(await has('worker-panel'),false);await key('f','KeyF');assert.equal((await world()).ore,hireBank);
  await key('h','KeyH');await until(async()=>!(await local()).homing,'home selects hub');assert.equal(await has('repair'),true);assert.equal(await has('worker'),true);assert.equal(await has('close-context'),true);assert.equal(await has('upgrade'),true);await capture('-hub');
  await click('worker');assert.equal((await world()).ore,hireBank-25);await key('f','KeyF');assert.equal((await world()).ore,hireBank-50);assert.equal((await local()).chooser,true);
  await key('Escape','Escape');await key('e','KeyE');await until(async()=>(await local()).turnElapsed===300,'keyboard rotation');
  await frameCell(12,20);await pointCell(12,20,true,.7);assert.match(await evaluate('document.querySelector("[data-ui-key=context-title]").textContent'),/extractor/i);
  await key('q','KeyQ');await until(async()=>(await local()).turnElapsed===300,'return rotation');await key('Escape','Escape');
  const ignored=await evaluate('({world:snailApp.runtime.snapshot(1),client:snailApp.runtime.snapshot(2)})');
  await evaluate(`(()=>{const pad={index:0,id:'ignored gamepad',connected:true,axes:[.8,-.8],buttons:Array.from({length:16},()=>({pressed:true}))};
    Object.defineProperty(navigator,'getGamepads',{configurable:true,value:()=>[pad]});snailApp.input.pollController(performance.now(),0);delete navigator.getGamepads;})()`);
  await settled();assert.deepEqual(await evaluate('({world:snailApp.runtime.snapshot(1),client:snailApp.runtime.snapshot(2)})'),ignored);
  console.log('ok - rapid doubleclick builds one remembered structure; retargeting is free; delayed and failed writes preserve intent; hires remain explicit');

  const beforeFeedback=await world(),beforeFeedbackClient=await local(),unreachable=structuredClone(freshHint);
  unreachable.started=true;unreachable.surveys.unshift({...at(unreachable,12,8),radius:4});setWorker(unreachable,0,{x:12,y:12});
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(unreachable))})`);await settled();await command('center');
  for(const [width,height,left]of[[1100,760,false],[320,568,false],[568,320,false],[568,320,true]]) {
    await resize(width,height);if((await local()).leftHanded!==left){await click('pause');await click((await local()).leftHanded?'right-handed':'left-handed');await click('resume');}
    await frameCell(12,11);await pointCell(12,11,true);await click('tower');assert.equal((await local()).failure,32);assert.equal((await world()).ore,160);
    assert.match(await evaluate('document.querySelector("[data-ui-key=context-description]").textContent'),/No worker route through surveyed ground/);
    await capture(`-route-rejection-${width}x${height}-${left?'left':'right'}`);await key('Escape','Escape');
  }
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(beforeFeedback))})`);
  await evaluate(`snailApp.runtime.restore(2,${JSON.stringify(clientWords(beforeFeedbackClient))})`);await resize(1100,760);await command('viewport',[1100,760]);await settled();
  console.log('ok - actual construction route failures remain visible, unclipped and actionable at desktop and small mobile sizes');

  await complete();assert.equal(siteAt(await world(),15,22)?.stage,2);await frameCell(15,22);
  const upgradeSite=siteAt(await world(),15,22),healthHeight=await buildingHealthHeight(upgradeSite);
  // The health frame is .42 above the same model top used by picking. Select
  // halfway up that compact body, then prove the order addresses this site.
  const pickHeight=(healthHeight-.42)/2;await pointCell(15,22,true,pickHeight);
  assert.deepEqual([(await local()).targetX,(await local()).targetY],[upgradeSite.x,upgradeSite.y]);await click('upgrade');
  const upgrading=siteAt(await world(),15,22),spinner=`upgrade-wait-${upgrading.id}`;assert.equal(await has(spinner),true);
  const marker=()=>evaluate(`(()=>{const n=document.querySelector('[data-ui-key="${spinner}"]'),r=n.getBoundingClientRect(),s=getComputedStyle(n);return{x:r.x+r.width/2,y:r.y+r.height/2,width:parseFloat(s.width),height:parseFloat(s.height),pointer:s.pointerEvents,animation:s.animationName}})()`);
  // The upgrade marker is .35 above that top, .07 below the green frame.
  const firstMarker=await marker(),top=await pointCell(15,22,false,healthHeight-.07);assert.ok(Math.abs(firstMarker.x-top.x)<=1&&Math.abs(firstMarker.y-top.y)<=1);
  assert.deepEqual([firstMarker.width,firstMarker.height,firstMarker.pointer,firstMarker.animation],[24,24,'none','upgrade-wait-spin']);
  const waiting=await evaluate('snailApp.runtime.snapshot(1)');await command('drag',[18,12]);const movedMarker=await marker();
  assert.ok(Math.abs(movedMarker.x-firstMarker.x-18)<=1&&Math.abs(movedMarker.y-firstMarker.y-12)<=1);assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),waiting);
  await capture('-upgrade-spinner');await click('cancel-build');assert.equal(await has(spinner),false);
  await pointCell(15,22,true,pickHeight);assert.deepEqual([(await local()).targetX,(await local()).targetY],[upgradeSite.x,upgradeSite.y]);
  await click('upgrade');assert.equal(await has(spinner),true);
  await complete();assert.equal(siteAt(await world(),15,22).level,2);assert.equal(await has(spinner),false);await key('Escape','Escape');
  console.log('ok - CSS upgrade indicators track the building top, ignore pointer input and disappear on cancellation or completion');

  const pixels=await evaluate(`(async()=>{const frame=snailApp.runtime.view(),p=await snailApp.renderer.readPixels(frame.scene);return{
    vertices:frame.scene.batches.reduce((n,b)=>n+b.draws.reduce((n,d)=>n+d.count*d.mesh.vertices.length/10,0),0),bytes:p.bytes.length,colors:new Set(Array.from(p.bytes).filter((_,i)=>i%4!==3)).size};})()`);
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
    await key('Escape','Escape');assert.ok(await evaluate(`document.querySelectorAll('[data-ui-key^="attack-toast-"]').length>0`),'alerts remain available when the selected panel is closed');
    const heading=(await local()).heading,turnWorld=await evaluate('snailApp.runtime.snapshot(1)');
    await touchControl('rotate-right');await until(async()=>(await local()).turnElapsed===300,'touch clockwise turn');
    assert.equal((await local()).heading,(heading+90000)%360000);
    await touchControl('rotate-left');await until(async()=>(await local()).turnElapsed===300,'touch counterclockwise turn');
    assert.equal((await local()).heading,heading);assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),turnWorld);
    await checkResolution(width,height,dpr);
    await touchControl('pause');await capture(`-${width}x${height}-pause`);
    await touchControl((await local()).leftHanded?'right-handed':'left-handed');assert.equal((await local()).leftHanded,true);await touchControl('resume');await capture(`-${width}x${height}-left`);
    await touchControl('pause');await touchControl((await local()).leftHanded?'right-handed':'left-handed');await touchControl('resume');await key('Escape','Escape');
    await frameCell(15,21);const bank=(await world()).ore;await touchAt(await pointCell(15,21));
    assert.equal((await local()).chooser,true);assert.equal((await world()).ore,bank);await capture(`-${width}x${height}-construction`);await tileIsTappable(15,21);
    await touchControl('pause');await touchControl((await local()).leftHanded?'right-handed':'left-handed');await touchControl('resume');
    await frameCell(15,21);await touchAt(await pointCell(15,21));await capture(`-${width}x${height}-construction-left`);await tileIsTappable(15,21);
    await touchControl('pause');await touchControl((await local()).leftHanded?'right-handed':'left-handed');await touchControl('resume');await key('Escape','Escape');
  }
  const edgeWorld=await world();await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords({...edgeWorld,alerts:[]}))})`);await settled();
  for(const [width,height]of[[320,568],[568,320]])for(const left of [false,true]) {
    await resize(width,height);if((await local()).leftHanded!==left){await click('pause');await click((await local()).leftHanded?'right-handed':'left-handed');await click('resume');}
    for(const [px,py]of[[left?40:width-40,height<400?height-20:height-110],[width/2,height-168]]) {
      await frameCell(12,22);const before=await pointCell(12,22);await command('drag',[Math.round(px-before.x),Math.round(py-before.y)]);
      await pointCell(12,22,true);await capture(`-edge-${width}x${height}-${left?'left':'right'}-${px}`);const selectedPoint=await tileIsTappable(12,22);
      const arrow=await evaluate(`(()=>{const n=document.querySelector('[data-ui-key="context"]'),r=n.getBoundingClientRect();return{side:Number(n.dataset.arrow),x:r.x,right:r.right,y:r.y,bottom:r.bottom}})()`);
      if(selectedPoint.x<arrow.x)assert.equal(arrow.side,1);else if(selectedPoint.x>arrow.right)assert.equal(arrow.side,2);
      else assert.equal(arrow.side,selectedPoint.y<arrow.y?3:4);
    }
    await key('Escape','Escape');
  }
  if((await local()).leftHanded){await click('pause');await click((await local()).leftHanded?'right-handed':'left-handed');await click('resume');}
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(edgeWorld))})`);await settled();
  const firstAlert=(await world()).alerts[0],alertKey=(firstAlert.x+firstAlert.y*MAP_WIDTH)*8+firstAlert.kind;
  const beforeDismiss=await evaluate('snailApp.runtime.snapshot(1)');await touchControl(`attack-dismiss-${alertKey}`);
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),beforeDismiss);assert.equal(await has(`attack-toast-${alertKey}`),false);
  const repeat=await world();repeat.tick++;repeat.alerts=repeat.alerts.map(alert=>({...alert,tick:repeat.tick}));
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(repeat))})`);await settled();
  assert.equal(await has(`attack-toast-${alertKey}`),false,'ongoing fire stays dismissed');
  repeat.tick+=79;repeat.alerts=repeat.alerts.map(alert=>({...alert,tick:repeat.tick}));
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(repeat))})`);await settled();
  assert.equal(await has(`attack-toast-${alertKey}`),true,'later attack is visible again');
  const inspect=await evaluate(`(()=>{const r=document.querySelector('[data-ui-key="attack-inspect-${alertKey}"]').getBoundingClientRect();return{x:r.x+24,y:r.y+48}})()`);
  await touchAt(inspect);await until(async()=>!(await local()).homing,'toast label inspects attack');
  assert.deepEqual([(await local()).cameraX,(await local()).cameraY],[firstAlert.x*1000,firstAlert.y*1000]);
  await resize(390,844,3);await command('center');await frameCell(15,21);
  const beforeTouch=await world(),touchSnapshot=await evaluate('snailApp.runtime.snapshot(1)');assert.equal(siteAt(beforeTouch,15,21),undefined);
  await touchAt(await pointCell(15,21));assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),touchSnapshot);
  assert.equal((await local()).choiceKind,0,'an empty site starts with a neutral construction marker');
  await touchAt(await tileIsTappable(15,21));assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),touchSnapshot);await touchControl('tower');const orderedTouch=await world();assert.equal(siteAt(orderedTouch,15,21)?.kind,3);
  assert.equal(orderedTouch.spent,beforeTouch.spent+25);
  assert.equal(beforeTouch.ore-orderedTouch.ore+orderedTouch.localSpent-beforeTouch.localSpent,25,'bank and accessible local stock fund exactly one kit');
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
  const beforeHubTouch=await world(),beforeHubTouchClient=await local(),hubTouch=structuredClone(freshHint);hubTouch.started=true;
  for(const [width,height]of[[320,568],[568,320]]) {
    await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(hubTouch))})`);await settled();
    await resize(width,height);await command('home');await until(async()=>!(await local()).homing,'hub capacity touch');
    assert.match(await evaluate('document.querySelector("[data-ui-key=context-description]").textContent'),/12 → 14/);
    await touchControl('upgrade');assert.equal((await world()).ore,60);assert.equal((await world()).hubCapacityLevel,0);
    assert.equal(await evaluate('document.querySelector("[data-ui-key=upgrade]").disabled'),true);
    await touchControl('worker');await touchControl('worker');assert.equal((await world()).ore,10);assert.equal((await world()).bots.length,3);
    assert.equal((await local()).chooser,true);await capture(`-hub-upgrade-pending-${width}x${height}`);
    await complete(29);assert.equal((await world()).hubCapacityLevel,0);await complete(1);
    assert.equal((await world()).hubCapacityLevel,1);assert.equal((await world()).bots.length,5);
    assert.equal(await evaluate('document.querySelector("[data-ui-key=upgrade-caption]").textContent'),'200 ore');
    assert.equal(await evaluate('document.querySelector("[data-ui-key=upgrade]").disabled'),true);
    await capture(`-hub-upgrade-complete-${width}x${height}`);
  }
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(beforeHubTouch))})`);
  await evaluate(`snailApp.runtime.restore(2,${JSON.stringify(clientWords(beforeHubTouchClient))})`);await settled();
  console.log('ok - portrait and landscape touch keep hub expansion and repeated hires separate, paid, delayed and clearly priced');
  await call('Emulation.setTouchEmulationEnabled',{enabled:false});await resize(1100,760);await command('center');await capture();
  console.log('ok - centered Pause preserves selection; paused reopen, HiDPI HUD, explicit touch construction and mirrored popups fit 320–1100px');
  await click('pause');await click('restart-menu');const oldMarker=(await world()).runMarker;await holdNextSave();
  await evaluate(`document.querySelector('[data-ui-key="accept-restart"]').click()`);await until(()=>evaluate('!!globalThis.releaseMenuSave'),'delayed Restart save');
  assert.equal((await local()).dialogPending,3);assert.equal((await world()).runMarker,oldMarker);await until(()=>evaluate(`document.querySelector('[data-ui-key="accept-restart"]').textContent.includes('Restarting')`),'pending Restart label did not render');
  await evaluate(`void snailApp.local('accept-restart');void snailApp.local('accept');void snailApp.local('dismiss')`);await evaluate('releaseMenuSave()');await settled();
  assert.equal(await evaluate('menuWriteCount'),1);assert.equal((await world()).runMarker,oldMarker+1);assert.equal((await local()).dialog,0);assert.equal((await local()).dialogPending,0);
  console.log('ok - real IndexedDB delays keep Resume/Restart locked; failures retain the selection and repeated confirmation creates one colony');
  const finalColony=await world(),finalClient=await local(),finalHub=finalColony.surveys.find(value=>value.radius===9);
  for(const [width,height]of[[320,568],[568,320]]){
    await resize(width,height);await click('pause');await click('resign-menu');assert.ok(await has('resign-dialog'));
    await capture(`-resign-confirm-${width}x${height}`);await click('dismiss-resign');assert.equal((await world()).outcome,0);await click('resume');
  }
  await click('pause');await click('resign-menu');await holdNextSave();
  await evaluate(`document.querySelector('[data-ui-key="accept-resign"]').click()`);await until(()=>evaluate('!!globalThis.releaseMenuSave'),'delayed Resign save');
  assert.equal((await local()).dialogPending,4);await evaluate(`void snailApp.local('accept-resign');void snailApp.local('accept');void snailApp.local('dismiss')`);
  await evaluate('releaseMenuSave()');await settled();assert.equal(await evaluate('menuWriteCount'),1);assert.equal((await world()).outcome,4);assert.equal((await world()).hull,finalColony.hull);
  assert.equal((await local()).dialog,0);assert.match(await evaluate('document.querySelector("[data-ui-key=context-description]").textContent'),/resigned/);
  await capture('-resigned');const resigned=await evaluate('snailApp.runtime.snapshot(1)');await evaluate('globalThis.fixtureReload=true');await call('Page.reload');await until(()=>evaluate('!globalThis.fixtureReload && !!globalThis.snailApp'),'resigned durable reopen');await settled();assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),resigned);
  console.log('ok - Resign confirms on portrait and landscape, commits once, preserves the hub and survives reopen');

  for(const outcome of [1,3,4])for(const [width,height]of[[320,568],[568,320]])for(const leftHanded of [false,true]) {
    const ended={...finalColony,outcome,started:true,hull:outcome===1?0:300,nests:finalColony.nests.map(nest=>({...nest,hp:outcome===3?0:900})),
      alerts:[0,1,4].map((kind,index)=>({x:finalHub.x+index*2,y:finalHub.y,kind,tick:finalColony.tick}))};
    await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(ended))})`);
    await evaluate(`snailApp.runtime.restore(2,${JSON.stringify(clientWords({...finalClient,chooser:false,leftHanded}))})`);
    await resize(width,height);await command('viewport',[width,height]);assert.ok(await has('result'));await capture(`-outcome-${outcome}-${width}x${height}-${leftHanded?'left':'right'}`);
  }
  console.log('ok - victory and defeat keep Restart reachable and attack alerts outside the result card on both control sides');
  await evaluate("dispatchEvent(new PageTransitionEvent('pagehide'))");
  await until(()=>evaluate('snailApp.renderer.resources.closed && snailApp.renderer.resources.textures===0'),'page exit did not drain GPU resources');
  console.log('ok - page exit closes the browser session and disposes GPU resources');
} finally {ws.close();await fetch(`${devtools}/json/close/${target.id}`);}
