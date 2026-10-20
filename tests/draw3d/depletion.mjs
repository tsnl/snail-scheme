// Actual Wasm health/reserve fractions, visibility and camera-facing instances.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {MAP_WIDTH,colony,client,establishColony,restoreColony,restoreClient,fixtureCall,siteAt,pixelAt} from '../applications/colony-state.mjs';

const output=process.argv[2],manifest=JSON.parse(readFileSync(join(output,'manifest.json')));
const bytes=readFileSync(join(output,manifest.module));
async function fresh() {
  const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);
  r.uiBridge.resize(936,608);return establishColony(r);
}
const world=r=>colony(r.snapshot(1)),local=r=>client(r.snapshot(2));
const close=(a,b)=>Math.abs(a-b)<.0002,near=(a,b)=>a.every((value,index)=>close(value,b[index]));
const point=(m,p=[0,0,0])=>[0,4,8].map(row=>m[row]*p[0]+m[row+1]*p[1]+m[row+2]*p[2]+m[row+3]);
const width=m=>Math.hypot(m[0],m[4],m[8]);
const barBatches=r=>r.view().scene.batches.filter(batch=>batch.key===30||batch.key===31);
function bars(r) {
  return barBatches(r).flatMap(batch=>batch.draws.flatMap(draw=>Array.from({length:draw.count},(_,offset)=>{
    const index=draw.first+offset,vertices=draw.mesh.vertices,frame=vertices.length>40,color=vertices.slice(frame?46:6,frame?49:9);
    return{kind:color[1]>color[0]?'health':'reserve',frame,mesh:draw.mesh,
      matrix:batch.transforms.slice(index*12,index*12+12),before:batch.previous.slice(index*12,index*12+12)};
  })));
}
function fraction(r,anchor,kind) {
  const values=bars(r),frame=values.find(value=>value.frame&&value.kind===kind&&near(point(value.matrix),anchor));
  assert.ok(frame,`${kind} frame at ${anchor}`);
  const left=point(frame.matrix,[-.45,0,.006]);
  const fill=values.find(value=>!value.frame&&value.kind===kind&&near(point(value.matrix,[-.5,0,0]),left));
  return{frame,fill,value:fill?width(fill.matrix)/width(frame.matrix)/.9:0};
}
function removeOre(value,cell,remaining) {
  const deposit=value.deposits.find(item=>item.cell===cell),removed=deposit.remaining-remaining;
  assert.ok(removed>=0);deposit.remaining=remaining;value.produced+=removed;value.lostOre+=removed;return value;
}
async function center(r,cell,changes={}) {
  await restoreClient(r,{...local(r),cameraX:(cell%MAP_WIDTH)*1000,cameraY:Math.floor(cell/MAP_WIDTH)*1000,homing:false,...changes});
}
const depositPoint=cell=>[cell%MAP_WIDTH,-Math.floor(cell/MAP_WIDTH),.78];
function noOreLabels(node) {
  assert.ok(!node.key?.startsWith('deposit-ore-'));for(const child of node.children)noOreLabels(child);
}

{
  const r=await fresh();
  try {
    const original=r.snapshot(1),cell=world(r).deposits[0].cell;
    for(const remaining of [600,61,60,1,0]) {
      await restoreColony(r,removeOre(colony(original),cell,remaining));
      const committed=r.snapshot(1),amount=fraction(r,depositPoint(cell),'reserve');
      assert.ok(close(amount.value,remaining/600));assert.equal(!!amount.fill,remaining>0);
      for(const batch of barBatches(r)) {
        assert.equal(batch.opacity,1);assert.equal(batch.pulse,false);assert.equal(batch.unordered,true);
        assert.ok(batch.draws.length<=4,'all bars share two fixed frames and two fill meshes');
        assert.ok(batch.draws.every(draw=>draw.mesh.vertices.every((value,index)=>index%10!==9||value===1)),'unlit colors');
      }
      noOreLabels(r.view().ui);await r.dispatch(2,r.command('client','animate',[50]));assert.deepEqual(r.snapshot(1),committed);
    }
    console.log('ok - full/low/one/empty reserves retain purple frames, exact original fractions, no labels or pulse and four shared meshes');
  } finally {await r.close();}
}

{
  const r=await fresh();
  try {
    const initial=world(r),deposit=initial.deposits.find(value=>value.remaining>600),cell=deposit.cell,capacity=deposit.remaining;
    await center(r,cell);assert.ok(!bars(r).some(value=>value.frame&&value.kind==='reserve'&&near(point(value.matrix),depositPoint(cell))),'undiscovered reserves remain hidden');
    const remembered=removeOre(initial,cell,capacity/10);remembered.surveys.push({x:cell%MAP_WIDTH,y:Math.floor(cell/MAP_WIDTH),radius:4});
    await restoreColony(r,remembered);assert.ok(close(fraction(r,depositPoint(cell),'reserve').value,.1));
    const committed=r.snapshot(1);await center(r,0);assert.equal(bars(r).length,0,'offscreen bars never dock to the edge');
    assert.deepEqual(r.snapshot(1),committed);
    console.log('ok - unknown resources stay hidden; remembered deposits retain their own capacity and all bars cull outside the viewport');
  } finally {await r.close();}
}

