// Actual Wasm HUD values, discovery and camera projection for finite deposits.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony,client,establishColony,restoreColony,restoreClient,fixtureCall,siteAt} from '../applications/colony-state.mjs';

const output=process.argv[2],manifest=JSON.parse(readFileSync(join(output,'manifest.json')));
const bytes=readFileSync(join(output,manifest.module));
async function fresh() {
  const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);
  r.uiBridge.resize(936,608);return establishColony(r);
}
const world=r=>colony(r.snapshot(1)),local=r=>client(r.snapshot(2));
function node(r,key,value=r.view().ui) {
  if(value.key===key)return value;
  for(const child of value.children){const found=node(r,key,child);if(found)return found;}
}
const badge=(r,cell)=>node(r,`deposit-ore-${cell}`);
function removeOre(world,cell,remaining) {
  const deposit=world.deposits.find(value=>value.cell===cell),removed=deposit.remaining-remaining;
  assert.ok(removed>=0);deposit.remaining=remaining;world.produced+=removed;world.lostOre+=removed;return world;
}
async function center(r,cell,changes={}) {
  await restoreClient(r,{...local(r),cameraX:(cell%128)*1000,cameraY:Math.floor(cell/128)*1000,homing:false,...changes});
}
function projectedTop(r,cell,z) {
  const m=r.view().scene.uniforms,x=cell%128,y=-Math.floor(cell/128),s=local(r);
  return [(m[0]*x+m[4]*y+m[8]*z+m[12]+1)*s.width/2,(1-m[1]*x-m[5]*y-m[9]*z-m[13])*s.height/2];
}
function checkAmount(r,cell,remaining,capacity,tone) {
  const value=badge(r,cell);assert.ok(value,'known onscreen deposit has an indicator');
  assert.equal(value.kind,4);assert.equal(value.properties[3],remaining);assert.equal(value.properties[5],capacity);
  assert.equal(value.properties[0],tone);assert.equal(value.text,remaining===0?'0 ore · Empty':`${remaining} ore`);
  assert.equal(value.action,undefined);return value;
}

{
  const r=await fresh();
  try {
    const original=r.snapshot(1),cell=world(r).deposits[0].cell;
    for(const [remaining,tone] of [[600,0],[61,0],[60,4],[1,4],[0,1]]) {
      await restoreColony(r,removeOre(colony(original),cell,remaining));
      const committed=r.snapshot(1);checkAmount(r,cell,remaining,600,tone);
      await r.dispatch(2,r.command('client','animate',[50]));assert.deepEqual(r.snapshot(1),committed);
    }
    const hud=node(r,'hud');assert.ok(hud.children.findIndex(value=>value.key===`deposit-ore-${cell}`)<hud.children.findIndex(value=>value.key==='rail'));
    console.log('ok - 600/61/60/1/0 ore shows exact units, a fixed 600-unit denominator, inclusive 10% danger and a distinct empty state');
  } finally {await r.close();}
}

{
  const r=await fresh();
  try {
    const initial=world(r),deposit=initial.deposits.find(value=>value.remaining>600),cell=deposit.cell,capacity=deposit.remaining;
    await center(r,cell);assert.equal(badge(r,cell),undefined,'an unseen deposit has no quantity or accessible label');
    const remembered=removeOre(initial,cell,capacity/10);remembered.surveys.push({x:cell%128,y:Math.floor(cell/128),radius:4});
    await restoreColony(r,remembered);checkAmount(r,cell,capacity/10,capacity,4);
    assert.ok(remembered.buildings.length===0&&remembered.bots.every(bot=>Math.hypot(bot.x/40-.5-cell%128,bot.y/40-.5-Math.floor(cell/128))>2),
      'the remembered deposit is outside current worker and building sight');
    const committed=r.snapshot(1);await center(r,0);assert.equal(badge(r,cell),undefined,'offscreen deposits never dock to a viewport edge');
    assert.deepEqual(r.snapshot(1),committed);
    console.log('ok - undiscovered deposits stay hidden; remembered deposits use their own seed capacity outside current sight and hide offscreen');
  } finally {await r.close();}
}

{
  const r=await fresh();
  try {
    await fixtureCall(r,'extract',[12,20]);
    for(let step=0;step<600&&siteAt(world(r),12,20).stage!==2;step++)await fixtureCall(r,'advance');
    assert.equal(siteAt(world(r),12,20).stage,2);
    const cell=world(r).deposits[0].cell;assert.equal(badge(r,cell).properties[5],600);
    await fixtureCall(r,'upgrade',[12,20]);
    for(let step=0;step<600&&siteAt(world(r),12,20).level!==2;step++)await fixtureCall(r,'advance');
    assert.equal(siteAt(world(r),12,20).level,2);
    await restoreColony(r,removeOre(world(r),cell,60));checkAmount(r,cell,60,600,4);
    const [x,y]=projectedTop(r,cell,.816),value=badge(r,cell);
    assert.ok(Math.abs(value.rect[0]+12+44-x)<=1);assert.ok(value.rect[1]+12+28<y,'occupied badge clears the extractor roof');
    console.log('ok - actual extractor construction and upgrade preserve the original denominator and lift the badge above its roof');
  } finally {await r.close();}
}

{
  const r=await fresh();
  try {
    const cell=world(r).deposits[0].cell,committed=r.snapshot(1);
    for(const [width,height] of [[1100,760],[390,844],[568,320],[320,568]])for(const heading of [0,90000,180000,270000])for(const scale of [500,1000,2000]) {
      r.uiBridge.resize(width-24,height-32);
      await center(r,cell,{width,height,heading,turnFrom:heading,turnTo:heading,turnElapsed:300,scale});
      const value=checkAmount(r,cell,600,600,0),[x,y]=projectedTop(r,cell,.56);
      assert.deepEqual(value.rect.slice(2),[88,28],'zoom retains readable screen-space dimensions');
      assert.ok(Math.abs(value.rect[0]+12+44-x)<=1);assert.ok(value.rect[1]+12+28<y,'badge remains above its crystal');
      assert.ok(value.rect[0]>=0&&value.rect[1]>=0&&value.rect[0]+88<=width-24&&value.rect[1]+28<=height-32);
    }
    assert.deepEqual(r.snapshot(1),committed);
    console.log('ok - ore badges keep fixed readable bounds above deposits through portrait, landscape, zoom and all camera turns');
  } finally {await r.close();}
}
