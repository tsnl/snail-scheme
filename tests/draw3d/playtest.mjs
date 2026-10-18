// Actual Wasm presentation contracts for the hub, circular controls and meshes.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,client,at,siteAt,restoreColony,restoreClient,fixtureCall} from '../applications/colony-state.mjs';

const output=process.argv[2],manifest=JSON.parse(readFileSync(join(output,'manifest.json')));
const bytes=readFileSync(join(output,manifest.module));
async function fresh() {
  const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);r.uiBridge.resize(936,608);return r;
}
const world=r=>colony(r.snapshot(1)),local=r=>client(r.snapshot(2));
async function apply(r,action) {
  const result=await r.dispatch(action.owner,action.command);
  for(const effect of result.effects)if(effect.kind==='send')await apply(r,{owner:effect.owner,command:r.effectCommand(effect)});
}
const command=(r,name,args=[])=>{if(name==='viewport')r.uiBridge.resize(args[0]-24,args[1]-32);return apply(r,{owner:2,command:r.command('client',name,args)});};
function node(r,key,value=r.view().ui) {
  if(value.key===key)return value;
  for(const child of value.children){const found=node(r,key,child);if(found)return found;}
}
async function complete(r) {
  for(let tick=0;tick<600&&world(r).buildings.some(site=>site.stage!==2);tick++)await fixtureCall(r,'advance');
  assert.ok(world(r).buildings.every(site=>site.stage===2));
}
function project(r,x,y,z=0) {
  ({x,y}=at(world(r),x,y));const m=r.view().scene.uniforms,s=local(r);
  return[Math.round((m[0]*x-m[4]*y+m[8]*z+m[12]+1)*s.width/2),
    Math.round((1-(m[1]*x-m[5]*y+m[9]*z+m[13]))*s.height/2)];
}
const batch=(r,key)=>r.view().scene.batches.find(value=>value.key===key);
const points=batch=>Array.from({length:batch.vertices.length/10},(_,index)=>batch.vertices.slice(index*10,index*10+3));

