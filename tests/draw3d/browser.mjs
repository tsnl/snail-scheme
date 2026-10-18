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
      uniforms:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1,1,1,1,1,0,0,0,0,0,0,-1]};
    const result=await renderer.readPixels(probe),canvas=document.querySelector('canvas');
    const at=Math.floor(canvas.height/2)*result.bytesPerRow+Math.floor(canvas.width/2)*4;
    const pixel=Array.from(result.bytes.slice(at,at+4));if(result.format.startsWith('bgra'))[pixel[0],pixel[2]]=[pixel[2],pixel[0]];
    const staticMotionBytes=renderer.resources.motionBytes;
    let rejected=false;try{await renderer.prepare('invalid shader');}catch{rejected=true;}
    await renderer.readPixels(frame);const before=renderer.resources;await renderer.readPixels(frame);const after=renderer.resources;
    return{pixel,rejected,reused:before.uploads===after.uploads,staticMotionBytes};})()`);
  assert.deepEqual(depth, {pixel:[255,0,0,255], rejected:true, reused:true,staticMotionBytes:0});
  console.log('ok - depth rejects later hidden triangles; failed shader preparation preserves the reusable renderer');
  const resizing = await evaluate(`(async()=>{const {renderer,frame}=sceneFixture,canvas=document.querySelector('canvas');
    const width=canvas.width,height=canvas.height,first=renderer.readPixels(frame);
    canvas.width=width-16;canvas.height=height-8;const second=renderer.readPixels(frame);
    const [a,b]=await Promise.all([first,second]);canvas.width=width;canvas.height=height;
    return{first:a.bytes.length===a.bytesPerRow*height,second:b.bytes.length===b.bytesPerRow*(height-8),errors:sceneErrors};})()`);
  assert.deepEqual(resizing, {first:true,second:true,errors:[]});
  console.log('ok - resizing during queued readback retains each submitted frame');
  const motion = await evaluate(`(async()=>{const {renderer,frame}=sceneFixture,canvas=document.querySelector('canvas');
    const original=Object.getOwnPropertyDescriptor(performance,'now');let time=1000;
    Object.defineProperty(performance,'now',{configurable:true,value:()=>time});
    function triangle(key,y,color,duration){const vertices=[],previous=[];
      for(const [x,dy] of [[-.12,-.12],[.12,-.12],[0,.18]]){
        vertices.push(.48+x,y+dy,.3,0,0,1,...color,1);previous.push(-.48+x,y+dy,.3);}
      return{key,vertices,previous,indices:[0,1,2],duration};}
    const probe={batches:[triangle(30,.4,[1,0,0],100),triangle(31,-.4,[0,0,1],200)],background:[0,0,0],
      uniforms:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1,1,1,1,1,0,0,0,0,0,0,-1]};
    async function sample(points){const result=await renderer.readPixels(probe);
      return points.map(([x,y])=>{const at=Math.floor((1-y)*canvas.height/2)*result.bytesPerRow+Math.floor((1+x)*canvas.width/2)*4;
        const pixel=Array.from(result.bytes.slice(at,at+4));if(result.format.startsWith('bgra'))[pixel[0],pixel[2]]=[pixel[2],pixel[0]];return pixel;});}
    try{const start=await sample([[-.48,.4],[-.48,-.4]]),uploads=renderer.resources.uploads;
      const motionBuffers=renderer.resources.motionBytes>0;
      time=1050;const before=renderer.resources.frames;renderer.animate(time);const animated=renderer.resources.frames===before+1;
      const halfway=await sample([[0,.4],[-.24,-.4],[-.48,.4]]);
      const source=await(await fetch('./shader.wgsl')).text();renderer.replace(await renderer.prepare(source));
      const replacement=await sample([[0,.4],[-.24,-.4]]);
      time=1100;const separated=await sample([[.48,.4],[0,-.4]]);
      time=1300;const last=renderer.resources.frames;renderer.animate(time);const terminal=renderer.resources.frames===last+1;
      const done=renderer.resources.frames;renderer.animate(time+16);const stopped=renderer.resources.frames===done;
      const endpoint=await sample([[.48,.4],[.48,-.4]]);
      return{start,halfway,replacement,separated,endpoint,animated,terminal,stopped,motionBuffers,
        reused:renderer.resources.uploads===uploads,errors:sceneErrors};
    }finally{if(original)Object.defineProperty(performance,'now',original);else delete performance.now;renderer.draw(frame);}})()`);
  const red=[255,0,0,255],blue=[0,0,255,255],black=[0,0,0,255];
  assert.deepEqual(motion, {start:[red,blue],halfway:[red,blue,black],replacement:[red,blue],
    separated:[red,blue],endpoint:[red,blue],animated:true,terminal:true,stopped:true,motionBuffers:true,reused:true,errors:[]});
  console.log('ok - GPU motion reaches intermediate and final pixels with independent clocks, reused buffers and shader replacement');
  const insets = await evaluate(`(async()=>{const {renderer,frame}=sceneFixture,canvas=document.querySelector('canvas');
    const before={width:canvas.width,height:canvas.height,cssWidth:canvas.style.width,cssHeight:canvas.style.height};
    canvas.style.width='960px';canvas.style.height='640px';canvas.width=1920;canvas.height=1280;
    const matrix=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1,1,1,1,1,0,0,0,0,0,0,-1];
    function quad(color){const vertices=[];for(const [x,y] of [[-1,-1],[1,-1],[1,1],[-1,1]])vertices.push(x,y,.3,0,0,1,...color,1);
      return{key:0,vertices,indices:[0,1,2,0,2,3]};}
    const shifted=matrix.slice();shifted[12]=1;
    const first={key:0,rect:[20,30,96,72],uniforms:matrix,background:[0,0,0],batches:[quad([0,0,1])]},
      second={key:1,rect:[140,30,96,72],uniforms:shifted,background:[1,1,1],batches:[quad([0,1,0])]},
      probe={uniforms:matrix,background:[0,0,0],batches:[quad([1,0,0])],insets:[first,second]};
    async function sample(scene,points){const result=await renderer.readPixels(scene);
      return points.map(([x,y])=>{const at=Math.floor(y*2)*result.bytesPerRow+Math.floor(x*2)*4;
        const pixel=Array.from(result.bytes.slice(at,at+4));if(result.format.startsWith('bgra'))[pixel[0],pixel[2]]=[pixel[2],pixel[0]];return pixel;});}
    try{const points=[[10,10],[68,66],[164,66],[212,66],[100,200]],initial=await sample(probe,points),resources=renderer.resources;
      const source=await(await fetch('./shader.wgsl')).text();renderer.replace(await renderer.prepare(source));
      const replaced=await sample(probe,points),reused=renderer.resources.uploads===resources.uploads;
      const resized={...probe,insets:[{...first,rect:[20,30,48,36]},second]},reading=renderer.readPixels(probe);
      const resizedPixels=await sample(resized,[[44,48],[212,66]]);await reading;
      const resizeReused=renderer.resources.uploads===resources.uploads,resizePixels=renderer.resources.insetPixels;
      const clipped=await sample({...probe,insets:[{...first,rect:[950,30,96,72]}]},[[949,50],[955,50]]);
      await renderer.readPixels({...probe,insets:[{...first,rect:[1000,30,96,72]}]});
      const hidden=renderer.resources;
      return{initial,replaced,resizedPixels,clipped,reused,resizeReused,resizePixels,requests:sceneRequests(),
        active:{insets:resources.insets,textures:resources.textures,batches:resources.batches,pixels:resources.insetPixels},
        hidden:{insets:hidden.insets,textures:hidden.textures,batches:hidden.batches},errors:sceneErrors};
    }finally{canvas.width=before.width;canvas.height=before.height;canvas.style.width=before.cssWidth;canvas.style.height=before.cssHeight;renderer.draw(frame);}})()`);
  const green=[0,255,0,255],white=[255,255,255,255],viewPixels=[red,blue,white,green,red];
  assert.deepEqual(insets,{initial:viewPixels,replaced:viewPixels,resizedPixels:[blue,green],clipped:[red,blue],
    reused:true,resizeReused:true,resizePixels:34560,requests:{adapters:1,devices:1},
    active:{insets:2,textures:5,batches:3,pixels:55296},hidden:{insets:0,textures:1,batches:1},errors:[]});
  console.log('ok - native-DPR inset cameras copy exact pixels with one device, isolated batch keys, cached geometry and released hidden resources');
  const reveal = await evaluate(`(async()=>{const {renderer,frame}=sceneFixture,canvas=document.querySelector('canvas');
    const before={width:canvas.width,height:canvas.height,cssWidth:canvas.style.width,cssHeight:canvas.style.height};
    const original=Object.getOwnPropertyDescriptor(performance,'now');let time=1000;
    Object.defineProperty(performance,'now',{configurable:true,value:()=>time});
    canvas.style.width='400px';canvas.style.height='400px';canvas.width=400;canvas.height=400;
    const matrix=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1,1,1,1,1,0,0,0,0,0,0,-1];
    function quad(key,color,left,right,bottom,top){const vertices=[];
      for(const[x,y]of[[left,bottom],[right,bottom],[right,top],[left,top]])vertices.push(x,y,.3,0,0,1,...color,1);
      return{key,vertices,indices:[0,1,2,0,2,3]};}
    const transition={id:123,x:0,y:0,radius:1,edge:.2,elapsed:0,duration:3000};
    const fresh={...quad(42,[1,0,0],-.7,.7,-.7,.7),reveal:transition},old=quad(41,[0,1,0],-.9,-.75,-.9,.9);
    let probe={uniforms:matrix,background:[0,0,1],batches:[old,fresh]};
    async function pixels(scene,points){const result=await renderer.readPixels(scene),sx=canvas.width/400,sy=canvas.height/400;
      return points.map(([x,y])=>{const at=Math.floor(y*sy)*result.bytesPerRow+Math.floor(x*sx)*4;
        const p=Array.from(result.bytes.slice(at,at+4));if(result.format.startsWith('bgra'))[p[0],p[2]]=[p[2],p[0]];return p;});}
    const points=[[40,200],[200,200],[284,200],[300,200],[316,200],[336,64]];
    try{const initial=await pixels(probe,points),uploads=renderer.resources.uploads;
      time=2500;const frames=renderer.resources.frames;renderer.animate(time);const animated=renderer.resources.frames===frames+1;
      const middle=await pixels(probe,points),reused=renderer.resources.uploads===uploads;
      const aged={...fresh,reveal:{...transition,elapsed:0}},inset={key:8,rect:[300,10,96,72],uniforms:matrix,background:[0,0,1],batches:[aged]};
      probe={...probe,batches:[old,aged],insets:[inset]};
      const shared=await pixels(probe,[[200,200],[300,200],[348,46],[372,46]]);
      const afterInset=renderer.resources.uploads;
      probe={...probe,batches:[old,{...fresh,reveal:{...transition,elapsed:2900}}]};
      const noRestart=await pixels(probe,[[300,200]]),metadataReused=renderer.resources.uploads===afterInset;
      const shifted=matrix.slice();shifted[12]=.1;probe={...probe,uniforms:shifted};
      const camera=await pixels(probe,[[320,200]]);
      renderer.replace(await renderer.prepare(await(await fetch('./shader.wgsl')).text()));
      canvas.width=600;canvas.height=600;const resized=await pixels(probe,[[320,200]]);
      const rebuilt={...fresh,vertices:fresh.vertices.slice(),reveal:{...transition,elapsed:0}};
      probe={...probe,batches:[old,rebuilt]};const rebuild=await pixels(probe,[[320,200]]);
      time=4100;const ending=renderer.resources.frames;renderer.animate(time);const terminal=renderer.resources.frames===ending+1;
      const done=renderer.resources.frames;renderer.animate(time+16);const stopped=renderer.resources.frames===done;
      const endpoint=await pixels(probe,[[60,200],[220,200],[356,64]]),held=renderer.resources.reveals;
      const plain={...probe,batches:[old,{...fresh,reveal:undefined}],insets:[]};await renderer.readPixels(plain);
      const released=renderer.resources.reveals;
      const resumed={...plain,batches:[old,{...fresh,reveal:{...transition,elapsed:1500}}]};
      const seeded=await pixels(resumed,[[320,200]]);
      renderer.draw({...plain,batches:[{key:42,vertices:[],indices:[],reveal:transition}]});
      const hiddenFrames=renderer.resources.frames;renderer.animate(4150);
      const hiddenRetained=renderer.resources.reveals===1&&renderer.resources.frames===hiddenFrames;
      time=4200;const reappeared=await pixels(resumed,[[335,200]]);
      let sizeRejected=false;const resources=renderer.resources;
      try{renderer.draw({...plain,insets:[{...inset,rect:[0,0,renderer.device.limits.maxTextureDimension2D+1,72]}]});}catch{sizeRejected=true;}
      const sizePreserved=renderer.resources.textures===resources.textures&&renderer.resources.uploads===resources.uploads;
      return{initial,middle,shared,noRestart,camera,resized,rebuild,endpoint,seeded,reappeared,animated,reused,metadataReused,
        terminal,stopped,held,released,hiddenRetained,sizeRejected,sizePreserved,errors:sceneErrors};
    }finally{if(original)Object.defineProperty(performance,'now',original);else delete performance.now;
      canvas.width=before.width;canvas.height=before.height;canvas.style.width=before.cssWidth;canvas.style.height=before.cssHeight;renderer.draw(frame);}})()`);
  assert.deepEqual(reveal.initial,[green,blue,blue,blue,blue,blue]);
  assert.deepEqual(reveal.middle.slice(0,2),[green,red]);
  assert.ok(reveal.middle[2][0]>235&&reveal.middle[2][2]<20,'inner feather should be nearly revealed');
  assert.ok(reveal.middle[3][0]>110&&reveal.middle[3][0]<145&&reveal.middle[3][2]>110,'one triangle must contain partial fragment opacity');
  assert.ok(reveal.middle[4][0]<20&&reveal.middle[4][2]>235,'outer feather should remain nearly hidden');
  assert.deepEqual(reveal.middle[5],blue);
  assert.deepEqual([reveal.shared[0],reveal.shared[2]],[red,red]);
  for(const pixel of [reveal.shared[1],reveal.shared[3],...reveal.noRestart,...reveal.camera,...reveal.resized,...reveal.rebuild,...reveal.seeded,...reveal.reappeared])
    assert.ok(pixel[0]>100&&pixel[0]<150&&pixel[2]>100&&pixel[2]<150,`reveal clock changed across a retained camera/geometry update: ${pixel}`);
  assert.deepEqual(reveal.endpoint,[green,red,red]);
  for(const flag of ['animated','reused','metadataReused','terminal','stopped','hiddenRetained','sizeRejected','sizePreserved'])assert.equal(reveal[flag],true,flag);
  assert.equal(reveal.held,1);assert.equal(reveal.released,0);assert.deepEqual(reveal.errors,[]);
  console.log('ok - fragment-soft radial reveals share clocks across cameras, keep old coverage stable, reuse geometry and hold the terminal frame');
  const insetMotion=await evaluate(`(async()=>{const{renderer,frame}=sceneFixture,canvas=document.querySelector('canvas');
    const original=Object.getOwnPropertyDescriptor(performance,'now');let time=5000;
    Object.defineProperty(performance,'now',{configurable:true,value:()=>time});
    const vertices=[],previous=[];
    for(const[x,y]of[[-.15,-.15],[.15,-.15],[0,.2]]){vertices.push(.5+x,y,.3,0,0,1,1,0,0,1);previous.push(-.5+x,y,.3);}
    const uniforms=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1,1,1,1,1,0,0,0,0,0,0,-1];
    const probe={uniforms,background:[0,0,1],batches:[{key:0,vertices:[],indices:[]}],insets:[
      {key:2,rect:[10,10,100,100],uniforms,background:[0,0,0],batches:[{key:0,vertices,previous,indices:[0,1,2],duration:100}]}]};
    try{renderer.draw(probe);time=5050;const before=renderer.resources.frames;renderer.animate(time);
      const animated=renderer.resources.frames===before+1,result=await renderer.readPixels(probe);
      const at=Math.floor(60*canvas.height/canvas.clientHeight)*result.bytesPerRow+Math.floor(60*canvas.width/canvas.clientWidth)*4;
      const pixel=Array.from(result.bytes.slice(at,at+4));if(result.format.startsWith('bgra'))[pixel[0],pixel[2]]=[pixel[2],pixel[0]];
      time=5200;const ending=renderer.resources.frames;renderer.animate(time);const terminal=renderer.resources.frames===ending+1;
      const done=renderer.resources.frames;renderer.animate(time+16);return{animated,pixel,terminal,stopped:renderer.resources.frames===done,errors:sceneErrors};
    }finally{if(original)Object.defineProperty(performance,'now',original);else delete performance.now;renderer.draw(frame);}})()`);
  assert.deepEqual(insetMotion,{animated:true,pixel:red,terminal:true,stopped:true,errors:[]});
  console.log('ok - inset-only motion drives display redraw and presents its terminal frame while the main scene is static');
  const lifetime = await evaluate(`(async()=>{const {renderer,frame}=sceneFixture;
    const source=await(await fetch('./shader.wgsl')).text(),preparing=renderer.prepare(source);
    const closingFrame={...frame,insets:[{...frame,key:9,rect:[10,10,96,72]}]};
    const reading=renderer.readPixels(closingFrame); await renderer.close(); await reading;
    return {drawStopped:renderer.draw(frame)===undefined,closed:renderer.resources.closed,
      preparationRejected:await preparing.then(()=>false,()=>true),
      vertexBytes:renderer.resources.vertexBytes,motionBytes:renderer.resources.motionBytes,insets:renderer.resources.insets,
      reveals:renderer.resources.reveals,textures:renderer.resources.textures,pending:renderer.resources.pending};})()`);
  assert.deepEqual(lifetime, {drawStopped: true, closed: true, preparationRejected:true,vertexBytes:0,motionBytes:0,insets:0,reveals:0,textures:0,pending:0});
  console.log('ok - close drains queued readback, rejects in-flight preparation and stops further draw admission');
} finally { ws.close(); await fetch(`${devtools}/json/close/${target.id}`); }
