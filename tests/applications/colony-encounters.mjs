// Actual Wasm transitions at ownership and combat boundaries; these fixtures do
// not provide an alternate simulation or pathfinder.
import assert from 'node:assert/strict';
import {colony, colonyBalance, addEnemy, setWorker, restoreColony, at, pixelAt} from './colony-state.mjs';

export async function checkEncounters(test, fresh, call) {
  const state = r => colony(r.snapshot(1));
  const advance = async (r, count = 1) => { for (let i = 0; i < count; i++) await call(r, 'advance'); };
  function balanced(r) {
    const world = state(r), expected = colonyBalance(world);
    assert.equal(world.ore, expected.bank); assert.equal(world.produced, expected.raw);
  }
  async function builtMine(r) {
    await call(r, 'extract', [12,20]);
    for (let i = 0; i < 100 && state(r).buildings[0].stage !== 2; i++) await advance(r);
    assert.equal(state(r).buildings[0].stage, 2); return state(r).buildings[0];
  }
  async function cleanWorkers(r, assignments) {
    const world = state(r); world.bots.length = assignments.length;
    if (assignments.length === 1 && assignments[0].job === 6) world.casualties++;
    assignments.forEach((assignment, i) => setWorker(world, i, {...assignment, id:i+1}));
    await restoreColony(r, world);
  }
  await test('only physically occupied mining slots produce and upgrades add capacity', async () => {
    const r = await fresh(), mine = await builtMine(r);
    await cleanWorkers(r, [{job:6,timer:60}]);
    const before = state(r).produced; await advance(r, 10); assert.equal(state(r).produced, before);
    await call(r, 'upgrade', [12,20]); await advance(r, 10); assert.equal(state(r).produced, before);
    await cleanWorkers(r, [{x:12,y:20,job:9,target:mine.id}]);
    const arrival = state(r); arrival.tick=69; arrival.lastRevealTick=-100; await restoreColony(r, arrival); await advance(r);
    assert.equal(state(r).produced,before); assert.equal(state(r).bots[0].job,8);
    await advance(r, 10); assert.equal(state(r).produced, before + 2);
    await cleanWorkers(r, [{x:12,y:20,job:8,target:mine.id},{x:12,y:20,job:8,target:mine.id}]);
    await advance(r, 10); assert.equal(state(r).produced, before + 6); balanced(r);
    const bad = state(r); bad.buildings[0].level = 1; await assert.rejects(() => restoreColony(r, bad)); await r.close();
  });
  await test('a sole worker alternates mining and physical delivery without free ore', async () => {
    const r = await fresh(); await cleanWorkers(r, [{}]); await builtMine(r);
    let mining = false, loaded = false;
    for (let i = 0; i < 430; i++) {
      await advance(r); balanced(r); const bot = state(r).bots[0];
      mining ||= bot.job === 8; loaded ||= bot.job === 2 && bot.cargo > 0;
    }
    assert.ok(mining && loaded); assert.ok(state(r).delivered >= 32); assert.equal(state(r).bots.length, 1); await r.close();
  });
  await test('construction completion chains directly into nearby mining work', async () => {
    const r = await fresh(), mine = await builtMine(r);
    const position=pixelAt(state(r),12,20), builder = state(r).bots.find(bot => bot.x === position.x && bot.y === position.y);
    assert.equal(builder.job, 9);
    const assigned = state(r).bots.find(bot => bot.id === builder.id);
    assert.equal(assigned.job, 9); assert.equal(assigned.target, mine.id); assert.equal(assigned.x, position.x);
    await advance(r); assert.equal(state(r).bots.find(bot => bot.id === builder.id).job, 8); await r.close();
  });
  await test('a blocked home route triggers visible escape and work resumes after danger', async () => {
    const r = await fresh(), mine = await builtMine(r);
    await cleanWorkers(r, [{x:12,y:20,job:8,target:mine.id},{},{}]);
    await addEnemy(r, {x:10,y:20}); const bank = state(r).ore; await advance(r);
    let fleeing = state(r).bots.some(bot => bot.job === 7), away = false;
    for (let i = 0; i < 45; i++) { await advance(r); const bot = state(r).bots[0];
      const minePoint=pixelAt(state(r),12,20), threatPoint=pixelAt(state(r),10,20);
      fleeing ||= bot.job === 7; away ||= bot.x > minePoint.x || bot.y !== minePoint.y;
      assert.ok(Math.abs(bot.x - threatPoint.x) + Math.abs(bot.y - threatPoint.y) > 40); balanced(r);
    }
    assert.ok(fleeing && away); assert.equal(state(r).casualties, 0);
    const world = state(r); world.enemies.length = 0; await restoreColony(r, world); await advance(r, 220);
    assert.ok(state(r).produced > 0); assert.ok(state(r).ore >= bank); await r.close();
  });
  await test('worker death loses cargo once, records its location and assembles one replacement', async () => {
    const r = await fresh(); const world = state(r); world.bots.length = 1; world.started = true; world.tick = 9; world.lastRevealTick=-100;
    world.produced = 16; setWorker(world, 0, {id:1,x:12,y:20,job:7,cargo:16,timer:2}); await restoreColony(r, world);
    await addEnemy(r, {x:12,y:20}); await addEnemy(r, {x:12,y:20}); await advance(r);
    const dead = state(r); assert.equal(dead.casualties, 1); assert.equal(dead.lostOre, 16);
    assert.equal(dead.ore, 160); assert.equal(dead.bots.length, 1); assert.equal(dead.bots[0].job, 6);
    assert.equal(dead.bots[0].timer, 60); assert.deepEqual(dead.alerts.map(a => [a.x,a.y,a.kind]), [[at(dead,12,20).x,at(dead,12,20).y,4]]);
    const saved = r.snapshot(1); await r.restore(1, saved); await advance(r, 20);
    assert.equal(state(r).bots.length, 1); assert.equal(state(r).bots[0].timer, 40); assert.equal(state(r).casualties, 1);
    balanced(r); await r.close();
  });
  await test('a killed construction carrier cancels exactly its paid project without refund', async () => {
    const r = await fresh(); await call(r, 'observe', [12,20+1]); await advance(r);
    const before = state(r), carrier = before.bots.find(b => b.job === 3), world = state(r);
    const index = before.bots.findIndex(b => b.id === carrier.id);
    setWorker(world, index, {id:carrier.id,x:12,y:21,job:7,target:carrier.target,cargo:25,timer:5});
    world.tick = 9; world.lastRevealTick=-100; await restoreColony(r, world); await addEnemy(r, {x:12,y:21}); await addEnemy(r, {x:12,y:21}); await advance(r);
    assert.equal(state(r).buildings.length, 0); assert.equal(state(r).ore, 135); assert.equal(state(r).spent, 25);
    assert.equal(state(r).casualties, 1); await advance(r, 20); assert.equal(state(r).spent, 25); balanced(r); await r.close();
  });
  await test('ordinary enemies damage encountered infrastructure and coalesce actual-hit alerts', async () => {
    const r = await fresh(), mine = await builtMine(r), world = state(r); world.tick = 9; world.lastRevealTick=-100; world.buildings[0].hp = 7;
    setWorker(world,0,{id:1}); setWorker(world,1,{id:2}); setWorker(world,2,{id:3}); await restoreColony(r, world);
    await addEnemy(r, {x:12,y:20}); await advance(r);
    assert.equal(state(r).buildings.length, 0); assert.equal(state(r).lost, 1);
    assert.deepEqual(state(r).alerts.map(a => [a.x,a.y,a.kind]), [[at(world,12,20).x,at(world,12,20).y,1]]); balanced(r); await r.close();
  });
  await test('actual damage alerts remain bounded and retain destroyed-site locations', async () => {
    const r=await fresh(), sites=[[2,18],[16,18],[2,26],[16,26]];
    for(const site of sites) await call(r,'observe',site);
    for(let i=0;i<350 && state(r).buildings.some(b=>b.stage!==2);i++) await advance(r);
    assert.ok(state(r).buildings.every(b=>b.stage===2));
    await cleanWorkers(r,[{},{},{}]); const world = state(r); world.tick=9; world.lastRevealTick=-100; world.buildings[0].hp=1; await restoreColony(r, world);
    for(const [x,y] of sites) await addEnemy(r,{x,y}); await addEnemy(r,{x:8,y:22}); await advance(r);
    assert.equal(state(r).alerts.length,4); assert.equal(state(r).lost,1); assert.ok(state(r).alerts.some(a=>a.kind===0));
    assert.ok(state(r).alerts.every(a=>a.tick===10));
    const frozen=r.snapshot(1); await call(r,'pause-colony',[1]); await advance(r,90);
    assert.deepEqual(state(r).alerts,colony(frozen).alerts);
    await call(r,'pause-colony',[0]); const clear = state(r); clear.enemies.length=0; await restoreColony(r, clear); await advance(r,81);
    assert.doesNotMatch(r.view().label,/RECENT DAMAGE/); await r.close();
  });
  await test('same seeds reproduce maps and invalid seed orders retain the colony', async () => {
    const r = await fresh(); await call(r,'new-run-seed',[43]); const initial = r.snapshot(1);
    await call(r,'extract',[12,20]); await advance(r,170); assert.ok(state(r).delivered > 0);
    await call(r,'new-run-seed',[43]); const replay = colony(initial); replay.runMarker++;
    assert.deepEqual(state(r),replay);
    for (const seed of [0,-1,65536]) { const before=r.snapshot(1); await call(r,'new-run-seed',[seed]);
      const expected=colony(before); expected.notice=16; assert.deepEqual(state(r),expected); }
    await call(r,'new-run'); assert.equal(state(r).seed,44);
    for (const seed of [2,7,1337,65535]) { await call(r,'new-run-seed',[seed]); await builtMine(r); await advance(r,160);
      assert.ok(state(r).delivered>0); balanced(r); }
    const saved=r.snapshot(1); await r.restore(1,saved); assert.equal(state(r).seed,65535);
    const wrapping=colony(saved); wrapping.runMarker=2147483647; await restoreColony(r,wrapping); await call(r,'new-run');
    assert.equal(state(r).seed,1); assert.equal(state(r).runMarker,0);
    await r.close();
  });
}
