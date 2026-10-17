// Actual compiled reducers exercise spatial knowledge, shared labor and material
// ownership. Snapshot edits below only establish boundary/failure scenarios.
import assert from 'node:assert/strict';
import {colony, addEnemy} from './colony-state.mjs';

export async function checkColony(test, fresh, call) {
  const advance = (runtime, ticks = 1) => { for (let tick = 0; tick < ticks; tick++) call(runtime, 'advance'); };
  const state = runtime => colony(runtime.snapshot(1));
  function materialBalance(world) {
    assert.equal(world.ore, 160 + world.delivered - world.spent);
    const cargo = world.bots.filter(bot => bot.job === 2).reduce((total, bot) => total + bot.cargo, 0);
    const stock = world.buildings.reduce((total, building) => total + building.stock, 0);
    assert.equal(world.produced, world.delivered + cargo + stock);
    for (const building of world.buildings) {
      const carriers = world.bots.filter(bot => [3,5].includes(bot.job) && bot.cargo > 4 && bot.target === building.id);
      assert.equal(carriers.length, building.stage === 1 ? 1 : 0);
    }
  }

  await test('completed observation and upgraded radius open a second working mine', () => {
    const r = fresh(), retained = r.stores.get(1);
    call(r, 'extract', [12,20]); call(r, 'observe', [12,14]);
    assert.equal(state(r).surveys.length, 1); assert.equal(state(r).buildings[1].stage, 0);
    const paid = state(r).ore; call(r, 'extract', [5,5]);
    assert.equal(state(r).notice, 1); assert.equal(state(r).ore, paid);
    advance(r, 100); assert.equal(state(r).buildings[1].stage, 2);
    call(r, 'observe', [12,8]); advance(r, 200);
    call(r, 'upgrade', [12,8]); call(r, 'extract', [5,5]);
    const northern = state(r).buildings.find(building => building.x === 5 && building.y === 5);
    assert.ok(northern); let northDelivered = false;
    for (let tick = 0; tick < 600; tick++) {
      const before = state(r);
      const arriving = before.bots.some(bot => bot.job === 2 && bot.target === northern.id && bot.cargo > 0 && bot.path.length === 0);
      advance(r); materialBalance(state(r));
      if (arriving && state(r).delivered > before.delivered) northDelivered = true;
    }
    assert.ok(northDelivered); assert.equal(retained[3], 160); assert.equal(retained[7], 0);
    assert.ok(state(r).buildings.filter(building => building.kind === 1 && building.stage === 2).length === 2);
    r.close();
  });

  await test('observation does not bypass terrain reachability and lost sight preserves geography', () => {
    const r = fresh(); call(r, 'observe', [2,16]); advance(r, 120);
    const before = state(r); call(r, 'fortify', [2,9]);
    assert.equal(state(r).notice, 6); assert.equal(state(r).ore, before.ore);
    const words = r.snapshot(1); words[32 + 5] = 1; words[1] = 129; r.restore(1, words);
    addEnemy(r, {x:2, y:16, target:before.buildings[0].id, kind:1});
    advance(r); assert.equal(state(r).lost, 1); assert.deepEqual(state(r).surveys, before.surveys);
    call(r, 'fortify', [2,9]); assert.equal(state(r).notice, 1);
    r.close();
  });

  await test('interrupted construction returns exactly one paid kit and resumes after danger', () => {
    const r = fresh(); call(r, 'observe', [12,14]); advance(r);
    const project = state(r).buildings[0]; assert.equal(project.stage, 1);
    addEnemy(r, {x:8, y:22}); advance(r);
    assert.equal(state(r).bots.filter(bot => bot.job === 5 && bot.target === project.id).length, 1);
    advance(r, 8); assert.equal(state(r).buildings[0].stage, 0);
    assert.equal(state(r).bots.filter(bot => bot.job === 3).length, 0);
    const clear = r.snapshot(1); clear[9] = 0; r.restore(1, clear); advance(r, 150);
    assert.equal(state(r).buildings[0].stage, 2); assert.equal(state(r).spent, 25); assert.equal(state(r).ore, 135);
    r.close();
  });

  await test('automatic repairs preserve their ore reserve and have one supply owner', () => {
    const r = fresh(), words = r.snapshot(1);
    words[3] = 44; words[15] = 116; words[4] = 100; words[1] = 19; r.restore(1, words);
    advance(r); assert.equal(state(r).ore, 40);
    assert.equal(state(r).bots.filter(bot => bot.job === 4).length, 1);
    advance(r, 80); assert.equal(state(r).ore, 40); assert.equal(state(r).hull, 125);
    r.close();
  });

  await test('the scheduled raid destroys an outer operation and workers can rebuild it', () => {
    const r = fresh(); call(r, 'observe', [16,21]); advance(r, 120);
    call(r, 'observe', [22,20]); advance(r, 200);
    const outpost = state(r).buildings.find(building => building.x === 22);
    assert.equal(outpost.stage, 2);
    const checkpoint = r.snapshot(1); checkpoint[1] = 2099; r.restore(1, checkpoint);
    advance(r); assert.equal(state(r).enemies.length, 4);
    assert.ok(state(r).enemies.every(enemy => enemy.kind === 1 && enemy.target === outpost.id));
    for (let tick = 0; tick < 400 && state(r).lost === 0; tick++) advance(r);
    assert.equal(state(r).lost, 1); const knowledge = state(r).surveys;
    const cleared = r.snapshot(1); cleared[9] = 0; r.restore(1, cleared);
    call(r, 'observe', [22,20]); assert.equal(state(r).notice, 10); advance(r, 200);
    assert.equal(state(r).buildings.find(building => building.x === 22).stage, 2);
    assert.deepEqual(state(r).surveys, knowledge); materialBalance(state(r)); r.close();
  });

  await test('decoder rejects orphaned construction claims and discontinuous worker paths', () => {
    const r = fresh(); call(r, 'observe', [12,14]);
    const committed = r.snapshot(1), orphan = committed.slice(); orphan[32 + 7] = 1;
    assert.throws(() => r.restore(1, orphan), WebAssembly.RuntimeError); assert.deepEqual(r.snapshot(1), committed);
    advance(r); const moving = r.snapshot(1), discontinuous = moving.slice(); discontinuous[416 + 8] = 0;
    assert.throws(() => r.restore(1, discontinuous), WebAssembly.RuntimeError); assert.deepEqual(r.snapshot(1), moving);
    r.close();
  });

  await test('an undefended finale reaches and destroys a healthy hub despite automatic repairs', () => {
    const r = fresh(), words = r.snapshot(1); words[1] = 4199; r.restore(1, words);
    advance(r); assert.equal(state(r).enemies[0].kind, 2);
    let firstDamage = 0;
    while (state(r).outcome === 0) {
      advance(r); if (state(r).hull < 300 && firstDamage === 0) firstDamage = state(r).tick;
    }
    assert.ok(firstDamage > 4200 && firstDamage < 4600);
    assert.equal(state(r).outcome, 1); assert.ok(state(r).tick < 4800);
    assert.ok(state(r).spent > 0); assert.equal(state(r).repairs, 1); r.close();
  });

  await test('camera coordinates agree for pointer placement, pan and cursor movement', () => {
    const r = fresh(), local = (name, args = []) => r.dispatch(2, r.command('client', name, args));
    local('pan', [4,-3]); local('move', [8,9]);
    assert.deepEqual(r.snapshot(2), [3,1,12,20,4,11]);
    const effects = local('confirm').effects; call(r, 'extract', [12,20]);
    assert.deepEqual(r.effectCommand(effects[0]), r.command('match', 'extract', [12,20]));
    local('nudge', [-30,0]); const moved = r.snapshot(2); assert.equal(moved[2], -3); assert.equal(moved[4], -3);
    local('home'); assert.deepEqual(r.snapshot(2), [3,1,8,22,0,14]);
    for (const [dx,dy,cx,cy,sx,sy] of [[-100,-100,-3,-3,0,0],[100,0,27,-3,23,0],[0,100,27,23,23,15],[-100,0,-3,23,0,15]]) {
      local('pan', [dx,dy]); local('move', [sx,sy]); const camera = r.snapshot(2);
      assert.deepEqual(camera.slice(4), [cx,cy]); r.restore(2, camera);
      const before = state(r), command = r.effectCommand(local('confirm').effects[0]); r.dispatch(1, command);
      assert.equal(state(r).notice, 15); assert.equal(state(r).ore, before.ore);
      assert.equal(state(r).buildings.length, before.buildings.length);
    }
    const invalid = r.snapshot(2); invalid[4] = -4;
    assert.throws(() => r.restore(2, invalid), WebAssembly.RuntimeError); r.close();
  });

  await test('shared pause freezes all simulation while retaining inspection and paid planning', () => {
    const r = fresh(); call(r, 'extract', [12,20]); advance(r, 650);
    call(r, 'pause-colony', [1]); const paused = r.snapshot(1);
    advance(r, 100); call(r, 'pause-colony', [1]); assert.deepEqual(r.snapshot(1), paused);
    call(r, 'pause-colony', [2]); assert.deepEqual(r.snapshot(1), paused);
    r.dispatch(2, r.command('client', 'pan', [-100,-100])); assert.deepEqual(r.snapshot(1), paused);
    call(r, 'observe', [12,14]); call(r, 'fabricate-worker');
    const planned = r.snapshot(1); advance(r, 100); assert.deepEqual(r.snapshot(1), planned);
    assert.equal(state(r).buildings[1].stage, 0); assert.equal(state(r).bots[3].job, 6);
    call(r, 'pause-colony', [0]); advance(r);
    assert.equal(state(r).tick, paused[1] + 1); assert.equal(state(r).paused, 0);
    assert.equal(state(r).bots[3].timer, 29); materialBalance(state(r)); r.close();
  });

  await test('a fired shot retains its hit position while its target moves and pause freezes the tracer', () => {
    const r = fresh(); call(r, 'fortify', [15,20]);
    for (let tick = 0; tick < 1100 && state(r).buildings[0].cooldown !== 8; tick++) advance(r);
    const shot = state(r).buildings[0]; assert.equal(shot.cooldown, 8);
    const target = state(r).enemies.find(enemy => enemy.x === shot.aimX && enemy.y === shot.aimY);
    assert.ok(target); assert.equal(target.hp, 60);
    advance(r); const next = state(r), gun = next.buildings[0];
    assert.deepEqual([gun.aimX,gun.aimY], [shot.aimX,shot.aimY]);
    assert.notDeepEqual(next.enemies.find(enemy => enemy.id === target.id), target);
    call(r, 'pause-colony', [1]); const frozen = r.view().quads;
    advance(r, 30); assert.deepEqual(r.view().quads, frozen);
    call(r, 'pause-colony', [0]); advance(r); assert.notDeepEqual(r.view().quads, frozen); r.close();
  });
}
