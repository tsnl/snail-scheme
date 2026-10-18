// Actual compiled reducers exercise spatial knowledge, shared labor and material
// ownership. Snapshot edits below only establish boundary/failure scenarios.
import assert from 'node:assert/strict';
import {colony, colonyBalance, addEnemy, setWorker, restoreColony, client, restoreClient, at, siteAt, routeCell} from './colony-state.mjs';

export async function checkColony(test, fresh, call) {
  const advance = async (runtime, ticks = 1) => { for (let tick = 0; tick < ticks; tick++) await call(runtime, 'advance'); };
  const state = runtime => colony(runtime.snapshot(1));
  function materialBalance(world) {
    assert.equal(world.ore, 160 + world.delivered + world.localSpent - world.spent);
    assert.equal(world.produced, colonyBalance(world).raw);
    for (const building of world.buildings) {
      const carriers = world.bots.filter(bot => ([3,5].includes(bot.job) || (bot.job === 7 && bot.timer === 5)) && bot.cargo > 4 && bot.target === building.id);
      assert.equal(carriers.length, [1,5].includes(building.stage) ? 1 : 0);
    }
  }

  await test('completed observation and upgraded radius open a second working mine', async () => {
    const r = await fresh(), retained = r.stores.get(1);
    await call(r, 'extract', [12,20]); await call(r, 'observe', [12,14]);
    assert.equal(state(r).surveys.length, 1); assert.equal(state(r).buildings[1].stage, 0);
    const paid = state(r).ore; await call(r, 'extract', [5,5]);
    assert.equal(state(r).notice, 1); assert.equal(state(r).ore, paid);
    await advance(r, 100); assert.equal(state(r).buildings[1].stage, 2);
    await call(r, 'observe', [12,8]); await advance(r, 200);
    await call(r, 'upgrade', [12,8]);
    for(let i=0;i<250&&siteAt(state(r),12,8).level!==2;i++)await advance(r);
    await call(r, 'extract', [5,5]);
    const northern = siteAt(state(r),5,5);
    assert.ok(northern);
    for (let tick = 0; tick < 300 && state(r).ore < 25; tick++) await advance(r);
    await call(r, 'fabricate-worker'); assert.equal(state(r).bots.length, 3); let northCollected = false;
    assert.ok(state(r).bots.some(bot => bot.job === 4 || bot.job === 6));
    const deliveredBefore = state(r).delivered;
    for (let tick = 0; tick < 600; tick++) {
      const before = state(r);
      const arriving = before.bots.find(bot => bot.job === 1 && bot.target === northern.id && bot.path.length === 0);
      await advance(r); materialBalance(state(r));
      if (arriving && state(r).bots.some(bot => bot.id === arriving.id && bot.job === 2 && bot.cargo > 0)) northCollected = true;
    }
    assert.ok(northCollected); assert.ok(state(r).delivered > deliveredBefore);
    assert.equal(colony(retained).ore, 160); assert.equal(colony(retained).buildings.length, 0);
    assert.ok(state(r).buildings.filter(building => building.kind === 1 && building.stage === 2).length === 2);
    await r.close();
  });

  await test('observation does not bypass terrain reachability and lost sight preserves geography', async () => {
    const r = await fresh(); await call(r, 'observe', [2,16]); await advance(r, 120);
    const before = state(r); await call(r, 'fortify', [2,9]);
    assert.equal(state(r).notice, 6); assert.equal(state(r).ore, before.ore);
    const world = state(r); world.buildings[0].hp = 1; world.tick = 129; world.lastRevealTick=-100;
    for (let i=0;i<3;i++) setWorker(world,i,{id:i+1}); await restoreColony(r, world);
    await addEnemy(r, {x:2, y:16, target:before.buildings[0].id, kind:1});
    await advance(r); assert.equal(state(r).lost, 1); assert.deepEqual(state(r).surveys, before.surveys);
    await call(r, 'fortify', [2,9]); assert.equal(state(r).notice, 1);
    await r.close();
  });

  await test('interrupted construction returns exactly one paid kit and resumes after danger', async () => {
    const r = await fresh(); await call(r, 'observe', [12,14]); await advance(r);
    const project = state(r).buildings[0]; assert.equal(project.stage, 1);
    await addEnemy(r, {x:8, y:22}); await advance(r, 3);
    assert.equal(state(r).bots.filter(bot => bot.job === 7 && bot.timer === 5 && bot.target === project.id).length, 1);
    await advance(r, 25); assert.equal(state(r).buildings[0].stage, 1);
    assert.equal(state(r).spent, 25); materialBalance(state(r));
    const clear = state(r); clear.enemies.length = 0; await restoreColony(r, clear); await advance(r, 260);
    assert.equal(state(r).buildings[0].stage, 2); assert.equal(state(r).spent, 25); assert.equal(state(r).ore, 135);
    await r.close();
  });

  await test('the scheduled raid destroys an outer operation and workers can rebuild it', async () => {
    const r = await fresh(); await call(r, 'observe', [16,21]); await advance(r, 120);
    await call(r, 'observe', [22,20]); await advance(r, 200);
    const outpost = siteAt(state(r),22,20);
    assert.equal(outpost.stage, 2);
    const checkpoint = state(r); checkpoint.tick = 2699; checkpoint.lastRevealTick=-100; checkpoint.enemies.length=0; await restoreColony(r, checkpoint);
    await advance(r); assert.equal(state(r).enemies.length, 5);
    assert.ok(state(r).enemies.every(enemy => enemy.kind === 1 && enemy.target === outpost.id));
    for (let tick = 0; tick < 1800 && state(r).lost === 0 && state(r).outcome === 0; tick++) await advance(r);
    assert.equal(state(r).lost, 1); const knowledge = state(r).surveys;
    const cleared = state(r); cleared.enemies.length = 0; await restoreColony(r, cleared);
    await call(r, 'observe', [22,20]); assert.equal(state(r).notice, 10); await advance(r, 200);
    assert.equal(siteAt(state(r),22,20).stage, 2);
    assert.deepEqual(state(r).surveys, knowledge); materialBalance(state(r)); await r.close();
  });

  await test('decoder rejects orphaned construction claims and discontinuous worker paths', async () => {
    const r = await fresh(); await call(r, 'observe', [12,14]);
    const committed = r.snapshot(1), orphan = colony(committed); orphan.buildings[0].stage = 1;
    await assert.rejects(() => restoreColony(r, orphan), WebAssembly.RuntimeError); assert.deepEqual(r.snapshot(1), committed);
    await advance(r); const moving = r.snapshot(1), discontinuous = colony(moving); discontinuous.bots[0].path[0] = 0;
    await assert.rejects(() => restoreColony(r, discontinuous), WebAssembly.RuntimeError); assert.deepEqual(r.snapshot(1), moving);
    await r.close();
  });

  await test('an undefended heavy nest wave reaches and destroys a healthy hub without passive healing', async () => {
    const r = await fresh(), world = state(r); world.started = true; world.tick = 10799; world.lastRevealTick=-100; await restoreColony(r, world);
    await advance(r); assert.equal(state(r).enemies[0].kind, 2);
    let firstDamage = 0;
    for(let count=0;count<4000 && state(r).outcome===0;count++) {
      await advance(r); if (state(r).hull < 300 && firstDamage === 0) firstDamage = state(r).tick;
    }
    assert.ok(firstDamage > 10800); assert.equal(state(r).outcome, 1);
    assert.equal(state(r).nestHp,1500);
    assert.equal(state(r).spent, 0); await r.close();
  });

  await test('3D camera preserves state, bounds pan and rejects invalid client snapshots', async () => {
    const r = await fresh(), local = (name, args = []) => r.dispatch(2, r.command('client', name, args));
    const world = r.snapshot(1); await local('pan', [4, -3]);
    const panned = client(r.snapshot(2)); assert.notEqual(panned.cameraX, 10000);
    assert.deepEqual(r.snapshot(1), world); await local('home');
    assert.equal(client(r.snapshot(2)).homing,true);
    for(let i=0;i<40&&client(r.snapshot(2)).homing;i++)await local('animate',[50]);
    const hub=colony(world).surveys[0],home=client(r.snapshot(2));
    assert.equal(home.homing,false); assert.deepEqual([home.cameraX,home.cameraY],[hub.x*1000,hub.y*1000]);
    assert.deepEqual(r.snapshot(1),world);
    const initial = r.snapshot(2); await r.restore(2, initial); assert.deepEqual(r.snapshot(2), initial);
    const invalid = client(initial); invalid.cameraX = -3001;
    await assert.rejects(() => restoreClient(r, invalid), WebAssembly.RuntimeError);
    await local('pan', [100, 100]); const bounded = client(r.snapshot(2));
    assert.ok(bounded.cameraX >= -3000 && bounded.cameraX <= 387000);
    assert.ok(bounded.cameraY >= -3000 && bounded.cameraY <= 291000); await r.close();
  });

  await test('shared pause freezes all simulation while retaining inspection and paid planning', async () => {
    const r = await fresh(); await call(r, 'extract', [12,20]); await advance(r, 650);
    await call(r, 'pause-colony', [1]); const paused = r.snapshot(1);
    await advance(r, 100); await call(r, 'pause-colony', [1]); assert.deepEqual(r.snapshot(1), paused);
    await call(r, 'pause-colony', [2]); assert.deepEqual(r.snapshot(1), paused);
    await r.dispatch(2, r.command('client', 'pan', [-100,-100])); assert.deepEqual(r.snapshot(1), paused);
    await call(r, 'observe', [12,14]); await call(r, 'fabricate-worker');
    const planned = r.snapshot(1); await advance(r, 100); assert.deepEqual(r.snapshot(1), planned);
    assert.equal(state(r).buildings[1].stage, 3); assert.equal(state(r).bots.length, 3);
    const assembler = state(r).bots.find(bot => bot.job === 4 || bot.job === 6); assert.ok(assembler);
    await call(r, 'pause-colony', [0]); await advance(r);
    assert.equal(state(r).tick, colony(paused).tick + 1); assert.equal(state(r).paused, 0);
    assert.equal(state(r).bots.find(bot => bot.id === assembler.id).timer, assembler.job === 6 ? 29 : 0);
    materialBalance(state(r)); await r.close();
  });

  await test('a fired shot retains its hit position while its target moves and pause freezes the tracer', async () => {
    const r = await fresh(); await call(r, 'fortify', [15,20]);
    for (let tick = 0; tick < 200 && state(r).buildings[0].stage !== 2; tick++) await advance(r);
    await addEnemy(r,{x:17,y:20,hp:80});
    const moving=state(r); moving.enemies[0].path=[routeCell(moving,16,20),routeCell(moving,15,20)];
    await restoreColony(r,moving);
    for (let tick = 0; tick < 10 && state(r).buildings[0].cooldown !== 8; tick++) await advance(r);
    const shot = state(r).buildings[0]; assert.equal(shot.cooldown, 8);
    const target = state(r).enemies.find(enemy => enemy.x === shot.aimX && enemy.y === shot.aimY);
    assert.ok(target); assert.ok(target.hp < 80 && target.hp >= 56);
    await advance(r); const next = state(r), gun = next.buildings[0];
    assert.deepEqual([gun.aimX,gun.aimY], [shot.aimX,shot.aimY]);
    assert.notDeepEqual(next.enemies.find(enemy => enemy.id === target.id), target);
    await call(r, 'pause-colony', [1]); const frozen = r.view().scene;
    await advance(r, 30); assert.deepEqual(r.view().scene, frozen);
    await call(r, 'pause-colony', [0]); await advance(r); assert.notDeepEqual(r.view().scene, frozen); await r.close();
  });
}
