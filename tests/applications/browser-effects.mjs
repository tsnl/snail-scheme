// The real browser FIFO and LocalState use tiny linked Wasm messages. Only the
// storage completion and browser presentation surface are controlled here.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {LocalState} from '../../src/application/local.mjs';
import {BrowserApplication} from '../../src/browser/application.mjs';

const handler=(binding,slot,arity)=>({binding,id:binding,slot,payload:Array(arity).fill('I32')});
const contract={version:1,applications:[
  {owner:'match',schema:1,handlers:[handler('build-cell',0,2)]},
  {owner:'client',schema:1,handlers:[handler('done',0,0),handler('plan-result',1,2),handler('plan-settled',2,1),handler('incoming',3,0),handler('invalid',4,0)]},
]};
function deferred() {
  let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});
  return {promise,resolve,reject};
}
async function host(bytes,commit=()=>{}) {
  const runtime=new ReducerRuntime();await runtime.replace(runtime.prepare(bytes,contract));
  await runtime.initialize(1);await runtime.initialize(2);
  const events=[],app=Object.assign(Object.create(BrowserApplication.prototype),{
    runtime,updates:Promise.resolve(),closing:false,localWork:0,dirty:false,
    note:()=>{},report:error=>events.push(['error',error.message]),
  });
  const dispatch=runtime.dispatch.bind(runtime);
  runtime.dispatch=async(owner,command,...options)=>{
    const result=await dispatch(owner,command,...options);
    if(owner===2)events.push([command.handler,...command.args]);return result;
  };
  const local=new LocalState(runtime,{commit,publish:output=>app.queueEffects(output.effects)});
  app.session={submit:command=>local.submit(command)};
  return {app,runtime,local,events};
}
const state=r=>Array.from(r.snapshot(2));

export async function checkBrowserEffects(test,fixture) {
  const bytes=fixture('browser-effects');
  await test('durable replies precede authored settlements and queued incoming Client actions remain ordered',async()=>{
    const entered=deferred(),saved=deferred();let writes=0;
    const {app,runtime,events}=await host(bytes,()=>{if(++writes===1){entered.resolve();return saved.promise;}});
    const done=app.local('done');await entered.promise;assert.equal(app.dirty,true,'committed Client progress can render while its World effect saves');
    const incoming=app.local('incoming'),repeat=app.local('done');
    assert.equal(runtime.snapshot(1)[1],0);assert.deepEqual(state(runtime),[1,3,0,0,1,0]);
    assert.deepEqual(events,[['done']]);saved.resolve();await Promise.all([done,incoming,repeat]);await app.drainUpdates();
    assert.equal(runtime.snapshot(1)[1],3);assert.deepEqual(state(runtime),[1,0,7,7,1,1]);
    assert.deepEqual(events,[['done'],['incoming'],['done'],['plan-result',1,1],['plan-settled',1],
      ['plan-result',2,1],['plan-settled',2],['plan-result',4,1],['plan-settled',4]]);await app.close();
  });
  await test('failed first, middle, last and all saves settle every cell before a fresh plan can begin',async()=>{
    for(const failures of [[1],[2],[3],[1,2,3]]) {
      let writes=0;const {app,runtime,local,events}=await host(bytes,()=>{if(failures.includes(++writes))throw new Error('storage offline');});
      await app.local('done');await app.drainUpdates();
      assert.equal(local.revision,3-failures.length);assert.equal(runtime.snapshot(1)[1],3-failures.length);
      assert.deepEqual(state(runtime),[1,0,7-failures.reduce((sum,index)=>sum+2**(index-1),0),7,1,0]);
      const expected=[['done']];
      for(const [index,cell] of [1,2,4].entries()) {
        if(!failures.includes(index+1))expected.push(['plan-result',cell,1]);expected.push(['plan-settled',cell]);
      }
      expected.push(['error',failures.map(()=>'storage offline').join('; ')]);assert.deepEqual(events,expected);
      events.length=0;await app.local('done');await app.drainUpdates();
      assert.equal(local.revision,6-failures.length);assert.deepEqual(state(runtime),[1,0,7,7,2,0]);
      assert.deepEqual(events,[['done'],['plan-result',1,1],['plan-settled',1],['plan-result',2,1],['plan-settled',2],
        ['plan-result',4,1],['plan-settled',4]]);await app.close();
    }
  });
  await test('a rejected World dispatch still drains authored settlements and following valid sends',async()=>{
    const {app,runtime,local,events}=await host(bytes);await app.local('invalid');await app.drainUpdates();
    assert.equal(local.revision,2);assert.equal(runtime.snapshot(1)[1],2);assert.deepEqual(state(runtime),[1,0,5,3,1,0]);
    assert.deepEqual(events.slice(0,-1),[['invalid'],['plan-result',1,1],['plan-settled',1],['plan-settled',-2],
      ['plan-result',4,1],['plan-settled',4]]);assert.equal(events.at(-1)[0],'error');assert.match(events.at(-1)[1],/unreachable/);
    await app.close();
  });
  await test('compatible replacement preserves a pending plan before queued replies and settlements drain',async()=>{
    const entered=deferred(),saved=deferred();let writes=0;
    const {app,runtime}=await host(bytes,()=>{if(++writes===1){entered.resolve();return saved.promise;}});
    const done=app.local('done');await entered.promise;
    const replacement=app.update(async()=>{
      assert.equal(runtime.snapshot(2)[1],3);await runtime.replace(runtime.prepare(bytes,contract));
      assert.equal(runtime.snapshot(2)[1],3);
    });
    saved.resolve();await Promise.all([done,replacement]);await app.drainUpdates();
    assert.deepEqual(state(runtime),[1,0,7,7,1,0]);await app.close();
  });
  await test('closing drains admitted UI orders and replies published by an independent pending World save',async()=>{
    for(const fromClient of [true,false]) {
      const entered=deferred(),saved=deferred();let writes=0;
      const {app,runtime,events}=await host(bytes,()=>{if(++writes===1){entered.resolve();return saved.promise;}});
      const pending=fromClient?app.local('done'):app.session.submit(runtime.command('match','build-cell',[1,1]));
      await entered.promise;const closing=app.close();
      await assert.rejects(app.update(()=>{}),/closing/);saved.resolve();await Promise.all([pending,closing]);
      await assert.rejects(runtime.dispatch(2,runtime.command('client','incoming')),/closing/);
      assert.deepEqual(events,fromClient?[['done'],['plan-result',1,1],['plan-settled',1],['plan-result',2,1],
        ['plan-settled',2],['plan-result',4,1],['plan-settled',4]]:[['plan-result',1,1]]);
    }
  });
  await test('deferred error text describes the current clock after later saves recover',async()=>{
    const messages=[],app={reconcileGeneration:()=>{},note:text=>messages.push(text),session:{faulted:true}};
    BrowserApplication.prototype.report.call(app,new Error('storage offline'));assert.match(messages.at(-1),/clock stopped.*Retry.*reload/);
    app.session.faulted=false;BrowserApplication.prototype.report.call(app,new Error('storage offline'));
    assert.doesNotMatch(messages.at(-1),/clock stopped/);
  });
}

if(process.argv[1]===import.meta.filename) {
  const directory=resolve(process.argv[2]);let count=0;
  await checkBrowserEffects(async(name,run)=>{await run();console.log(`ok ${++count} - ${name}`);},name=>readFileSync(join(directory,`${name}.wasm`)));
  console.log(`${count} browser effect checks passed`);
}
