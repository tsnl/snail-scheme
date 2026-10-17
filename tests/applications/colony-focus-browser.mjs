// Real input, WebGPU pixels and durable reopen for either packaged owner.
// Use a fresh origin; this test intentionally creates a mine, tower and move.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {colony} from './colony-state.mjs';
const origin=process.argv[2], devtools=process.argv[3]??'http://127.0.0.1:9445';
const screenshot=process.argv[4];
const pause=ms=>new Promise(r=>setTimeout(r,ms));
async function until(fn,label,timeout=20000) {
  const deadline=Date.now()+timeout;
  while(Date.now()<deadline) { const value=await fn(); if(value)return value; await pause(100); }
  throw new Error(label);
}
const target=await(await fetch(`${devtools}/json/new?${encodeURIComponent(origin)}`,{method:'PUT'})).json();
const ws=new WebSocket(target.webSocketDebuggerUrl), pending=new Map(); let sequence=0;
await new Promise(r=>ws.addEventListener('open',r,{once:true}));
ws.onmessage=event=>{const data=JSON.parse(event.data);if(data.id){pending.get(data.id)?.(data);pending.delete(data.id);}};
function call(method,params={}) {return new Promise((resolve,reject)=>{const id=++sequence;
  const timer=setTimeout(()=>reject(new Error(`CDP timeout: ${method}`)),20000);
  pending.set(id,data=>{clearTimeout(timer);data.error?reject(new Error(data.error.message)):resolve(data.result);});
  ws.send(JSON.stringify({id,method,params}));});}
async function evaluate(expression) {
  const result=await call('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});
  if(result.exceptionDetails)throw new Error(result.exceptionDetails.exception?.description??result.exceptionDetails.text);
  return result.result.value;
}
const state=async()=>colony(await evaluate('snailApp.runtime.snapshot(1)'));
async function settled() {
  // Cloud removes the pending envelope before its accepted snapshot is restored.
  await until(()=>evaluate('!snailApp.localWork && !snailApp.session.sending && snailApp.pending.length===0'),
    'input was not committed and restored');
}
async function click(selector) {
  const box=await evaluate(`(()=>{const element=document.querySelector(${JSON.stringify(selector)});element.scrollIntoView({block:'center'});
    const b=element.getBoundingClientRect();return{x:b.x+b.width/2,y:b.y+b.height/2}})()`);
  await call('Input.dispatchMouseEvent',{type:'mousePressed',...box,button:'left',clickCount:1});
  await call('Input.dispatchMouseEvent',{type:'mouseReleased',...box,button:'left',clickCount:1}); await settled();
}
async function key(key,code) {await call('Input.dispatchKeyEvent',{type:'keyDown',key,code});await call('Input.dispatchKeyEvent',{type:'keyUp',key,code});await settled();}
async function point(x,y,press=false) {
  const box=await evaluate('(()=>{const canvas=document.querySelector("canvas");canvas.scrollIntoView({block:"center"});const r=canvas.getBoundingClientRect();return{x:r.x,y:r.y,w:r.width,h:r.height}})()');
  const position={x:box.x+x*box.w/960,y:box.y+y*box.h/640};
  await call('Input.dispatchMouseEvent',{type:'mouseMoved',...position});await settled();
  if(press){await call('Input.dispatchMouseEvent',{type:'mousePressed',...position,button:'left',clickCount:1});
    await call('Input.dispatchMouseEvent',{type:'mouseReleased',...position,button:'left',clickCount:1});await settled();}
}
try {
  await call('Page.bringToFront');await until(()=>evaluate('!!globalThis.snailApp'),'app startup');
  if(process.argv.includes('--restart')){await evaluate('snailApp.local("restart-seed",[1])');await settled();}
  assert.equal((await state()).focus,0);await click('.manual-controls summary');
  await click('[data-handler="choose"][data-args="[1]"]');await point(500,260,true);
  await until(async()=>(await state()).buildings.some(b=>b.kind===1&&b.stage===2),'extractor completion');
  await key('3','Digit3');await point(500,300,true);
  await until(async()=>(await state()).buildings.some(b=>b.kind===3&&b.stage===2),'tower completion');
  let world=await state();assert.equal(world.rails.length,1);
  const rail=world.rails[0];assert.equal(rail.path[0],12+21*48);assert.equal(rail.path.at(-1),8+22*48);
  await until(async()=>(await state()).rails.some(r=>r.cargo>0),'visible loaded rail shuttle',30000);
  const gpu=await evaluate(`(async()=>{const frame=snailApp.runtime.view(),pixels=await snailApp.renderer.readPixels(frame.quads,960,640);
    return{bytes:pixels.bytes.length,quads:frame.quads.length,colors:new Set(Array.from(pixels.bytes).filter((_,i)=>i%4!==3)).size};})()`);
  assert.ok(gpu.bytes>0&&gpu.quads>100&&gpu.colors>10);console.log('ok - pointer/key construction creates visible rails and real WebGPU pixels',gpu);
  await click('[data-handler="suspend"][data-args="[1]"]');const beforeMove=await state();assert.equal(beforeMove.paused,1);
  await point(500,300);await key('m','KeyM');await point(500,340,true);world=await state();
  assert.equal(world.ore,beforeMove.ore-5);assert.equal(world.buildings.find(b=>b.kind===3).moveY,22);
  const paused=await evaluate('snailApp.runtime.snapshot(1)');await call('Page.reload');
  await until(()=>evaluate('!!globalThis.snailApp'),'reopen');assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),paused);
  await click('[data-handler="suspend"][data-args="[0]"]');
  await until(async()=>(await state()).buildings.find(b=>b.kind===3).y===22,'queued move drains and completes',30000);
  await click('[data-handler="suspend"][data-args="[1]"]');
  await click('[data-handler="focus"][data-args="[1]"]');assert.equal((await state()).focus,1);
  await click('.manual-controls summary');assert.equal((await state()).focus,0);
  assert.doesNotMatch(await evaluate('document.body.textContent'),/Prioritize selected|Toggle auto repair/);
  if(screenshot){const shot=await call('Page.captureScreenshot',{format:'png',captureBeyondViewport:true});writeFileSync(screenshot,Buffer.from(shot.data,'base64'));}
  console.log('ok - real move input, pause, durable page reopen and Auto/Manual controls',origin);
} finally {ws.close();await fetch(`${devtools}/json/close/${target.id}`);}
