// Replay one measured route with actual costs, labor, ticks and enemies. The
// earlier price experiment chooses the route; this runner never edits a World.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {join, resolve} from 'node:path';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {colony, colonyBalance} from './colony-state.mjs';

function seedOnePlan(budget) {
  const sample = budget.policies.area.rows.find(row => row.seed === 1);
  assert.equal(sample?.status, 'reached', 'the price experiment must supply a completed seed-one route');
  const plan = sample.purchases;
  assert.equal(plan[0].kind, 'mine'); assert.equal(plan.at(-1).kind, 'mine');
  assert.ok(plan.slice(1, -1).every(order => order.kind === 'tower'));
  assert.notEqual(plan[0].cell, plan.at(-1).cell, 'the target must be a second deposit');
  return plan;
}

function checkedWorld(runtime, initial) {
  const world = colony(runtime.snapshot(1)), balance = colonyBalance(world);
  assert.equal(world.ore, initial.ore + world.delivered + world.localSpent - world.spent, 'bank ledger');
  assert.equal(world.produced, balance.raw, 'mined ore must remain delivered, spent, carried, stored or lost');
  assert.equal(world.produced + world.deposits.reduce((sum, site) => sum + site.remaining, 0), initial.underground, 'finite reserves');
  return world;
}

async function purchase(runtime, world, order, width, initial) {
  const kind = order.kind === 'mine' ? 1 : 3;
  await runtime.dispatch(1, runtime.command('match', 'build-cell', [kind, order.cell]));
  const next = checkedWorld(runtime, initial);
  assert.equal(next.spent - world.spent, order.price, `order ${order.kind}/${order.cell} refused or price changed; notice ${next.notice}`);
  const building = next.buildings.find(site => site.id === world.nextId);
  assert.ok(building && building.kind === kind && building.x + building.y * width === order.cell, 'accepted order owns its new building');
  return {world:next, order:{kind:order.kind, cell:order.cell, price:order.price, buildingId:building.id,
    orderedTick:world.tick, operationalTick:null}};
}

function result(status, world, orders, remaining, active) {
  return {status, tick:world.tick, starterRemaining:remaining, outcome:world.outcome,
    ore:world.ore, produced:world.produced, delivered:world.delivered, spent:world.spent,
    casualties:world.casualties, buildingsLost:world.lost, activeBuildingId:active?.buildingId ?? null, orders};
}

async function replay(runtime, plan, width, horizon) {
  const start = colony(runtime.snapshot(1));
  const initial = {ore:start.ore, underground:start.deposits.reduce((sum, site) => sum + site.remaining, 0)};
  const orders = []; let index = 0, active = null, world = checkedWorld(runtime, initial);
  for (;;) {
    const remaining = world.deposits.find(site => site.cell === plan[0].cell)?.remaining;
    assert.ok(Number.isInteger(remaining), 'the starter deposit must retain its identity');
    const site = active && world.buildings.find(building => building.id === active.buildingId);
    if (active && !site) return result('project-lost', world, orders, remaining, active);
    if (site?.stage === 2) {active.operationalTick = world.tick; active = null; index++;}
    if (world.outcome !== 0) return result('world-ended', world, orders, remaining, active);
    if (remaining === 0) return result('starter-exhausted', world, orders, remaining, active);
    if (index === plan.length) return result('second-mine-operational', world, orders, remaining, active);
    if (world.tick >= horizon) return result('horizon', world, orders, remaining, active);
    if (!active && world.ore >= plan[index].price) {
      const accepted = await purchase(runtime, world, plan[index], width, initial);
      world = accepted.world; active = accepted.order; orders.push(active); continue;
    }
    const previousTick = world.tick;
    await runtime.dispatch(1, runtime.command('match', 'advance', []));
    world = checkedWorld(runtime, initial);
    assert.equal(world.tick, previousTick + 1, 'each replay advance must progress one actual tick');
  }
}

assert.ok(process.argv[2] && process.argv[3], 'usage: node tests/applications/starter-sprint.mjs PACKAGE BUDGET-REPORT.json [REPORT.json]');
const directory = resolve(process.argv[2]), budget = JSON.parse(readFileSync(resolve(process.argv[3])));
const manifest = JSON.parse(readFileSync(join(directory, 'manifest.json'))), bytes = readFileSync(join(directory, manifest.module));
const plan = seedOnePlan(budget), tickSeconds = manifest.settings.tickMilliseconds / 1000;
assert.ok(Number.isFinite(tickSeconds) && tickSeconds > 0);
const horizon = Math.ceil(600 / tickSeconds), runtime = new ReducerRuntime();
try {
  await runtime.replace(runtime.prepare(bytes, manifest)); await runtime.initialize(1); await runtime.initialize(2);
  await runtime.dispatch(1, runtime.command('match', 'new-run-seed', [1]));
  const outcome = await replay(runtime, plan, budget.facts.width, horizon);
  const report = {test:'starter-sprint', seed:1, generation:manifest.generation,
    moduleSha256:createHash('sha256').update(bytes).digest('hex'), budgetProbeSha256:budget.probe.sha256,
    policy:'Replay the seed-one area-policy purchase trace. Wait for prior completion and real bank cash, then order immediately. No state edits, extra orders, free ore or removed enemies.',
    limits:'One predetermined route with zero deliberation; no discoverability, ordinary-player, other-seed or later-survival guarantee. Stop at the second operational mine; later starter depletion is unobserved.',
    horizonTicks:horizon, tickSeconds, seconds:outcome.tick * tickSeconds, ...outcome};
  if (process.argv[4]) writeFileSync(resolve(process.argv[4]), `${JSON.stringify(report, null, 2)}\n`);
  console.log(JSON.stringify(report));
  assert.equal(outcome.status, 'second-mine-operational', 'the fixed seed-one sprint must reach mine two before starter exhaustion');
  assert.ok(outcome.starterRemaining > 0);
} finally {await runtime.close();}
