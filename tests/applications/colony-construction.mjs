// Direct construction commits ordinary paid orders through one typed absolute-cell command.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {MAP_WIDTH,MAP_HEIGHT,establishColony,colony,restoreColony,fixtureCall,routeCell,at} from './colony-state.mjs';

export async function checkConstructionOrders(test,fresh) {
  const state=r=>colony(r.snapshot(1));
  async function place(r,kind,cell,accepted) {
    const result=await r.dispatch(1,r.command('match','build-cell',[kind,cell]));
    assert.deepEqual(result.effects,[{kind:'send',owner:2,command:r.command('client','build-result',[cell,accepted ? 0 : kind < 1 || kind > 4 ? 15 : state(r).notice])}]);
  }
  await test('each construction kind pays and reserves exactly the same order as its direct command',async()=>{
    for(const [kind,name,x,y] of [[1,'extract',12,20],[2,'fortify',12,22],[3,'observe',12,22]]) {
      const direct=await fresh(),placed=await fresh(),cell=routeCell(state(placed),x,y);
      await fixtureCall(direct,name,[x,y]);await place(placed,kind,cell,1);
      assert.deepEqual(placed.snapshot(1),direct.snapshot(1));
      await placed.restore(1,placed.snapshot(1));await direct.close();await placed.close();
    }
  });
  await test('malformed construction kinds and absolute cells reject before spending or starting time',async()=>{
    const r=await fresh(),base=state(r),cell=routeCell(base,12,22);
    for(const kind of [-2147483648,-1,0,5,2147483647]) {
      await place(r,kind,cell,0);assert.deepEqual(state(r),base);
    }
    for(const invalid of [-2147483648,-1,MAP_WIDTH*MAP_HEIGHT,2147483647]) {
      await restoreColony(r,base);await place(r,3,invalid,0);
      assert.deepEqual(state(r),{...base,notice:15});
    }
    await r.close();
  });
  await test('construction orders retain hub, deposit and current visibility placement rules',async()=>{
    const r=await fresh(),base=state(r);base.surveys.unshift({...at(base,12,14),radius:10});
    for(const [kind,x,y,notice] of [[3,8,22,3],[1,12,22,4],[3,12,20,5],[3,12,11,1]]) {
      await restoreColony(r,base);await place(r,kind,routeCell(base,x,y),0);
      assert.deepEqual(state(r),{...base,notice});
    }
    await r.close();
  });
  await test('construction cells acknowledge individual success and retain prior orders when a later cell rejects',async()=>{
    const r=await fresh(),base=state(r);base.ore=50;base.spent=110;base.started=true;await restoreColony(r,base);
    await place(r,3,routeCell(base,10,22),1);await place(r,3,routeCell(base,11,22),1);
    const paid=state(r);assert.equal(paid.ore,0);assert.equal(paid.spent,160);assert.equal(paid.buildings.length,2);
    await place(r,3,routeCell(base,12,22),0);assert.deepEqual(state(r),{...paid,notice:7});
    await place(r,3,routeCell(base,10,22),0);assert.deepEqual(state(r),{...paid,notice:3});
    await r.restore(1,r.snapshot(1));await r.close();
  });
}

if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json')));
  const bytes=readFileSync(join(directory,manifest.module));
  const fresh=async()=>{const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);await r.initialize(2);return establishColony(r);};
  let count=0;await checkConstructionOrders(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},fresh);
  console.log(`${count} construction order checks passed`);
}
