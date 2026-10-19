// Actual compiled flight poses and retained cables rendered through Chromium WebGPU.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {colony, client, colonyWords, clientWords, at, pixelAt, setWorker, withdrawReserves} from '../applications/colony-state.mjs';
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
const command = async (binding,args=[]) => {await evaluate(`snailApp.local(${JSON.stringify(binding)},${JSON.stringify(args)})`);await settled();};
const displayFrame = () => evaluate('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))');
// Freeze only the fixture clock; a paused World now correctly opens its menu.
const settled = async () => {await evaluate('snailApp.drainUpdates()');await evaluate('snailApp.session.stopClock()');await until(() => evaluate('!snailApp.localWork && !snailApp.dirty'), 'input did not settle');};

async function restore(world) {
  await evaluate(`snailApp.session.local.restore(${JSON.stringify(colonyWords(world))})`);await settled();
}
async function advance() {
  await evaluate("snailApp.session.local.submit(snailApp.runtime.command('match','advance'))");await settled();
}
try {
  await call('Runtime.enable');await call('Page.navigate',{url:origin});await call('Page.bringToFront');
  await until(()=>evaluate('!!globalThis.snailApp?.session'),'game startup');await settled();
  await command('restart-seed',[1]);await settled();
  const value=await world(),site=at(value,12,24),point=pixelAt(value,12,24);
  value.started=true;value.spent=25;value.ore-=25;
  value.buildings=[{id:value.nextId++,kind:3,...site,level:1,hp:90,stock:0,stage:2,cooldown:0,
    aimX:point.x,aimY:point.y,armed:0,source:0,moveX:-1,moveY:-1}];
  value.surveys.push({...site,radius:7});await restore(value);await advance();
  const loaded=await world();withdrawReserves(loaded,32);loaded.rails[0].cargo=16;
  setWorker(loaded,0,{x:12,y:24,job:2,cargo:16,path:[8+22*48]});await restore(loaded);
  const camera=await local();await evaluate(`snailApp.runtime.restore(2,${JSON.stringify(clientWords({...camera,
    cameraX:(site.x-2)*1000,cameraY:(site.y-1)*1000,homing:false,scale:900}))})`);
  for(let tick=1;tick<=4;tick++) {
    await advance();const current=await world();assert.equal(current.bots[0].flight.length,1);
    if(tick<=2)assert.deepEqual([current.bots[0].x,current.bots[0].y],[point.x,point.y]);
    else assert.ok(current.bots[0].x<point.x&&current.bots[0].y<point.y);
    for(const [width,height] of [[1100,760],[390,844]]) {
      await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:width<700});
      await command('viewport',[width,height]);await displayFrame();
      const result=await evaluate(`(async()=>{const scene=snailApp.runtime.view().scene,renderer=snailApp.renderer;
        const pixels=await renderer.readPixels(scene),cable=scene.batches.find(b=>b.key===20),body=scene.batches.find(b=>b.key===3);
        return{colors:new Set(pixels.bytes).size,bytes:pixels.bytes.length,lost:renderer.resources.lost,
          spans:cable.draws.reduce((n,d)=>n+d.count,0),altitude:cable.transforms[11],
          guides:scene.batches.find(b=>b.key===14).draws.length,
          moving:body.transforms.some((v,i)=>i%4===3&&Math.abs(v-body.previous[i])>.0001)};})()`);
      assert.equal(result.lost,false);assert.equal(result.spans,1);assert.ok(Math.abs(result.altitude-.9)<1e-6);
      assert.ok(result.guides>0&&result.colors>30&&result.bytes>width*height*3);assert.equal(result.moving,true);
      if(process.argv[4]){const shot=await call('Page.captureScreenshot',{format:'png'});
        writeFileSync(process.argv[4].replace('.png',`-${width}x${height}-tick${tick}.png`),Buffer.from(shot.data,'base64'));}
      console.log(`ok - GPU ${width}x${height} flight tick ${tick}: lift/cruise, direct cable and reveal guides`);
    }
  }
  const saved=await evaluate('snailApp.runtime.snapshot(1)');await evaluate(`snailApp.session.local.restore(${JSON.stringify(saved)})`);
  assert.deepEqual(await evaluate('snailApp.runtime.snapshot(1)'),saved);
  console.log('ok - browser durable save resumes the captured aerial trip');
} finally {ws.close();await fetch(`${devtools}/json/close/${target.id}`);}