{
  const r=await fresh();
  try {
    await fixtureCall(r,'extract',[12,20]);
    for(let step=0;step<600&&siteAt(world(r),12,20).stage!==2;step++)await fixtureCall(r,'advance');
    assert.equal(siteAt(world(r),12,20).stage,2);
    for(const level of [1,2]) {
      if(level===2){await fixtureCall(r,'upgrade',[12,20]);for(let step=0;step<600&&siteAt(world(r),12,20).level!==2;step++)await fixtureCall(r,'advance');}
      assert.equal(siteAt(world(r),12,20).level,level);
      const saved=r.snapshot(1),value=world(r),site=siteAt(value,12,20),cell=value.deposits[0].cell;site.hp=70;
      await restoreColony(r,removeOre(value,cell,60));const anchor=[site.x,-site.y,.816+.42];
      const health=fraction(r,anchor,'health');assert.ok(close(health.value,.5));
      const reserve=point(health.frame.matrix,[0,-.22,0]);assert.ok(close(fraction(r,reserve,'reserve').value,.1));
      assert.ok(reserve[2]>.816,'both bars clear the actual extractor roof');await r.restore(1,saved);
    }
    console.log('ok - worker-built level-one/two extractors pair green health above purple original-reserve fractions without changing the reserve');
  } finally {await r.close();}
}

{
  const r=await fresh();
  try {
    const value=world(r),hub=value.surveys.find(site=>site.radius===9),enemyPoint=pixelAt(value,8,20);
    value.hull=150;value.bots[0].hp=7;
    value.enemies=[{id:value.nextId++,...enemyPoint,hp:65,maxHp:130,kind:0,target:0,path:[],rank:0,burrower:false}];
    await restoreColony(r,value);
    assert.ok(close(fraction(r,[hub.x,-hub.y,.9+.06*.65+.22],'health').value,.5));
    const bot=value.bots[0],workerAnchor=[bot.x/40-.5+(bot.id%5)*.36-.72,.5-bot.y/40-1.7,.57+.22];
    assert.ok(close(fraction(r,workerAnchor,'health').value,.5),'workers use their actual 14-HP maximum');
    const enemyAnchor=[enemyPoint.x/40-.5,.5-enemyPoint.y/40,.85*.79+.22];
    assert.ok(close(fraction(r,enemyAnchor,'health').value,.5));
    const later=world(r);later.tick+=9000;await restoreColony(r,later);
    assert.ok(close(fraction(r,enemyAnchor,'health').value,.5),'difficulty never changes an existing enemy denominator');
    const remote=world(r),nest=remote.nests[0];nest.hp=450;remote.surveys.push({x:nest.x,y:nest.y,radius:4});
    await restoreColony(r,remote);await center(r,nest.x+MAP_WIDTH*nest.y);
    assert.ok(close(fraction(r,[nest.x,-nest.y,3.04],'health').value,.5));
    const dead=world(r);dead.nests[0].hp=0;await restoreColony(r,dead);
    assert.ok(!bars(r).some(bar=>bar.frame&&bar.kind==='health'&&near(point(bar.matrix),[nest.x,-nest.y,3.04])));
    const hidden=world(r);hidden.enemies[0].x=nest.x*40+20;hidden.enemies[0].y=nest.y*40+20;await restoreColony(r,hidden);
    assert.ok(!bars(r).some(bar=>bar.frame&&bar.kind==='health'&&near(point(bar.matrix),[nest.x,-nest.y,.85*.79+.22])),
      'remembered ground never reveals this enemy outside current sight, even when other entities fit the compact viewport');
    console.log('ok - hub, workers, visible enemies and live nests use health bars; enemy maxima stay fixed and hidden/dead enemies or nests expose none');
  } finally {await r.close();}
}

{
  const r=await fresh();
  try {
    await fixtureCall(r,'extract',[12,20]);await fixtureCall(r,'advance');
    const committed=r.snapshot(1),original=r.view().scene,body=original.batches.find(batch=>batch.key===3),meshes=new Set(bars(r).map(value=>value.mesh));
    for(const [width,height] of [[1100,760],[390,844]])for(const heading of [0,90000,180000,270000])for(const scale of [500,1000,2000]) {
      r.uiBridge.resize(width-24,height-32);const cell=world(r).deposits[0].cell;
      await center(r,cell,{width,height,heading,turnFrom:heading,turnTo:heading,turnElapsed:300,scale});
      const scene=r.view().scene,m=scene.uniforms,now=scene.batches.find(batch=>batch.key===3);
      assert.equal(now,body,'camera-only updates retain actor instances');
      for(const batch of barBatches(r))assert.equal(batch.motionClock,body.motionClock,'bars and actors share the same authoritative display interval');
      for(const bar of bars(r)) {
        assert.ok(meshes.has(bar.mesh),'camera changes reuse fixed bar meshes');
        const x=[bar.matrix[0],bar.matrix[4],bar.matrix[8]],y=[bar.matrix[1],bar.matrix[5],bar.matrix[9]];
        assert.ok(Math.abs(m[1]*x[0]+m[5]*x[1]+m[9]*x[2])<.00001,'bar width stays horizontal');
        assert.ok(Math.abs(m[0]*y[0]+m[4]*y[1]+m[8]*y[2])<.00001,'bar height stays vertical');
      }
    }
    assert.deepEqual(r.snapshot(1),committed);
    console.log('ok - desktop/portrait turns and zoom face every bar toward the camera, preserve meshes/body instances and share one motion epoch');
  } finally {await r.close();}
}