{
  const r=await fresh();
  try {
    const initial=r.snapshot(1),hub=at(world(r),8,22);
    for(let y=21;y<=23;y++)for(let x=7;x<=9;x++) {
      await command(r,'move',project(r,x,y));await command(r,'confirm');
      assert.deepEqual([local(r).targetX,local(r).targetY],[hub.x,hub.y]);
      assert.match(node(r,'context-title').text,/hub/i);assert.ok(node(r,'repair')&&node(r,'worker'));
      assert.deepEqual(node(r,'worker').action.command,r.command('client','hire'));
      assert.equal(node(r,'close-context'),undefined);
    }
    assert.deepEqual(r.snapshot(1),initial);
    const damaged=world(r);damaged.hull=200;await restoreColony(r,damaged);
    assert.match(node(r,'context-description').text,/Repair to 100% · 50 ore/);
    assert.deepEqual(node(r,'repair').action.command,r.command('client','repair'));await apply(r,node(r,'repair').action);
    assert.equal(world(r).ore,110);assert.ok(world(r).bots.some(bot=>[12,13].includes(bot.job)&&bot.target===50));
    await r.restore(1,initial);const limited=world(r);limited.hull=100;limited.ore=30;limited.spent=130;limited.started=true;await restoreColony(r,limited);
    assert.match(node(r,'context-description').text,/Repair to 53% · 30 ore/);await apply(r,node(r,'repair').action);assert.equal(world(r).ore,0);
    await r.restore(1,initial);await command(r,'dismiss');
    await command(r,'worker-menu');assert.deepEqual(r.snapshot(1),initial);
    assert.deepEqual(node(r,'worker').action.command,r.command('client','hire'));
    await apply(r,node(r,'worker').action);await apply(r,node(r,'worker').action);
    assert.equal(world(r).ore,110);assert.equal(local(r).chooser,false);
    assert.match(node(r,'workers').help,/queued: 2/);
    const hired=r.snapshot(1);await command(r,'fabricate');assert.deepEqual(r.snapshot(1),hired);
    await command(r,'dismiss');
    for(const [width,height] of [[1100,760],[390,844],[640,360],[568,320],[320,568],[360,640]]) {
      await command(r,'viewport',[width,height]);
      for(const key of ['ore','health','workers','difficulty','home','pause','worker-menu','rotate-left','rotate-right'])
        assert.deepEqual(node(r,key).rect.slice(2),[56,56],`${key} circle at ${width}×${height}`);
      assert.equal(node(r,'ore').text,'');assert.match(node(r,'ore-readout-label').text,/110 ore/);
      assert.equal(node(r,'health').properties[3],300);assert.equal(node(r,'health').properties[5],300);
    }
    console.log('ok - every hub tile selects the same hub; worker panel opens without charging and hiring repeats; all main circles have one diameter');
  } finally {await r.close();}
}
{
  const r=await fresh();
  try {
    await fixtureCall(r,'fortify',[13,22]);await complete(r);
    await fixtureCall(r,'fortify',[15,22]);await complete(r);
    await restoreClient(r,{...local(r),scale:2000});
    const guns=world(r).buildings,covered=new Set();
    for(const gun of guns)for(let y=gun.y-6;y<=gun.y+6;y++)for(let x=gun.x-6;x<=gun.x+6;x++)
      if((x-gun.x)**2+(y-gun.y)**2<=36)covered.add(`${x},${y}`);
    const expected=[];
    for(const cell of covered){const [x,y]=cell.split(',').map(Number);
      for(const [dx,dy] of [[-1,0],[1,0],[0,-1],[0,1]])
        if(!covered.has(`${x+dx},${y+dy}`))expected.push(`${x*2+dx},${-(y*2+dy)}`);}
    const frame=batch(r,4),vertices=points(frame),actual=[];
    for(let index=0;index<vertices.length;index+=4){const face=vertices.slice(index,index+4);
      actual.push([0,1].map(axis=>Math.round(Math.min(...face.map(v=>v[axis]))+Math.max(...face.map(v=>v[axis])))).join(','));}
    assert.deepEqual(actual.sort(),expected.sort());assert.equal(new Set(actual).size,actual.length);
    const cooling=world(r);cooling.buildings[0].cooldown=8;await restoreColony(r,cooling);
    assert.equal(batch(r,4),frame,'cooldown preserves gun coverage and its retained mesh');
    assert.ok(r.view().scene.batches.filter(value=>value.reveal).every(value=>value.reveal.edge===0));
    console.log('ok - active-gun coverage is the exact grid union without internal or duplicate edges; cooldown retains it');
  } finally {await r.close();}
}
{
  const r=await fresh();
  try {
    for(const [x,y] of [[13,24],[14,24],[15,25]]){await fixtureCall(r,'build-wall',[x,y]);await complete(r);}
    assert.equal(batch(r,8).vertices.length/10,48,'one cardinal and one diagonal shield panel');
    await fixtureCall(r,'build-wall',[14,25]);await complete(r);
    assert.equal(batch(r,8).vertices.length/10,72,'cardinal corner replaces the redundant diagonal');
    const opaque=batch(r,13),glass=batch(r,8),terrain=batch(r,1),rails=batch(r,2),next=world(r);
    next.tick++;next.ore++;next.delivered++;next.produced++;await restoreColony(r,next);
    assert.equal(batch(r,13),opaque);assert.equal(batch(r,8),glass);
    assert.equal(batch(r,1),terrain);assert.equal(batch(r,2),rails);
    console.log('ok - cardinal and diagonal walls join as thin panels; unchanged topology retains both wall meshes');
  } finally {await r.close();}
}
{
  const r=await fresh();
  try {
    await fixtureCall(r,'observe',[12,22]);await complete(r);
    const tracks=world(r).tracks.slice(),railMesh=batch(r,2);
    await fixtureCall(r,'fortify',[10,22]);await complete(r);
    assert.equal(siteAt(world(r),10,22).kind,2);assert.deepEqual(world(r).tracks,tracks);
    assert.equal(batch(r,2),railMesh,'building atop the route retains the entire physical rail mesh');
    const gun=siteAt(world(r),10,22),vertices=points(batch(r,3));
    assert.ok(vertices.some(([x,y,z])=>Math.abs(x-gun.x)<.5&&Math.abs(y+gun.y)<.5&&z>1.8),
      'the gun body is raised over the continuous track');
    console.log('ok - artillery can occupy an existing railway with a raised body and unchanged rail geometry');
  } finally {await r.close();}
}

