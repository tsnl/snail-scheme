// Measure the realized seeded map after ground/opening filters, not candidate odds.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {loadWasm,instantiate,invokeEntry,closeInstance} from '../../src/lofi/compiler/execute.mjs';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony} from './colony-state.mjs';

const directory=resolve(process.argv[2]),manifest=JSON.parse(readFileSync(join(directory,'manifest.json')));
const bytes=readFileSync(join(directory,manifest.module)),probe=instantiate(loadWasm(readFileSync(process.argv[3])));
const seeds=[1,2,3,7,42,91,255,1024,8191,32767,65535,...Array.from({length:21},(_,i)=>1+((i+1)*1879)%65535)];
const totals=Array(6).fill(0),samples=[];
const query=(seed,operation)=>invokeEntry(probe,[seed,operation]);
const r=new ReducerRuntime();await r.replace(r.prepare(bytes,manifest));await r.initialize(1);
try{
  for(const seed of seeds){
    const fingerprint=query(seed,0),counts=Array.from({length:6},(_,index)=>query(seed,index+1));
    assert.equal(query(seed,0),fingerprint);counts.forEach((value,index)=>totals[index]+=value);
    const bonus=query(seed,7);assert.ok(bonus>=0&&bonus<=24);
    await r.dispatch(1,r.command('match','new-run-seed',[seed]));const world=colony(r.snapshot(1));
    assert.deepEqual(world.deposits.slice(0,3).map(d=>d.remaining),[600,900,1800]);
    assert.equal(new Set(world.deposits.map(d=>d.cell)).size,world.deposits.length);
    assert.ok(world.deposits.length<=46);assert.ok(world.deposits.every(d=>d.cell>=0&&d.cell<16384));
    const reserves=world.deposits.slice(-3);
    assert.deepEqual(reserves,world.nests.map(n=>({cell:n.x+n.y*128,remaining:2400})));
    const frontier=world.deposits.slice(-3-bonus,-3),hub=world.surveys[0];
    for(const d of frontier){
      const x=d.cell%128,y=Math.floor(d.cell/128),distance=Math.min(...world.nests.map(n=>(x-n.x)**2+(y-n.y)**2));
      assert.equal(d.remaining,600);assert.ok(distance>=36&&distance<=293);
      assert.ok((x-hub.x)**2+(y-hub.y)**2>400);
    }
    await r.dispatch(1,r.command('match','new-run-seed',[seed]));assert.deepEqual(colony(r.snapshot(1)).deposits,world.deposits);
    samples.push({seed,fingerprint,counts,bonus});
  }
  const density=[0,2,4].map(i=>totals[i+1]/totals[i]);
  assert.ok(density[0]>density[1]*3,'inner nest ground must be substantially denser than the approach ring');
  assert.ok(density[1]>density[2]*1.25,'approach ring must be denser than distant ground');
  assert.ok(density[0]>density[2]*5,'nest surroundings must guide exploration strongly');
  const report={seeds:seeds.length,totals,density,samples};
  if(process.argv[4])writeFileSync(process.argv[4],JSON.stringify(report,null,2)+'\n');
  console.log(`${seeds.length} deterministic maps checked; realized deposits per 1,000 ground cells: ${density.map(d=>(d*1000).toFixed(2)).join(' / ')} (inner / approach / distant)`);
}finally{await r.close();closeInstance(probe);}
