// Compiled Scheme owns every transition. Snapshot edits establish bounded
// encounter and cargo fixtures; there is no alternate routing or simulation.
import assert from 'node:assert/strict';
import {colony, colonyBalance, addEnemy, setWorker, setBuilding, setRail, restoreColony} from './colony-state.mjs';

export async function checkLogistics(test, fresh, call) {
  const state = r => colony(r.snapshot(1));
  function balanced(r) {
    const world = state(r), totals = colonyBalance(world);
    assert.equal(world.ore, totals.bank); assert.equal(world.produced, totals.raw);
    for (const site of world.buildings) {
      assert.equal(world.bots.filter(bot => bot.order === site.id).length, site.stage === 3 ? 1 : 0);
    }
  }
  async function advance(r, count = 1) {
    for (let i = 0; i < count; i++) { await call(r, 'advance'); balanced(r); }
  }
  async function until(r, predicate, limit = 300) {
    for (let i = 0; i < limit && !predicate(state(r)); i++) await advance(r);
    assert.ok(predicate(state(r)), 'the bounded scenario reached its expected state');
  }
  async function tower(r, x, y) {
    await call(r, 'observe', [x,y]);
    await until(r, world => world.buildings.some(b => b.x === x && b.y === y && b.stage === 2));
    return state(r).buildings.find(b => b.x === x && b.y === y);
  }
  async function loadedWorker(r) {
    const world = state(r); world.produced = 16;
    setWorker(world, 0, {x:12,y:20,job:2,cargo:16,path:[971,970,969,968,1016,1064]});
    setWorker(world, 1, {job:6,timer:30}); setWorker(world, 2, {job:6,timer:30});
    await restoreColony(r, world);
  }

  await test('cancel releases an uncollected reservation and refunds exactly once while paused', async () => {
    const r = await fresh(), prior = r.stores.get(1);
    await call(r, 'pause-colony', [1]); await call(r, 'observe', [12,21]);
    const reserved = state(r); assert.equal(reserved.buildings[0].stage, 3);
    assert.equal(reserved.bots[0].order, reserved.buildings[0].id); assert.equal(reserved.bots[0].cargo, 0);
    await call(r, 'cancel-building', [12,21]); balanced(r);
    assert.equal(state(r).ore, 160); assert.equal(state(r).spent, 0);
    assert.equal(state(r).rails.length, 0); assert.equal(state(r).buildings.length, 0);
    assert.ok(state(r).bots.every(bot => bot.order === 0));
    await call(r, 'cancel-building', [12,21]); assert.equal(state(r).ore, 160);
    assert.equal(state(r).notice, 19); assert.equal(colony(prior).ore, 160); assert.equal(colony(prior).buildings.length, 0);
    await r.close();
  });

  await test('cancelled carried kits stay physical through pause and restore before their refund', async () => {
    const r = await fresh(); await call(r, 'observe', [12,14]); await advance(r, 12);
    const carrier = state(r).bots.find(bot => bot.job === 3); assert.ok(carrier.x !== 340 || carrier.y !== 900);
    await call(r, 'cancel-building', [12,14]); assert.equal(state(r).ore, 135);
    assert.equal(state(r).buildings.length, 0); assert.equal(state(r).bots.find(b => b.id === carrier.id).cargo, 25);
    await call(r, 'pause-colony', [1]); const saved = r.snapshot(1); await r.restore(1, saved);
    await advance(r, 30); assert.deepEqual(r.snapshot(1), saved);
    await call(r, 'pause-colony', [0]); await until(r, world => world.spent === 0);
    assert.equal(state(r).ore, 160); await advance(r, 20); assert.equal(state(r).ore, 160);
    await r.close();
  });

  await test('construction keeps one kit owner and chooses completion time over proximity', async () => {
    const r = await fresh(); await call(r, 'extract', [12,20]); await advance(r, 100);
    const miner = state(r).bots.find(bot => bot.job === 8); assert.ok(miner);
    await call(r, 'observe', [13,20]); const project = state(r).buildings.find(b => b.kind === 3);
    const reserved = state(r).bots.find(bot => bot.order === project.id);
    assert.notEqual(reserved.id, miner.id); assert.ok([2,11].includes(reserved.job));
    assert.equal(project.stage, 3); balanced(r);
    await until(r, world => world.buildings.find(b => b.id === project.id).stage === 2);
    assert.ok(state(r).bots.every(bot => bot.order !== project.id)); await r.close();
  });

  await test('hub pickup makes the hub worker fastest even when another worker is near the site', async () => {
    const r = await fresh(); await tower(r, 12,14); await tower(r, 12,8);
    const world = state(r); setWorker(world, 0, {x:6,y:11});
    setWorker(world, 1, {x:10,y:9}); setWorker(world, 2); await restoreColony(r, world);
    await call(r, 'fortify', [6,9]); const project = state(r).buildings.find(b => b.x === 6 && b.y === 9);
    assert.ok(project); assert.equal(state(r).bots.find(bot => bot.order === project.id).id, 3);
    balanced(r); await r.close();
  });

  await test('a preempted loaded hauler delivers ore before collecting the reserved build kit', async () => {
    const r = await fresh(); await loadedWorker(r); await call(r, 'observe', [13,20]);
    const project = state(r).buildings[0], bot = state(r).bots[0];
    assert.equal(bot.order, project.id); assert.equal(bot.job, 2); assert.equal(bot.cargo, 16);
    await until(r, world => world.delivered === 16);
    assert.equal(state(r).buildings[0].stage, 1); assert.equal(state(r).bots[0].cargo, 25);
    await until(r, world => world.buildings[0].stage === 2);
    assert.equal(state(r).ore, 151); assert.equal(state(r).spent, 25); await r.close();
  });

  await test('cancelling a reserved project leaves its workers unrelated ore delivery intact', async () => {
    const r = await fresh(); await loadedWorker(r); const before = state(r).bots[0];
    await call(r, 'observe', [13,20]); await call(r, 'cancel-building', [13,20]);
    const after = state(r).bots[0]; assert.equal(after.order, 0);
    assert.deepEqual({...after, order:before.order}, before); assert.equal(state(r).ore, 160);
    await until(r, world => world.delivered === 16);
    assert.equal(state(r).ore, 176); assert.equal(state(r).spent, 0); await r.close();
  });

  await test('death releases an uncollected kit but loses a cancelled carried kit without refund', async () => {
    const r = await fresh(); await loadedWorker(r); await call(r, 'observe', [13,20]);
    const world = state(r); world.tick = 9; world.bots[0].hp = 7; await restoreColony(r, world);
    await addEnemy(r, {x:12,y:20}); await advance(r);
    assert.equal(state(r).casualties, 1); assert.equal(state(r).lostOre, 16);
    assert.equal(state(r).buildings[0].stage, 0); assert.equal(state(r).spent, 25);
    await call(r, 'cancel-building', [13,20]); assert.equal(state(r).ore, 160);
    await call(r, 'new-run-seed', [1]); await call(r, 'observe', [12,21]); await advance(r);
    await call(r, 'cancel-building', [12,21]); const cancelled = state(r); cancelled.tick = 9;
    setWorker(cancelled, 0, {x:12,y:21,job:7,cargo:25,timer:5,hp:7}); await restoreColony(r, cancelled);
    await addEnemy(r, {x:12,y:21}); await advance(r);
    assert.equal(state(r).casualties, 1); assert.equal(state(r).ore, 135); assert.equal(state(r).spent, 25);
    await advance(r, 20); assert.equal(state(r).ore, 135); await r.close();
  });

  await test('workers use a nearby connected depot and only rail arrival makes ore spendable', async () => {
    const r = await fresh(), depot = await tower(r, 12,21);
    await call(r, 'extract', [12,20]); let deposited = false, hauled = false;
    for (let i = 0; i < 300 && state(r).delivered < 16; i++) {
      const before = state(r);
      hauled ||= before.bots.some(bot => bot.job === 2 && bot.target === depot.id && bot.cargo > 0);
      await advance(r); const after = state(r);
      if (!deposited && after.buildings.find(b => b.id === depot.id).stock > before.buildings.find(b => b.id === depot.id).stock) {
        deposited = true; assert.equal(after.delivered, before.delivered);
      }
    }
    assert.ok(hauled && deposited); assert.ok(state(r).delivered >= 16); await r.close();
  });

  await test('tower placement fixes an upstream tree and freight traverses each link before credit', async () => {
    const r = await fresh(), parent = await tower(r, 12,21), child = await tower(r, 16,21);
    const links = state(r).rails; assert.equal(links.find(link => link.source === child.id).parent, parent.id);
    const world = state(r); world.produced = 32; setBuilding(world, 1, {stock:32}); await restoreColony(r, world);
    await advance(r); assert.equal(state(r).delivered, 0);
    const loaded = state(r).rails.find(link => link.source === child.id);
    assert.equal(loaded.cargo, 32); assert.equal(loaded.progress, 0);
    await call(r, 'pause-colony', [1]); const saved = r.snapshot(1), frame = r.view().scene;
    await r.restore(1, saved); await advance(r, 20);
    assert.deepEqual(r.snapshot(1), saved); assert.deepEqual(r.view().scene, frame);
    await call(r, 'pause-colony', [0]);
    await advance(r, 10); assert.equal(state(r).delivered, 0);
    assert.notDeepEqual(r.view().scene, frame);
    assert.equal(state(r).rails.find(link => link.source === parent.id).cargo, 32);
    assert.equal(state(r).rails.find(link => link.source === parent.id).progress, 0);
    await until(r, world => world.delivered === 32); const delivered = state(r).ore;
    await advance(r, 100); assert.equal(state(r).ore, delivered); assert.equal(state(r).delivered, 32);
    assert.deepEqual(state(r).rails.map(link => [link.source,link.parent,link.path]), links.map(link => [link.source,link.parent,link.path]));
    await r.close();
  });

  await test('arming retains tower sight, depot stock and route while firing without kill income', async () => {
    const r = await fresh(), towerSite = await tower(r, 12,21);
    await call(r, 'upgrade', [12,21]); const world = state(r); world.produced = 16;
    setBuilding(world, 0, {stock:16}); await restoreColony(r, world);
    const before = state(r); await call(r, 'arm-tower', [12,21]); const armed = state(r);
    assert.equal(armed.buildings[0].id, towerSite.id); assert.equal(armed.buildings[0].armed, 1);
    assert.equal(armed.buildings[0].kind, 3); assert.equal(armed.buildings[0].level, 2);
    assert.equal(armed.buildings[0].stock, 16); assert.deepEqual(armed.surveys, before.surveys);
    assert.deepEqual(armed.rails, before.rails); assert.equal(armed.ore, before.ore - 50);
    await addEnemy(r, {x:14,y:21,hp:20}); await advance(r);
    assert.equal(state(r).kills, 1); assert.equal(state(r).ore, armed.ore);
    assert.equal(state(r).buildings[0].cooldown, 8); balanced(r); await r.close();
  });

  await test('destroyed rail endpoints lose each in-flight load once and reconnect surviving depots', async () => {
    const r = await fresh(); await tower(r, 12,21); const child = await tower(r, 16,21);
    const world = state(r); world.tick = 9; world.produced = 48;
    for (let i = 0; i < 3; i++) setWorker(world, i, {id:i+1});
    setBuilding(world, 0, {hp:7}); setRail(world, 0, {cargo:16}); setRail(world, 1, {cargo:32});
    await restoreColony(r, world); await addEnemy(r, {x:12,y:21}); await advance(r);
    const destroyed = state(r); assert.equal(destroyed.lost, 1); assert.equal(destroyed.lostOre, 48);
    assert.equal(destroyed.rails.length, 1); assert.equal(destroyed.rails[0].source, child.id);
    assert.equal(destroyed.rails[0].parent, 0); assert.equal(destroyed.rails[0].cargo, 0);
    assert.equal(destroyed.delivered, 0); await advance(r, 15); assert.equal(state(r).lostOre, 48);
    await r.close();
  });

  await test('decoder rejects duplicate kit reservations and malformed rail ownership', async () => {
    const r = await fresh(); await call(r, 'observe', [12,21]); const reserved = r.snapshot(1);
    const duplicate = colony(reserved); duplicate.bots[1].order = state(r).buildings[0].id;
    await assert.rejects(() => restoreColony(r, duplicate), WebAssembly.RuntimeError);
    assert.deepEqual(r.snapshot(1), reserved);
    await until(r, world => world.buildings[0].stage === 2); const valid = r.snapshot(1);
    const cycle = colony(valid); setRail(cycle, 0, {parent:state(r).buildings[0].id});
    await assert.rejects(() => restoreColony(r, cycle), WebAssembly.RuntimeError);
    const phantom = colony(valid); setRail(phantom, 0, {returning:1,cargo:16,progress:16}); phantom.produced += 16;
    await assert.rejects(() => restoreColony(r, phantom), WebAssembly.RuntimeError);
    assert.deepEqual(r.snapshot(1), valid); await r.close();
  });
}