{
  const r=await fresh();
  try {
    const committed=r.snapshot(1),base=r.view().scene;
    const expected=[-.5,.6,-1].map(value=>value/Math.hypot(.5,.6,1));
    function fixedLight(heading) {
      assert.equal(local(r).heading,heading);const frame=r.view().scene,m=frame.uniforms,light=m.slice(16,19);
      for(let axis=0;axis<3;axis++) {
        const row=[m[axis],m[axis+4],m[axis+8]],length=Math.hypot(...row);
        const value=row.reduce((sum,part,index)=>sum+part*light[index],0)/length;
        assert.ok(Math.abs(value-expected[axis])<.00001,`camera-space light axis ${axis} at ${heading}`);
      }
      for(const key of [0,3,8,13])assert.equal(frame.batches.find(b=>b.key===key),base.batches.find(b=>b.key===key));
      assert.deepEqual(r.snapshot(1),committed);
    }
    fixedLight(0);await command(r,'rotate',[0,1]);
    for(let i=0;i<3;i++)await command(r,'animate',[50]);fixedLight(45000);
    for(let i=0;i<3;i++)await command(r,'animate',[50]);fixedLight(90000);
    await command(r,'rotate',[0,1]);for(let i=0;i<6;i++)await command(r,'animate',[50]);fixedLight(180000);
    console.log('ok - lighting stays fixed in camera space through intermediate and quarter turns; retained geometry and World are unchanged');
  } finally {await r.close();}
}
{
  const r=await fresh();
  try {
    const initial=world(r),hub=at(initial,8,22),other=at(initial,14,22);
    initial.started=true;initial.tick=100;
    initial.alerts=[{...hub,kind:0,tick:100},{...other,kind:3,tick:100}];await restoreColony(r,initial);
    const key=alert=>(alert.x+alert.y*384)*8+alert.kind;
    const first=key(initial.alerts[0]),second=key(initial.alerts[1]),before=r.snapshot(1);
    assert.ok(node(r,`attack-dismiss-${first}`)&&node(r,`attack-inspect-${second}`));
    await command(r,'dismiss-attack',[first]);assert.deepEqual(r.snapshot(1),before);
    assert.equal(node(r,`attack-toast-${first}`),undefined);assert.ok(node(r,`attack-toast-${second}`));
    assert.deepEqual(local(r).dismissed,[{key:first,until:180}]);
    const hidden=r.snapshot(2);
    for(const invalid of [-1,first+6,first+7,384*288*8,2147483647]){await command(r,'dismiss-attack',[invalid]);assert.deepEqual(r.snapshot(2),hidden);}
    const repeated=world(r);repeated.tick=101;repeated.alerts=repeated.alerts.map(alert=>({...alert,tick:101}));await restoreColony(r,repeated);
    assert.equal(node(r,`attack-toast-${first}`),undefined,'a repeat hit does not immediately undo dismissal');
    const nearby=world(r);nearby.alerts[0]={...nearby.alerts[0],x:hub.x+2,kind:4};await restoreColony(r,nearby);
    assert.equal(node(r,`attack-toast-${key(nearby.alerts[0])}`),undefined,'nearby worker damage shares the dismissed area');
    assert.ok(node(r,`attack-toast-${second}`),'damage beyond the coalescing radius remains visible');
    const nearbyWorld=r.snapshot(1);await command(r,'dismiss-attack',[first]);
    assert.deepEqual(local(r).dismissed,[{key:first,until:181}],'a valid rendered key still dismisses its area after nearby damage refreshes the toast');
    assert.deepEqual(r.snapshot(1),nearbyWorld);await r.restore(2,hidden);
    const expired=world(r);expired.tick=180;expired.alerts=expired.alerts.map(alert=>({...alert,tick:180}));await restoreColony(r,expired);
    assert.ok(node(r,`attack-toast-${key(expired.alerts[0])}`));assert.deepEqual(r.snapshot(2),hidden,'expiry is a pure view decision');
    await command(r,'dismiss-attack',[second]);assert.deepEqual(local(r).dismissed,[{key:second,until:260}]);
    const saved=r.snapshot(2);await r.restore(2,saved);assert.deepEqual(r.snapshot(2),saved);
    for(const dismissed of [[{key:first,until:-1}],[{key:7,until:260}],Array.from({length:5},(_,i)=>({key:i*8,until:260})),[{key:first,until:260},{key:first,until:261}]]) {
      await assert.rejects(restoreClient(r,{...local(r),dismissed}));assert.deepEqual(r.snapshot(2),saved);
    }
    await command(r,'center');assert.deepEqual(local(r).dismissed,[],'resetPresentation clears local dismissal history');
    const areas=Array.from({length:5},(_,i)=>({x:hub.x+i*6,y:hub.y,kind:i%5,tick:181+i}));
    for(const alert of areas) {
      const next=world(r);next.tick=alert.tick;next.alerts=[alert];await restoreColony(r,next);
      const committed=r.snapshot(1);await command(r,'dismiss-attack',[key(alert)]);assert.deepEqual(r.snapshot(1),committed);
    }
    assert.deepEqual(local(r).dismissed,areas.slice(1).reverse().map(alert=>({key:key(alert),until:alert.tick+80})),
      'a fifth area evicts the oldest dismissal while keeping four recent areas');
    const afterEviction=world(r);afterEviction.alerts=[areas[0],areas[4]].map(alert=>({...alert,tick:185}));await restoreColony(r,afterEviction);
    assert.ok(node(r,`attack-toast-${key(areas[0])}`));assert.equal(node(r,`attack-toast-${key(areas[4])}`),undefined);
    const afterExpiry=world(r);afterExpiry.tick=265;afterExpiry.alerts=[{...hub,x:hub.x+36,kind:3,tick:265}];await restoreColony(r,afterExpiry);
    await command(r,'dismiss-attack',[key(afterExpiry.alerts[0])]);
    assert.deepEqual(local(r).dismissed,[{key:key(afterExpiry.alerts[0]),until:345}],'a new dismissal prunes expired areas');
    await command(r,'center');assert.deepEqual(local(r).dismissed,[]);
    console.log('ok - attack dismissal is local, follows shared area proximity, expires, and retains only four recent areas');
  } finally {await r.close();}
}

