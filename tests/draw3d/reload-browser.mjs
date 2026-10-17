// Start against the earlier served generation, then publish a compatible
// package while this test waits. Both owners and the GPU device must survive.
import assert from 'node:assert/strict';
const [origin, generation, devtools='http://127.0.0.1:9452']=process.argv.slice(2);
const target=await(await fetch(`${devtools}/json/new?${encodeURIComponent(origin)}`,{method:'PUT'})).json();
const ws=new WebSocket(target.webSocketDebuggerUrl),pending=new Map();let sequence=0;
await new Promise(resolve=>ws.addEventListener('open',resolve,{once:true}));
ws.onmessage=event=>{const data=JSON.parse(event.data);if(data.id){pending.get(data.id)?.(data);pending.delete(data.id);}};
function call(method,params={}) {
  return new Promise((resolve,reject)=>{const id=++sequence;
    const timer=setTimeout(()=>reject(new Error(`CDP timeout: ${method}`)),30000);
    pending.set(id,data=>{clearTimeout(timer);data.error?reject(new Error(data.error.message)):resolve(data.result);});
    ws.send(JSON.stringify({id,method,params}));});
}
async function evaluate(expression) {
  const result=await call('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});
  if(result.exceptionDetails)throw new Error(result.exceptionDetails.exception?.description??result.exceptionDetails.text);
  return result.result.value;
}
async function until(expression) {
  const deadline=Date.now()+120000;
  while(Date.now()<deadline){if(await evaluate(expression))return;await new Promise(resolve=>setTimeout(resolve,100));}
  throw new Error(`Did not settle: ${expression}`);
}
try {
  await call('Page.bringToFront');await until('!!globalThis.snailApp');
  assert.notEqual(await evaluate('snailApp.generation'),generation);
  await evaluate('snailApp.local("suspend",[1])');
  await evaluate('snailApp.local("pan",[1,-1])');
  await until('!snailApp.localWork&&!snailApp.dirty&&!snailApp.session.sending&&!snailApp.pending.length');
  const before=await evaluate('({world:snailApp.runtime.snapshot(1),client:snailApp.runtime.snapshot(2)})');
  await evaluate('globalThis.retainedRenderer=snailApp.renderer');
  console.log(`READY for compatible publication at ${origin}`);
  await until(`snailApp.generation===${JSON.stringify(generation)}`);
  await until('!snailApp.localWork&&!snailApp.dirty&&!snailApp.session.sending&&!snailApp.pending.length');
  assert.deepEqual(await evaluate('({world:snailApp.runtime.snapshot(1),client:snailApp.runtime.snapshot(2)})'),before);
  assert.equal(await evaluate('snailApp.renderer===retainedRenderer'),true);
  const pixels=await evaluate('(async()=>{const p=await snailApp.renderer.readPixels(snailApp.runtime.view().scene);return p.bytes.length})()');
  assert.ok(pixels>100000);
  console.log('ok - changed Scheme code/shader generation retains both owners and the existing GPU renderer',origin);
} finally {
  await evaluate('snailApp.session.stopping=true;clearTimeout(snailApp.session.timer);clearTimeout(snailApp.session.reloading);snailApp.session.events?.close();snailApp.close()').catch(()=>{});
  ws.close();await fetch(`${devtools}/json/close/${target.id}`);
}
