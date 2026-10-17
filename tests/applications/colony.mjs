// Actual compiled reducers exercise spatial knowledge, shared labor and material
// ownership. Snapshot edits below only establish boundary/failure scenarios.
import assert from 'node:assert/strict';
import {colony, colonyBalance, addEnemy, setWorker} from './colony-state.mjs';

export async function checkColony(test, fresh, call) {
  const advance = async (runtime, ticks = 1) => { for (let tick = 0; tick < ticks; tick++) await call(runtime, 'advance'); };
  const state = runtime => colony(runtime.snapshot(1));
  function materialBalance(world) {
    assert.equal(world.ore, 160 + world.delivered - world.spent);
    assert.equal(world.produced, colonyBalance(world).raw);
    for (const building of world.buildings) {
      const carriers = world.bots.filter(bot => ([3,5].includes(bot.job) || (bot.job === 7 && bot.timer === 5)) && bot.cargo > 4 && bot.target === building.id);
      assert.equal(carriers.length, building.stage === 1 ? 1 : 0);
    }
  }

  await test('completed observation and upgraded radius open a second working mine', async () => {
    const r = await fresh(), retained = r.stores.get(1);
    await call(r, 'extract', [12,20]); await call(r, 'observe', [12,14]);
    assert.equal(state(r).surveys.length, 1); assert.equal(state(r).buildings[1].stage, 3);
    const paid = state(r).ore; await call(r, 'extract', [5,5]);
    assert.equal(state(r).notice, 1); assert.equal(state(r).ore, paid);
    await advance(r, 100); assert.equal(state(r).buildings[1].stage, 2);
    await call(r, 'observe', [12,8]); await advance(r, 200);
    await call(r, 'upgrade', [12,8]); await call(r, 'extract', [5,5]);
    const northern = state(r).buildings.find(building => building.x === 5 && building.y === 5);
    assert.ok(northern); await call(r, 'fabricate-worker'); assert.equal(state(r).bots.length, 4); let northCollected = false;
    const deliveredBefore = state(r).delivered;
    for (let tick = 0; tick < 600; tick++) {
      const before = state(r);
      const arriving = before.bots.find(bot => bot.job === 1 && bot.target === northern.id && bot.path.length === 0);
      await advance(r); materialBalance(state(r));
      if (arriving && state(r).bots.some(bot => bot.id === arriving.id && bot.job === 2 && bot.cargo > 0)) northCollected = true;
    }
    assert.ok(northCollected); assert.ok(state(r).delivered > deliveredBefore);
    assert.equal(retained[3], 160); assert.equal(retained[7], 0);
    assert.ok(state(r).buildings.filter(building => building.kind === 1 && building.stage === 2).length === 2);
    await r.close();
  });

  await test('observation does not bypass terrain reachability and lost sight preserves geography', async () => {
    const r = await fresh(); await call(r, 'observe', [2,16]); await advance(r, 120);
    const before = state(r); await call(r, 'fortify', [2,9]);
    assert.equal(state(r).notice, 6); assert.equal(state(r).ore, before.ore);
    const words = r.snapshot(1); words[32 + 5] = 1; words[1] = 129;
    for (let i=0;i<3;i++) setWorker(words,i,{id:i+1}); await r.restore(1, words);
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
    const clear = r.snapshot(1); clear[9] = 0; await r.restore(1, clear); await advance(r, 260);
    assert.equal(state(r).buildings[0].stage, 2); assert.equal(state(r).spent, 25); assert.equal(state(r).ore, 135);
    await r.close();
  });

  await test('automatic repairs preserve their ore reserve and have one supply owner', async () => {
    const r = await fresh(), words = r.snapshot(1);
    words[3] = 44; words[15] = 116; words[4] = 100; words[1] = 19; await r.restore(1, words);
    await advance(r); assert.equal(state(r).ore, 40);
    assert.equal(state(r).bots.filter(bot => bot.job === 4).length, 1);
    await advance(r, 80); assert.equal(state(r).ore, 40); assert.equal(state(r).hull, 125);
    await r.close();
  });

  await test('the scheduled raid destroys an outer operation and workers can rebuild it', async () => {
    const r = await fresh(); await call(r, 'observe', [16,21]); await advance(r, 120);
    await call(r, 'observe', [22,20]); await advance(r, 200);
    const outpost = state(r).buildings.find(building => building.x === 22);
    assert.equal(outpost.stage, 2);
    const checkpoint = r.snapshot(1); checkpoint[1] = 2099; await r.restore(1, checkpoint);
    await advance(r); assert.equal(state(r).enemies.length, 4);
    assert.ok(state(r).enemies.every(enemy => enemy.kind === 1 && enemy.target === outpost.id));
    for (let tick = 0; tick < 400 && state(r).lost === 0; tick++) await advance(r);
    assert.equal(state(r).lost, 1); const knowledge = state(r).surveys;
    const cleared = r.snapshot(1); cleared[9] = 0; await r.restore(1, cleared);
    await call(r, 'observe', [22,20]); assert.equal(state(r).notice, 10); await advance(r, 200);
    assert.equal(state(r).buildings.find(building => building.x === 22).stage, 2);
    assert.deepEqual(state(r).surveys, knowledge); materialBalance(state(r)); await r.close();
  });

  await test('decoder rejects orphaned construction claims and discontinuous worker paths', async () => {
    const r = await fresh(); await call(r, 'observe', [12,14]);
    const committed = r.snapshot(1), orphan = committed.slice(); orphan[32 + 7] = 1;
    await assert.rejects(() => r.restore(1, orphan), WebAssembly.RuntimeError); assert.deepEqual(r.snapshot(1), committed);
    await advance(r); const moving = r.snapshot(1), discontinuous = moving.slice(); discontinuous[416 + 8] = 0;
    await assert.rejects(() => r.restore(1, discontinuous), WebAssembly.RuntimeError); assert.deepEqual(r.snapshot(1), moving);
    await r.close();
  });

  await test('an undefended finale reaches and destroys a healthy hub despite automatic repairs', async () => {
    const r = await fresh(), words = r.snapshot(1); words[1] = 4199; await r.restore(1, words);
    await advance(r); assert.equal(state(r).enemies[0].kind, 2);
    let firstDamage = 0;
    while (state(r).outcome === 0) {
      await advance(r); if (state(r).hull < 300 && firstDamage === 0) firstDamage = state(r).tick;
    }
    assert.ok(firstDamage > 4200 && firstDamage < 4600);
    assert.equal(state(r).outcome, 1); assert.ok(state(r).tick < 4800);
    assert.ok(state(r).spent > 0); assert.equal(state(r).repairs, 1); await r.close();
  });

  await test('camera coordinates agree for pointer placement, pan and cursor movement', async () => {
    const r = await fresh(), local = (name, args = []) => r.dispatch(2, r.command('client', name, args));
    await local('pan', [4,-3]); await local('move', [340,380]);
    assert.deepEqual(r.snapshot(2), [5,1,340,380,160000,440000]);
    const effects = (await local('confirm')).effects; await call(r, 'extract', [12,20]);
    assert.deepEqual(r.effectCommand(effects[0]), r.command('match', 'extract', [12,20]));
    await local('nudge', [-30,0]); const moved = r.snapshot(2); assert.equal(moved[2], 0); assert.equal(moved[4], -100000);
    await local('home'); assert.deepEqual(r.snapshot(2), [5,1,340,340,0,560000]);
    for (const [dx,dy,cx,cy,sx,sy] of [[-100,-100,-120000,-120000,0,0],[100,0,1080000,-120000,959,0],[0,100,1080000,920000,959,639],[-100,0,-120000,920000,0,639]]) {
      await local('pan', [dx,dy]); await local('move', [sx,sy]); const camera = r.snapshot(2);
      assert.deepEqual(camera.slice(4), [cx,cy]); await r.restore(2, camera);
      const before = state(r), command = r.effectCommand((await local('confirm')).effects[0]); await r.dispatch(1, command);
      assert.equal(state(r).notice, 15); assert.equal(state(r).ore, before.ore);
      assert.equal(state(r).buildings.length, before.buildings.length);
    }
    const invalid = r.snapshot(2); invalid[4] = -120001;
    await assert.rejects(() => r.restore(2, invalid), WebAssembly.RuntimeError);
    await local('home'); await local('drift', [-1,0]); await local('move', [0,0]);
    assert.equal(r.snapshot(2)[4], -360);
    assert.deepEqual(r.effectCommand((await local('confirm')).effects[0]), r.command('match','extract',[-1,14]));
    await local('move', [1,0]); assert.deepEqual(r.effectCommand((await local('confirm')).effects[0]), r.command('match','extract',[0,14]));
    await local('home'); for (let i=0;i<10;i++) await local('drift',[16,0]); const shortFrames=r.snapshot(2);
    await local('home'); for (let i=0;i<5;i++) await local('drift',[32,0]); assert.deepEqual(r.snapshot(2),shortFrames); await r.close();
  });

  await test('shared pause freezes all simulation while retaining inspection and paid planning', async () => {
    const r = await fresh(); await call(r, 'extract', [12,20]); await advance(r, 650);
    await call(r, 'pause-colony', [1]); const paused = r.snapshot(1);
    await advance(r, 100); await call(r, 'pause-colony', [1]); assert.deepEqual(r.snapshot(1), paused);
    await call(r, 'pause-colony', [2]); assert.deepEqual(r.snapshot(1), paused);
    await r.dispatch(2, r.command('client', 'pan', [-100,-100])); assert.deepEqual(r.snapshot(1), paused);
    await call(r, 'observe', [12,14]); await call(r, 'fabricate-worker');
    const planned = r.snapshot(1); await advance(r, 100); assert.deepEqual(r.snapshot(1), planned);
    assert.equal(state(r).buildings[1].stage, 3); assert.equal(state(r).bots[3].job, 6);
    await call(r, 'pause-colony', [0]); await advance(r);
    assert.equal(state(r).tick, paused[1] + 1); assert.equal(state(r).paused, 0);
    assert.equal(state(r).bots[3].timer, 29); materialBalance(state(r)); await r.close();
  });

  await test('a fired shot retains its hit position while its target moves and pause freezes the tracer', async () => {
    const r = await fresh(); await call(r, 'fortify', [15,20]);
    for (let tick = 0; tick < 1100 && state(r).buildings[0].cooldown !== 8; tick++) await advance(r);
    const shot = state(r).buildings[0]; assert.equal(shot.cooldown, 8);
    const target = state(r).enemies.find(enemy => enemy.x === shot.aimX && enemy.y === shot.aimY);
    assert.ok(target); assert.equal(target.hp, 60);
    await advance(r); const next = state(r), gun = next.buildings[0];
    assert.deepEqual([gun.aimX,gun.aimY], [shot.aimX,shot.aimY]);
    assert.notDeepEqual(next.enemies.find(enemy => enemy.id === target.id), target);
    await call(r, 'pause-colony', [1]); const frozen = r.view().quads;
    await advance(r, 30); assert.deepEqual(r.view().quads, frozen);
    await call(r, 'pause-colony', [0]); await advance(r); assert.notDeepEqual(r.view().quads, frozen); await r.close();
  });
}
