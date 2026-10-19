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
      vertices:frame.batches.reduce((n,b)=>n+b.draws.reduce((sum,draw)=>sum+draw.count*draw.mesh.vertices.length/10,0),0),
      triangles:frame.batches.reduce((n,b)=>n+b.draws.reduce((sum,draw)=>sum+draw.count*draw.mesh.indices.length/3,0),0),errors:sceneErrors};})()`);
  assert.ok(pixels.colors > 30); assert.ok(pixels.bytes > 100000); assert.deepEqual(pixels.errors, []);
  console.log('ok - actual Chromium WebGPU scene pixels', pixels);
  if (process.argv[4]) { const shot = await call('Page.captureScreenshot', {format: 'png'}); writeFileSync(process.argv[4], Buffer.from(shot.data, 'base64')); }
  const instances=await evaluate(`(async()=>{const {renderer,frame}=sceneFixture;
    const {hydrateFrame}=await import('./scene-tools.mjs');
    const scene=hydrateFrame(await(await fetch('./instances.json')).json()),calls=[];
    const original=renderer.device.createCommandEncoder;
    renderer.device.createCommandEncoder=function(...args){const encoder=original.apply(this,args),begin=encoder.beginRenderPass.bind(encoder);
      encoder.beginRenderPass=(...args)=>{const pass=begin(...args),draw=pass.drawIndexed.bind(pass);
        pass.drawIndexed=(...args)=>{calls.push(args);return draw(...args);};return pass;};return encoder;};
    try{const before=renderer.resources.meshUploads;await renderer.readPixels(scene);
      const first=renderer.resources,initial=calls.splice(0);
      await renderer.readPixels({...scene,uniforms:scene.uniforms.slice()});const camera=renderer.resources;
      const moving=scene.batches[2],next={...scene,batches:[...scene.batches.slice(0,2),
        {...moving,transforms:moving.transforms.map((value,index)=>index%12===3?value+.25:value)}]};
      await renderer.readPixels(next);const changed=renderer.resources;
      return{counts:initial.map(call=>call[1]),firstInstances:initial.map(call=>call[4]),
        meshes:first.meshes,newMeshes:first.meshUploads-before,instances:first.instances,
        instancedDraws:first.instancedDraws,cameraReuse:camera.uploads===first.uploads&&camera.meshUploads===first.meshUploads,
        transformOnly:changed.uploads===camera.uploads+1&&changed.meshUploads===camera.meshUploads,
        instanceBytes:first.instanceBytes,errors:sceneErrors};
    }finally{renderer.device.createCommandEncoder=original;renderer.draw(frame);}})()`);
  assert.deepEqual(instances.counts,[1,1,1,2,1,2]);
  assert.deepEqual(instances.firstInstances,[0,1,2,0,2,0]);
  for(const [key,value]of Object.entries({meshes:3,newMeshes:3,instances:8,instancedDraws:2,cameraReuse:true,transformOnly:true}))assert.equal(instances[key],value,key);
  assert.ok(instances.instanceBytes>0);assert.deepEqual(instances.errors,[]);
  console.log('ok - GPU indexed draws use real instance counts and shared colored model buffers; camera changes upload nothing and new ticks upload only occurrence data',instances);
  const anisotropic=await evaluate(`(async()=>{const {renderer,frame}=sceneFixture,canvas=document.querySelector('canvas');
    const {hydrateFrame}=await import('./scene-tools.mjs');
    const scene=hydrateFrame(await(await fetch('./anisotropic.json')).json());
    try{const result=await renderer.readPixels(scene),at=Math.floor(canvas.height/2)*result.bytesPerRow+Math.floor(canvas.width/2)*4;
      return{pixel:Array.from(result.bytes.slice(at,at+4)),coefficient:scene.batches[0].normals[4],errors:sceneErrors};}
    finally{renderer.draw(frame);}})()`);
  assert.deepEqual(anisotropic.pixel,[255,255,255,255]);assert.deepEqual(anisotropic.errors,[]);
  assert.ok(anisotropic.coefficient>0&&anisotropic.coefficient<1e-35);
  console.log('ok - actual Wasm diagonal anisotropy retains a tiny finite normal coefficient and produces the expected lit GPU pixel');
  const order=await evaluate(`(async()=>{const {renderer,frame}=sceneFixture,canvas=document.querySelector('canvas');
    const {identityTransform:t,identityNormal:n}=await import('./scene-tools.mjs');
    function mesh(color){const vertices=[];for(const[x,y]of[[-.8,-.8],[.8,-.8],[0,.8]])vertices.push(x,y,.3,0,0,1,...color,1);return{vertices,indices:[0,1,2]};}
    const a=mesh([1,0,0]),b=mesh([0,0,1]),batch={key:77,draws:[{mesh:a,first:0,count:1},{mesh:b,first:1,count:1},{mesh:a,first:2,count:1}],
      transforms:[...t,...t,...t],normals:[...n,...n,...n]};
    const scene={batches:[batch],background:[0,0,0],uniforms:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1,1,1,1,1,0,0,0,0,0,0,-1]};
    async function center(value){const result=await renderer.readPixels(value),at=Math.floor(canvas.height/2)*result.bytesPerRow+Math.floor(canvas.width/2)*4;
      const pixel=Array.from(result.bytes.slice(at,at+4));if(result.format.startsWith('bgra'))[pixel[0],pixel[2]]=[pixel[2],pixel[0]];return pixel;}
    try{return{opaque:await center(scene),alpha:await center({...scene,batches:[{...batch,opacity:.5}]}),errors:sceneErrors};}
    finally{renderer.draw(frame);}})()`);
  assert.deepEqual(order.opaque,[255,0,0,255]);assert.ok(Math.abs(order.alpha[0]-160)<=1&&Math.abs(order.alpha[2]-64)<=1);
  assert.deepEqual(order.errors,[]);console.log('ok - ordered A/B/A instance runs preserve opaque tie winners and transparent blending');
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
  const phases = await evaluate(`(async()=>{const {renderer,frame}=sceneFixture,canvas=document.querySelector('canvas');
    const original=Object.getOwnPropertyDescriptor(performance,'now');let time=Math.PI/2/.004;
    Object.defineProperty(performance,'now',{configurable:true,value:()=>time});
    const batches=Array.from({length:8},(_,i)=>{const vertices=[],x=-.84+i*.24;
      for(const[dx,y]of[[-.07,-.08],[.07,-.08],[.07,.08],[-.07,.08]])vertices.push(x+dx,y,.3,0,0,1,1,1,1,1);
      return{key:60+i,vertices,indices:[0,1,2,0,2,3],opacity:.9,pulse:true,pulsePhase:i*Math.PI/4};});
    const scene={batches,background:[0,0,0],uniforms:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1,1,1,1,1,0,0,0,0,0,0,-1]};
    async function sample(){const result=await renderer.readPixels(scene);return batches.map((_,i)=>{
      const x=Math.floor((1-.84+i*.24)*canvas.width/2),y=Math.floor(canvas.height/2);
      return result.bytes[y*result.bytesPerRow+x*4];});}
    try{const first=await sample(),uploads=renderer.resources.uploads;time+=16;
      const frames=renderer.resources.frames;renderer.animate(time);const between=await sample();
      time=Math.PI*3/4/.004;const second=await sample();time=Math.PI/.004;const third=await sample();
      return{first,between,second,third,animated:renderer.resources.frames>frames,reused:renderer.resources.uploads===uploads,errors:sceneErrors};
    }finally{if(original)Object.defineProperty(performance,'now',original);else delete performance.now;renderer.draw(frame);}})()`);
  for(const [values,index] of [[phases.first,0],[phases.second,1],[phases.third,2]])
    assert.equal(values.indexOf(Math.max(...values)),index,'the brightness crest advances through increasing path phases');
  assert.notDeepEqual(phases.between,phases.first,'display time advances the glow between simulation ticks');
  assert.equal(phases.animated,true);assert.equal(phases.reused,true);assert.deepEqual(phases.errors,[]);
  console.log('ok - retained phase groups animate between ticks and move their glow upstream without geometry uploads');
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
  const hardReveal = await evaluate(`(async()=>{const {renderer,frame}=sceneFixture,canvas=document.querySelector('canvas');
    const before={width:canvas.width,height:canvas.height},original=Object.getOwnPropertyDescriptor(performance,'now');let time=1000;
    Object.defineProperty(performance,'now',{configurable:true,value:()=>time});canvas.width=400;canvas.height=400;
    const vertices=[];for(const[x,y]of[[-.9,-.9],[.9,-.9],[.9,.9],[-.9,.9]])vertices.push(x,y,.3,0,0,1,1,0,0,1);
    const batch={key:93,vertices,indices:[0,1,2,0,2,3],reveal:{id:987,x:.37,y:.21,radius:.6,edge:0,elapsed:1500,duration:3000}};
    const scene={uniforms:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1,1,1,1,1,0,0,0,0,0,0,-1],background:[0,0,1],batches:[batch]};
    async function sample(points){const result=await renderer.readPixels(scene);return points.map(([x,y])=>{
      const at=Math.floor((1-y)*200)*result.bytesPerRow+Math.floor((x+1)*200)*4,p=Array.from(result.bytes.slice(at,at+4));
      if(result.format.startsWith('bgra'))[p[0],p[2]]=[p[2],p[0]];return p;});}
    try{const points=[[.37,.21],[.66,.21],[.68,.21],[.57,.41],[.60,.44],[.08,.21],[.06,.21]];
      const middle=await sample(points),uploads=renderer.resources.uploads;
      time=1100;renderer.animate(time);const advanced=await sample([[.68,.21],[.06,.21]]);
      const reused=renderer.resources.uploads===uploads;time=2500;renderer.animate(time);
      return{middle,advanced,reused,endpoint:await sample(points),errors:sceneErrors};
    }finally{if(original)Object.defineProperty(performance,'now',original);else delete performance.now;
      canvas.width=before.width;canvas.height=before.height;renderer.draw(frame);}})()`);
  assert.deepEqual(hardReveal.middle,[red,red,blue,red,blue,red,blue]);
  assert.deepEqual(hardReveal.advanced,[red,red]);assert.equal(hardReveal.reused,true);
  assert.deepEqual(hardReveal.endpoint,Array(7).fill(red));assert.deepEqual(hardReveal.errors,[]);
  console.log('ok - zero-edge reveals cut a hard continuous circle through triangle interiors and advance without geometry uploads');
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
  const singleSample = await evaluate(`(async()=>{const {createSceneRenderer}=await import('./lib/webgpu/scene.mjs');
    const canvas=document.createElement('canvas');canvas.style.width='128px';canvas.style.height='96px';
    canvas.width=256;canvas.height=192;document.body.append(canvas);
    const errors=[],renderer=sceneFixture.adaptProbeRenderer(await createSceneRenderer(canvas,error=>errors.push(error.message))),textures=[],buffers=[];
    const createBuffer=renderer.device.createBuffer.bind(renderer.device);
    renderer.device.createBuffer=descriptor=>{const buffer=createBuffer(descriptor),destroy=buffer.destroy.bind(buffer),record={destroyed:0};
      buffers.push(record);buffer.destroy=()=>{record.destroyed++;destroy();};return buffer;};
    const createTexture=renderer.device.createTexture.bind(renderer.device);
    renderer.device.createTexture=descriptor=>{const texture=createTexture(descriptor),destroy=texture.destroy.bind(texture);
      const record={width:texture.width,height:texture.height,samples:texture.sampleCount,destroyed:0};textures.push(record);
      texture.destroy=()=>{record.destroyed++;destroy();};return texture;};
    const vertices=[];for(const[x,y]of[[-.73,-.79],[.81,-.79],[-.73,.83]])vertices.push(x,y,.3,0,0,1,1,1,1,1);
    const picture={uniforms:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1,1,1,1,1,0,0,0,0,0,0,-1],
      background:[0,0,0],batches:[{key:0,vertices,indices:[0,1,2]}]};
    const rects=[[68,2,48,40],[68,44,24,20],[68,66,16,18]],
      scene={...picture,insets:rects.map((rect,key)=>({...picture,key,rect}))};
    function owned(){return textures.filter(texture=>!texture.destroyed).map(({width,height,samples})=>[width,height,samples]);}
    async function coverage(){const result=await renderer.readPixels(scene),scale=canvas.width/128;
      return [[0,0,64,96],...rects].map(([x,y,width,height])=>{const values=new Set();let partial=0,white=0,black=0;
        for(let row=y*scale;row<(y+height)*scale;row++)for(let col=x*scale;col<(x+width)*scale;col++){
          const at=row*result.bytesPerRow+col*4,[r,g,b,a]=result.bytes.slice(at,at+4);
          if(r===255&&g===255&&b===255&&a===255)white++;
          else if(r===0&&g===0&&b===0&&a===255)black++;
          else if(r===g&&g===b&&a===255){partial++;values.add(r);}
          else throw new Error('unexpected single-sample edge color');}
        return{partial,white,black,values:[...values].sort((a,b)=>a-b)};});}
    try{const source=await(await fetch('./shader.wgsl')).text();renderer.replace(await renderer.prepare(source));
      const first=await coverage(),initial=owned(),uploads=renderer.resources.uploads,count=textures.length;
      renderer.replace(await renderer.prepare(source));const replaced=await coverage();renderer.rollback();const rolledBack=await coverage();
      const reused=textures.length===count&&renderer.resources.uploads===uploads;
      const reading=renderer.readPixels(scene);canvas.width=384;canvas.height=288;
      const resized=await coverage();await reading;
      const resizedOwned=owned(),replacedTargets=textures.slice(0,count).every(texture=>texture.destroyed===1);
      const fullResolution={width:canvas.width,height:canvas.height,insetPixels:renderer.resources.insetPixels,textures:renderer.resources.textures};
      await renderer.readPixels(picture);const omitted={owned:owned(),textures:renderer.resources.textures};
      const {hydrateFrame}=await import('./scene-tools.mjs');
      await renderer.readPixels(hydrateFrame(await(await fetch('./instances.json')).json()));
      const closing=renderer.readPixels(scene);await renderer.close();await closing;
      return{first,replaced,rolledBack,resized,initial,resizedOwned,reused,replacedTargets,fullResolution,omitted,
        closed:renderer.resources.closed&&renderer.resources.textures===0&&owned().length===0,
        destroyedOnce:textures.every(texture=>texture.destroyed===1),buffers:buffers.length,
        buffersDestroyedOnce:buffers.every(buffer=>buffer.destroyed===1),errors};
    }finally{await renderer.close();canvas.remove();}})()`);
  for(const view of [...singleSample.first,...singleSample.resized]){
    assert.ok(view.white>0&&view.black>0,'each view must contain foreground and background');
    assert.equal(view.partial,0,'single-sample edges have no fractional coverage');assert.deepEqual(view.values,[]);
  }
  assert.deepEqual(singleSample.replaced,singleSample.first);assert.deepEqual(singleSample.rolledBack,singleSample.first);
  const targets=scale=>[[128*scale,96*scale,1],
    ...[[48,40],[24,20],[16,18]].flatMap(([width,height])=>[[width*scale,height*scale,1],[width*scale,height*scale,1]])];
  assert.deepEqual(singleSample.initial,targets(2));assert.deepEqual(singleSample.resizedOwned,targets(3));
  assert.deepEqual(singleSample.fullResolution,{width:384,height:288,insetPixels:24192,textures:7});
  assert.deepEqual(singleSample.omitted,{owned:[[384,288,1]],textures:1});
  for(const flag of ['reused','replacedTargets','closed','destroyedOnce','buffersDestroyedOnce'])assert.equal(singleSample[flag],true,flag);
  assert.ok(singleSample.buffers>20,'track prototype, instance, prior, uniform and readback buffers');
  assert.deepEqual(singleSample.errors,[]);
  console.log('ok - single-sample main and three inset views retain hard edges at DPR 2/3, reuse targets and destroy every texture and buffer once');
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
