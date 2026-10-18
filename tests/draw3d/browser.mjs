import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
const origin = process.argv[2] ?? 'http://127.0.0.1:4197';
const devtools = process.argv[3] ?? 'http://127.0.0.1:9452';
const target = await (await fetch(`${devtools}/json/new?${encodeURIComponent(origin)}`, {method: 'PUT'})).json();
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
try {
  await call('Page.bringToFront');
  for (let i = 0; i < 200 && !await evaluate('!!globalThis.sceneFixture'); i++) await new Promise(resolve => setTimeout(resolve, 100));
  assert.ok(await evaluate('!!globalThis.sceneFixture'), 'scene fixture failed to start');
  const pixels = await evaluate(`(async () => { const {renderer,frame}=sceneFixture; const result=await renderer.readPixels(frame);
    return {colors: new Set(Array.from(result.bytes).filter((_,i)=>i%4!==3)).size, bytes:result.bytes.length,
      vertices:frame.batches.reduce((n,b)=>n+b.vertices.length/10,0),
      triangles:frame.batches.reduce((n,b)=>n+b.indices.length/3,0),errors:sceneErrors};})()`);
  assert.ok(pixels.colors > 30); assert.ok(pixels.bytes > 100000); assert.deepEqual(pixels.errors, []);
  console.log('ok - actual Chromium WebGPU scene pixels', pixels);
  if (process.argv[4]) { const shot = await call('Page.captureScreenshot', {format: 'png'}); writeFileSync(process.argv[4], Buffer.from(shot.data, 'base64')); }
  const depth = await evaluate(`(async()=>{const {renderer,frame}=sceneFixture;
    const vertices=[];for(const [z,color] of [[.2,[1,0,0]],[.8,[0,0,1]]])
      for(const [x,y] of [[-.8,-.8],[.8,-.8],[0,.8]])vertices.push(x,y,z,0,0,1,...color,1);
    const probe={batches:[{key:-1,vertices,indices:[0,1,2,3,4,5]}],background:[0,0,0],
      uniforms:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1,1,1,1]};
    const result=await renderer.readPixels(probe),canvas=document.querySelector('canvas');
    const at=Math.floor(canvas.height/2)*result.bytesPerRow+Math.floor(canvas.width/2)*4;
    const pixel=Array.from(result.bytes.slice(at,at+4));if(result.format.startsWith('bgra'))[pixel[0],pixel[2]]=[pixel[2],pixel[0]];
    let rejected=false;try{await renderer.prepare('invalid shader');}catch{rejected=true;}
    await renderer.readPixels(frame);const before=renderer.resources;await renderer.readPixels(frame);const after=renderer.resources;
    return{pixel,rejected,reused:before.uploads===after.uploads};})()`);
  assert.deepEqual(depth, {pixel:[255,0,0,255], rejected:true, reused:true});
  console.log('ok - depth rejects later hidden triangles; failed shader preparation preserves the reusable renderer');
  const resizing = await evaluate(`(async()=>{const {renderer,frame}=sceneFixture,canvas=document.querySelector('canvas');
    const width=canvas.width,height=canvas.height,first=renderer.readPixels(frame);
    canvas.width=width-16;canvas.height=height-8;const second=renderer.readPixels(frame);
    const [a,b]=await Promise.all([first,second]);canvas.width=width;canvas.height=height;
    return{first:a.bytes.length===a.bytesPerRow*height,second:b.bytes.length===b.bytesPerRow*(height-8),errors:sceneErrors};})()`);
  assert.deepEqual(resizing, {first:true,second:true,errors:[]});
  console.log('ok - resizing during queued readback retains each submitted frame');
  const lifetime = await evaluate(`(async()=>{const {renderer,frame}=sceneFixture;
    const source=await(await fetch('./shader.wgsl')).text(),preparing=renderer.prepare(source);
    const reading=renderer.readPixels(frame); await renderer.close(); await reading;
    return {drawStopped:renderer.draw(frame)===undefined,closed:renderer.resources.closed,
      preparationRejected:await preparing.then(()=>false,()=>true),
      vertexBytes:renderer.resources.vertexBytes,textures:renderer.resources.textures,pending:renderer.resources.pending};})()`);
  assert.deepEqual(lifetime, {drawStopped: true, closed: true, preparationRejected:true,vertexBytes:0,textures:0,pending:0});
  console.log('ok - close drains queued readback, rejects in-flight preparation and stops further draw admission');
} finally { ws.close(); await fetch(`${devtools}/json/close/${target.id}`); }
