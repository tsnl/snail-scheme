// Actual Wasm transitions at ownership and combat boundaries; these fixtures do
// not provide an alternate simulation or pathfinder.
import assert from 'node:assert/strict';
import {colony, colonyBalance, addEnemy, setWorker} from './colony-state.mjs';

export async function checkEncounters(test, fresh, call) {
  const state = r => colony(r.snapshot(1));
  const advance = (r, count = 1) => { for (let i = 0; i < count; i++) call(r, 'advance'); };
  function balanced(r) {
    const world = state(r), expected = colonyBalance(world);
    assert.equal(world.ore, expected.bank); assert.equal(world.produced, expected.raw);
  }
  function builtMine(r) {
    call(r, 'extract', [12,20]);
    for (let i = 0; i < 100 && state(r).buildings[0].stage !== 2; i++) advance(r);
    assert.equal(state(r).buildings[0].stage, 2); return state(r).buildings[0];
  }
  function cleanWorkers(r, assignments) {
    const words = r.snapshot(1); words[8] = assignments.length;
    assignments.forEach((assignment, i) => setWorker(words, i, {...assignment, id:i+1}));
    r.restore(1, words);
  }
  await test('only physically occupied mining slots produce and upgrades add capacity', () => {
    const r = fresh(), mine = builtMine(r);
    cleanWorkers(r, [{job:6,timer:60},{job:6,timer:60},{job:6,timer:60}]);
    const before = state(r).produced; advance(r, 10); assert.equal(state(r).produced, before);
    call(r, 'upgrade', [12,20]); advance(r, 10); assert.equal(state(r).produced, before);
    cleanWorkers(r, [{x:12,y:20,job:9,target:mine.id},{job:6,timer:60},{job:6,timer:60}]);
    const arrival=r.snapshot(1); arrival[1]=69; r.restore(1,arrival); advance(r);
    assert.equal(state(r).produced,before); assert.equal(state(r).bots[0].job,8);
    advance(r, 10); assert.equal(state(r).produced, before + 2);
    cleanWorkers(r, [{x:12,y:20,job:8,target:mine.id},{x:12,y:20,job:8,target:mine.id},{job:6,timer:60}]);
    advance(r, 10); assert.equal(state(r).produced, before + 6); balanced(r);
    const bad = r.snapshot(1); bad[36] = 1; assert.throws(() => r.restore(1, bad)); r.close();
  });
  await test('a sole worker alternates mining and physical delivery without free ore', () => {
    const r = fresh(); cleanWorkers(r, [{}]); builtMine(r);
    let mining = false, loaded = false;
    for (let i = 0; i < 430; i++) {
      advance(r); balanced(r); const bot = state(r).bots[0];
      mining ||= bot.job === 8; loaded ||= bot.job === 2 && bot.cargo > 0;
    }
    assert.ok(mining && loaded); assert.ok(state(r).delivered >= 32); assert.equal(state(r).bots.length, 1); r.close();
  });
  await test('construction completion chains directly into nearby mining work', () => {
    const r = fresh(), mine = builtMine(r);
    const builder = state(r).bots.find(bot => bot.x === 500 && bot.y === 820);
    assert.equal(builder.job, 9);
    const assigned = state(r).bots.find(bot => bot.id === builder.id);
    assert.equal(assigned.job, 9); assert.equal(assigned.target, mine.id); assert.equal(assigned.x, 500);
    advance(r); assert.equal(state(r).bots.find(bot => bot.id === builder.id).job, 8); r.close();
  });
  await test('a blocked home route triggers visible escape and work resumes after danger', () => {
    const r = fresh(), mine = builtMine(r);
    cleanWorkers(r, [{x:12,y:20,job:8,target:mine.id},{},{}]);
    addEnemy(r, {x:10,y:20}); const bank = state(r).ore; advance(r);
    let fleeing = state(r).bots.some(bot => bot.job === 7), away = false;
    for (let i = 0; i < 45; i++) { advance(r); const bot = state(r).bots[0];
      fleeing ||= bot.job === 7; away ||= bot.x > 500 || bot.y !== 820;
      assert.ok(Math.abs(bot.x - 420) + Math.abs(bot.y - 820) > 40); balanced(r);
    }
    assert.ok(fleeing && away); assert.equal(state(r).casualties, 0);
    const words = r.snapshot(1); words[9] = 0; r.restore(1, words); advance(r, 220);
    assert.ok(state(r).produced > 0); assert.ok(state(r).ore >= bank); r.close();
  });
  await test('worker death loses cargo once, records its location and assembles one replacement', () => {
    const r = fresh(); const words = r.snapshot(1); words[8] = 1; words[1] = 9;
    words[14] = 16; setWorker(words, 0, {id:1,x:12,y:20,job:7,cargo:16,timer:2}); r.restore(1, words);
    addEnemy(r, {x:12,y:20}); addEnemy(r, {x:12,y:20}); advance(r);
    const dead = state(r); assert.equal(dead.casualties, 1); assert.equal(dead.lostOre, 16);
    assert.equal(dead.ore, 160); assert.equal(dead.bots.length, 1); assert.equal(dead.bots[0].job, 6);
    assert.equal(dead.bots[0].timer, 60); assert.deepEqual(dead.alerts.map(a => [a.x,a.y,a.kind]), [[12,20,4]]);
    const saved = r.snapshot(1); r.restore(1, saved); advance(r, 20);
    assert.equal(state(r).bots.length, 1); assert.equal(state(r).bots[0].timer, 40); assert.equal(state(r).casualties, 1);
    balanced(r); r.close();
  });
  await test('a killed construction carrier cancels exactly its paid project without refund', () => {
    const r = fresh(); call(r, 'observe', [12,20+1]); advance(r);
    const before = state(r), carrier = before.bots.find(b => b.job === 3), words = r.snapshot(1);
    const index = before.bots.findIndex(b => b.id === carrier.id);
    setWorker(words, index, {id:carrier.id,x:12,y:21,job:7,target:carrier.target,cargo:25,timer:5});
    words[1] = 9; r.restore(1, words); addEnemy(r, {x:12,y:21}); addEnemy(r, {x:12,y:21}); advance(r);
    assert.equal(state(r).buildings.length, 0); assert.equal(state(r).ore, 135); assert.equal(state(r).spent, 25);
    assert.equal(state(r).casualties, 1); advance(r, 20); assert.equal(state(r).spent, 25); balanced(r); r.close();
  });
  await test('ordinary enemies damage encountered infrastructure and coalesce actual-hit alerts', () => {
    const r = fresh(), mine = builtMine(r), words = r.snapshot(1); words[1] = 9; words[37] = 7;
    setWorker(words,0,{id:1}); setWorker(words,1,{id:2}); setWorker(words,2,{id:3}); r.restore(1, words);
    addEnemy(r, {x:12,y:20}); advance(r);
    assert.equal(state(r).buildings.length, 0); assert.equal(state(r).lost, 1);
    assert.deepEqual(state(r).alerts.map(a => [a.x,a.y,a.kind]), [[12,20,1]]); balanced(r); r.close();
  });
  await test('actual damage alerts remain bounded and retain destroyed-site locations', () => {
    const r=fresh(), sites=[[2,18],[16,18],[2,26],[16,26]];
    for(const site of sites) call(r,'observe',site);
    for(let i=0;i<350 && state(r).buildings.some(b=>b.stage!==2);i++) advance(r);
    assert.ok(state(r).buildings.every(b=>b.stage===2));
    cleanWorkers(r,[{},{},{}]); const words=r.snapshot(1); words[1]=9; words[37]=1; r.restore(1,words);
    for(const [x,y] of sites) addEnemy(r,{x,y}); addEnemy(r,{x:8,y:22}); advance(r);
    assert.equal(state(r).alerts.length,4); assert.equal(state(r).lost,1); assert.ok(state(r).alerts.some(a=>a.kind===0));
    assert.ok(state(r).alerts.every(a=>a.tick===10));
    const frozen=r.snapshot(1); call(r,'pause-colony',[1]); advance(r,90);
    assert.deepEqual(state(r).alerts,colony(frozen).alerts);
    call(r,'pause-colony',[0]); const clear=r.snapshot(1); clear[9]=0; r.restore(1,clear); advance(r,81);
    assert.doesNotMatch(r.view().label,/RECENT DAMAGE/); r.close();
  });
  await test('lost repair kits are spent once and never refunded by casualty cleanup', () => {
    const r=fresh(), words=r.snapshot(1); words[1]=9; words[3]=156; words[15]=4;
    setWorker(words,0,{id:1,x:12,y:20,job:7,cargo:4,timer:5}); r.restore(1,words);
    addEnemy(r,{x:12,y:20}); addEnemy(r,{x:12,y:20}); advance(r);
    assert.equal(state(r).casualties,1); assert.equal(state(r).ore,156); assert.equal(state(r).spent,4);
    advance(r,50); assert.equal(state(r).ore,156); assert.equal(state(r).spent,4); balanced(r); r.close();
  });
  await test('same seeds reproduce maps and invalid seed orders retain the colony', () => {
    const r = fresh(); call(r,'new-run-seed',[43]); const initial = r.snapshot(1);
    call(r,'extract',[12,20]); advance(r,170); assert.ok(state(r).delivered > 0);
    call(r,'new-run-seed',[43]); initial[23]++; assert.deepEqual(r.snapshot(1),initial);
    for (const seed of [0,-1,65536]) { const before=r.snapshot(1); call(r,'new-run-seed',[seed]);
      const after=r.snapshot(1); before[17]=16; assert.deepEqual(after,before); }
    call(r,'new-run'); assert.equal(state(r).seed,44);
    for (const seed of [2,7,1337,65535]) { call(r,'new-run-seed',[seed]); builtMine(r); advance(r,160);
      assert.ok(state(r).delivered>0); balanced(r); }
    const saved=r.snapshot(1); r.restore(1,saved); assert.equal(state(r).seed,65535);
    saved[23]=2147483647; r.restore(1,saved); call(r,'new-run');
    assert.equal(state(r).seed,1); assert.equal(r.snapshot(1)[23],0);
    r.close();
  });
}