{
  const r=await fresh();
  try {
    const w=world(r),target=at(w,12,22),hub=at(w,8,22);
    w.alerts=[0,1,4].map((kind,index)=>({x:hub.x+index*2,y:hub.y,kind,tick:w.tick}));await restoreColony(r,w);
    for(const [width,height]of[[320,568],[390,844],[568,320],[640,360]])for(const leftHanded of [false,true]) {
      await command(r,'viewport',[width,height]);
      await restoreClient(r,{...local(r),chooser:true,targetX:target.x,targetY:target.y,cursorX:target.x,cursorY:target.y,leftHanded});
      const before=project(r,12,22),wanted=[leftHanded?40:width-40,height-110];
      await command(r,'drag',wanted.map((value,index)=>value-before[index]));const point=project(r,12,22);
      const card=node(r,'context');assert.ok(card);const origin=[];
      function place(value,x=0,y=0){x+=value.rect[0];y+=value.rect[1];if(value.key==='context')origin.push(x+12,y+12);for(const child of value.children)place(child,x,y);}
      place(r.view().ui);const rect=[...origin,...card.rect.slice(2)];
      assert.ok(point[0]<rect[0]||point[0]>rect[0]+rect[2]||point[1]<rect[1]||point[1]>rect[1]+rect[3],'selected tile remains outside its popup');
      for(const inset of r.view().scene.insets??[]) {
        const value=inset.rect;assert.ok(point[0]<value[0]||point[0]>value[0]+value[2]||point[1]<value[1]||point[1]>value[1]+value[3],'attack thumbnail does not cover the selected tile');
      }
      function inspect(value,x=0,y=0){x+=value.rect[0];y+=value.rect[1];if(value.key.startsWith('attack-toast-'))assert.ok(point[0]<x+12||point[0]>x+12+value.rect[2]||point[1]<y+12||point[1]>y+12+value.rect[3],'attack card leaves the second-tap target clear');for(const child of value.children)inspect(child,x,y);}
      inspect(r.view().ui);
    }
    console.log('ok - narrow mirrored popups and attack cards leave the selected tile available for its second tap');
  } finally {await r.close();}
}

{
  const r=await fresh();
  try {
    const initial=world(r),hub=at(initial,8,22);
    for(const outcome of [1,3])for(const [width,height]of[[320,568],[568,320]])for(const leftHanded of [false,true]) {
      const ended={...initial,outcome,started:true,hull:outcome===1?0:300,nestHp:outcome===3?0:1500,
        alerts:[0,1,4].map((kind,index)=>({x:hub.x+index*2,y:hub.y,kind,tick:initial.tick}))};
      await restoreColony(r,ended);await command(r,'viewport',[width,height]);await restoreClient(r,{...local(r),chooser:false,leftHanded});
      const boxes=new Map();function gather(value,x=0,y=0){x+=value.rect[0];y+=value.rect[1];boxes.set(value.key,[x,y,value.rect[2],value.rect[3]]);for(const child of value.children)gather(child,x,y);}
      gather(r.view().ui);const result=boxes.get('result');assert.ok(result);assert.equal(node(r,'restart').properties[1],1);
      for(const [key,toast]of boxes)if(key.startsWith('attack-toast-'))assert.ok(toast[0]+toast[2]<=result[0]||result[0]+result[2]<=toast[0]||toast[1]+toast[3]<=result[1]||result[1]+result[3]<=toast[1],'alerts leave the always-visible outcome card and Restart clear');
    }
    console.log('ok - victory and defeat cards reserve their space from attack alerts without an active selection');
  } finally {await r.close();}
}
