// Prices and legal paid orders execute in the Scheme model. This experiment
// prices an expansion; instantaneous mining/building is not a survival policy.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/compiler/execute.mjs';

const repository = fileURLToPath(new URL('../..', import.meta.url));
const settings = JSON.parse(readFileSync(resolve(repository, 'apps/siegework/settings.json')));
const queries = {initialOre:0, initialWorkers:1, price:2, upgradePrice:3, productionTicks:10,
  depositRate:15, width:16, height:17, hubX:18, hubY:19, mineLevels:21, mineSlots:22,
  reserve:23, reset:28, visibleTile:29, towerReason:30, buyTower:31, buyMine:32,
  credits:33, spent:34, deliverStarter:35, buildingRadius:36, initialRadius:37,
  oracleTile:38, oracleWalk:39};
// Fixed, spread-out regression seeds, including the preserved seed-one map and
// both seed-domain endpoints. They are not a random population estimate.
const regressionSeeds = [1, 7, 65535, ...Array.from({length:61}, (_, i) => 1 + (i + 1) * 1009)];

// ---- Facts and an explicit, reproducible experiment ----

function configuration(args) {
  const options = {seeds:regressionSeeds, output:null};
  for (let i = 0; i < args.length; i += 2) {
    assert.ok(args[i + 1] !== undefined, `missing value for ${args[i]}`);
    if (args[i] === '--output') options.output = resolve(args[i + 1]);
    else if (args[i] === '--seed') options.seeds = [Number(args[i + 1])];
    else throw new Error(`unknown option: ${args[i]}`);
  }
  assert.ok(options.seeds.every(seed => Number.isInteger(seed) && seed >= 1 && seed <= 65535));
  return options;
}

function modelFacts(query) {
  const facts = Object.fromEntries(['initialOre', 'initialWorkers', 'productionTicks', 'width', 'height'].map(name => [name, query(name)]));
  facts.minePrice = query('price', 1); facts.towerPrice = query('price', 3); facts.gunPrice = query('price', 2);
  facts.mineRadius = query('buildingRadius', 11); facts.towerRadius = query('buildingRadius', 31);
  facts.tickSeconds = settings.tickMilliseconds / 1000;
  facts.slots = Array.from({length:query('mineLevels', 1)}, (_, i) => query('mineSlots', i + 1));
  facts.mineUpgradePrices = facts.slots.slice(1).map((_, i) => query('upgradePrice', 11 + i));
  assert.ok(Object.values(facts).every(value => Array.isArray(value) || value > 0));
  return facts;
}

function point(cell, width) { return {x:cell % width, y:Math.floor(cell / width)}; }
function squaredDistance(a, b) { return (a.x - b.x) ** 2 + (a.y - b.y) ** 2; }

function circleOffsets(radius) {
  const offsets = [];
  for (let y = -radius; y <= radius; y++)
    for (let x = -radius; x <= radius; x++)
      if (x * x + y * y <= radius * radius) offsets.push({x, y});
  return offsets;
}

function cellsAround(cell, offsets, facts) {
  const center = point(cell, facts.width), cells = [];
  for (const offset of offsets) {
    const x = center.x + offset.x, y = center.y + offset.y;
    if (x >= 0 && x < facts.width && y >= 0 && y < facts.height) cells.push(x + y * facts.width);
  }
  return cells;
}

function reveal(query, known, cells) {
  let revealed = 0;
  for (const cell of cells) if (known[cell] < 0) {
    known[cell] = query('visibleTile', cell);
    if (known[cell] >= 0) revealed++;
  }
  return revealed;
}

// Only observed passability enters this flood. Actual chosen commands still
// prove their route in Scheme; rejected candidates are tried in rank order.
function visibleWalkingDistances(known, hub, width) {
  const distances = new Int32Array(known.length).fill(-1), queue = [hub];
  distances[hub] = 0;
  for (let i = 0; i < queue.length; i++) {
    const cell = queue[i], x = cell % width;
    for (const next of [x > 0 ? cell - 1 : -1, x + 1 < width ? cell + 1 : -1, cell - width, cell + width])
      if (next >= 0 && next < known.length && distances[next] < 0 && known[next] >= 0 && known[next] % 2 === 1) {
        distances[next] = distances[cell] + 1; queue.push(next);
      }
  }
  return distances;
}

function resourceChoices(known, occupied, distances) {
  return Array.from(known.keys()).filter(cell => known[cell] > 1 && !occupied.has(cell) && distances[cell] >= 0)
    .sort((a, b) => distances[a] - distances[b] || a - b);
}

function towerChoices(query, state, distances, offsets, facts, policy) {
  const choices = [];
  for (let cell = 0; cell < state.known.length; cell++) {
    if (state.known[cell] !== 1 || distances[cell] < 0 || state.occupied.has(cell) || query('towerReason', cell) !== 0) continue;
    const gain = cellsAround(cell, offsets, facts).filter(next => state.known[next] < 0).length;
    if (gain > 0) choices.push({cell, gain, distance:distances[cell]});
  }
  // Positive walking distances let integer cross-products compare gain/distance
  // without floating-point tie changes. No hidden terrain enters either score.
  return choices.sort((a, b) => (policy === 'nearby' ? b.gain * a.distance - a.gain * b.distance : b.gain - a.gain)
    || b.gain - a.gain || a.distance - b.distance || a.cell - b.cell);
}

function purchase(query, state, kind, cell, price, distance) {
  const credits = query('credits'), spent = query('spent'), reason = query(kind === 'tower' ? 'buyTower' : 'buyMine', cell);
  assert.equal(query('credits'), credits - (reason === 0 ? price : 0), 'accepted orders pay exactly once');
  assert.equal(query('spent'), spent + (reason === 0 ? price : 0), 'rejected orders do not spend');
  if (reason !== 0) {state.rejected.push({kind, cell, reason}); return false;}
  state.occupied.add(cell);
  state.purchases.push({kind, cell, price, visibleWalkCells:distance});
  return true;
}

function startScout(query, facts) {
  query('reset');
  assert.equal(query('deliverStarter'), -1, 'future ore cannot bootstrap the first extractor');
  const hub = query('hubX') + query('hubY') * facts.width, radius = query('initialRadius');
  const state = {hub, radius, known:new Int16Array(facts.width * facts.height).fill(-1), occupied:new Set(), purchases:[], rejected:[]};
  reveal(query, state.known, state.known.keys());
  const distances = visibleWalkingDistances(state.known, hub, facts.width), cell = resourceChoices(state.known, state.occupied, distances)[0];
  assert.notEqual(cell, undefined, 'a visible starter deposit must exist');
  assert.ok(purchase(query, state, 'mine', cell, facts.minePrice, distances[cell]), 'starting cash must pay for the starter');
  state.starter = {cell, rate:query('depositRate', cell), reserve:query('reserve', cell)};
  assert.equal(query('deliverStarter'), state.starter.reserve, 'only the finite starter reserve funds the experiment');
  assert.equal(query('deliverStarter'), -1, 'the same deposit cannot fund the budget twice');
  reveal(query, state.known, cellsAround(cell, circleOffsets(facts.mineRadius), facts));
  return state;
}

function buyVisibleMine(query, state, distances, facts) {
  for (const cell of resourceChoices(state.known, state.occupied, distances))
    if (purchase(query, state, 'mine', cell, facts.minePrice, distances[cell])) return cell;
  return null;
}

function buySurveyTower(query, state, distances, offsets, facts, policy) {
  for (const choice of towerChoices(query, state, distances, offsets, facts, policy))
    if (purchase(query, state, 'tower', choice.cell, facts.towerPrice, choice.distance)) {
      assert.equal(reveal(query, state.known, cellsAround(choice.cell, offsets, facts)), choice.gain,
        'the geometric survey forecast must match actual model sight');
      return true;
    }
  return false;
}

function scoutToSecondMine(query, facts, policy) {
  const state = startScout(query, facts), offsets = circleOffsets(facts.towerRadius);
  const budget = facts.initialOre + state.starter.reserve - facts.minePrice;
  for (;;) {
    assert.equal(query('credits') + query('spent'), facts.initialOre + state.starter.reserve);
    const distances = visibleWalkingDistances(state.known, state.hub, facts.width);
    const second = buyVisibleMine(query, state, distances, facts);
    if (second !== null) return {...state, budget, second, status:'reached', credits:query('credits')};
    if (query('credits') < facts.towerPrice + facts.minePrice)
      return {...state, budget, second:null, status:'budget-exhausted', credits:query('credits')};
    if (!buySurveyTower(query, state, distances, offsets, facts, policy))
      return {...state, budget, second:null, status:'survey-stalled', credits:query('credits')};
  }
}

// ---- A geometric lower bound, computed only AFTER scouting is finished ----

function minimumTowerHops(target, centers, radius) {
  let hops = 0;
  while (centers.every(center => squaredDistance(target, center) > (center.radius + hops * radius) ** 2)) hops++;
  return hops;
}

function oracleBound(query, state, facts) {
  const hub = point(state.hub, facts.width), sites = [];
  const centers = [{...hub, radius:state.radius}, {...point(state.starter.cell, facts.width), radius:facts.mineRadius}];
  for (let cell = 0; cell < facts.width * facts.height; cell++) {
    if (cell === state.starter.cell || query('oracleTile', cell) < 2) continue;
    const walkCells = query('oracleWalk', cell);
    if (walkCells > 0) sites.push({cell, walkCells, straightCells:Math.sqrt(squaredDistance(hub, point(cell, facts.width))),
      towerHops:minimumTowerHops(point(cell, facts.width), centers, facts.towerRadius)});
  }
  assert.ok(sites.length > 0, 'the sampled map must have another reachable deposit');
  sites.sort((a, b) => a.towerHops - b.towerHops || a.walkCells - b.walkCells || a.cell - b.cell);
  const price = facts.minePrice + sites[0].towerHops * facts.towerPrice;
  return {...sites[0], price, protectedPrice:price + (sites[0].towerHops + 2) * facts.gunPrice};
}

function depletionWindows(starter, facts) {
  const periodSeconds = facts.productionTicks * facts.tickSeconds;
  return facts.slots.map((slots, i) => ({level:i + 1, slots,
    upgradeOre:facts.mineUpgradePrices.slice(0, i).reduce((a, b) => a + b, 0),
    fullStaffSeconds:Math.ceil(starter.reserve / (starter.rate * slots)) * periodSeconds,
    initialWorkersSeconds:Math.ceil(starter.reserve / (starter.rate * Math.min(slots, facts.initialWorkers))) * periodSeconds,
    lastTenPercentFullStaffSeconds:Math.ceil(starter.reserve * 0.1 / (starter.rate * slots)) * periodSeconds}));
}

function seedResult(query, seed, facts, policy) {
  const state = scoutToSecondMine(query, facts, policy), oracle = oracleBound(query, state, facts);
  const towers = state.purchases.filter(order => order.kind === 'tower').length;
  const price = state.purchases.slice(1).reduce((sum, order) => sum + order.price, 0);
  const success = state.status === 'reached';
  if (success) assert.ok(oracle.price <= price, 'an optimistic lower bound cannot exceed a legal survey chain');
  return {seed, status:state.status, budget:state.budget, starter:state.starter, second:state.second,
    towers, expansionOre:success ? price : null, spentBeforeStop:price, oracle,
    secondWalkCells:success ? state.purchases.at(-1).visibleWalkCells : null,
    bareMargin:success ? state.budget - price : null,
    twoGunMargin:success ? state.budget - price - 2 * facts.gunPrice : null,
    outpostGunMargin:success ? state.budget - price - (towers + 2) * facts.gunPrice : null,
    depletion:depletionWindows(state.starter, facts), purchases:state.purchases, rejected:state.rejected};
}

// ---- Reports keep unsuccessful seeds in the denominator ----

function distribution(values) {
  const sorted = values.toSorted((a, b) => a - b);
  if (!sorted.length) return null;
  const percentile = fraction => sorted[Math.max(0, Math.ceil(sorted.length * fraction) - 1)];
  return {count:sorted.length, mean:sorted.reduce((a, b) => a + b, 0) / sorted.length,
    min:sorted[0], p50:percentile(0.5), p90:percentile(0.9), p95:percentile(0.95), max:sorted.at(-1)};
}

function summarize(rows, facts) {
  const reached = rows.filter(row => row.status === 'reached');
  const safetyBuffer = facts.minePrice + facts.towerPrice;
  return {samples:rows.length, reached:reached.length, safetyBuffer,
    protectedFloorFailures:rows.filter(row => row.oracle.protectedPrice + safetyBuffer > row.budget).map(row => row.seed),
    failures:rows.filter(row => row.status !== 'reached').map(({seed, status}) => ({seed, status})),
    bufferFailures:reached.filter(row => row.bareMargin < safetyBuffer).map(row => row.seed),
    twoGunFailures:reached.filter(row => row.twoGunMargin < 0).map(row => row.seed),
    outpostGunFailures:reached.filter(row => row.outpostGunMargin < 0).map(row => row.seed),
    twoGunAffordable:reached.filter(row => row.twoGunMargin >= 0).length,
    outpostGunAffordable:reached.filter(row => row.outpostGunMargin >= 0).length,
    distributions:Object.fromEntries(['towers', 'secondWalkCells', 'expansionOre', 'bareMargin', 'twoGunMargin', 'outpostGunMargin'].map(key => [key, distribution(reached.map(row => row[key]))])),
    oracleOre:distribution(rows.map(row => row.oracle.price)), oracleWalkCells:distribution(rows.map(row => row.oracle.walkCells)),
    protectedFloorMargin:distribution(rows.map(row => row.budget - row.oracle.protectedPrice - safetyBuffer))};
}

function printPolicy(name, summary) {
  console.log(`${name}: ${summary.reached}/${summary.samples} seeds reached a second paid mine.`);
  for (const [name, stats] of Object.entries(summary.distributions))
    console.log(`${name}: ${stats ? `mean ${stats.mean.toFixed(2)}, p50 ${stats.p50}, p90 ${stats.p90}, p95 ${stats.p95}, min ${stats.min}, max ${stats.max}` : 'no successful seeds'}`);
  console.log(`Failures: ${JSON.stringify(summary.failures)}; ${summary.safetyBuffer}-ore buffer failures ${JSON.stringify(summary.bufferFailures)}.`);
  console.log(`Defense allowances funded: two guns ${summary.twoGunAffordable}/${summary.samples}; two + one per tower ${summary.outpostGunAffordable}/${summary.samples}.`);
  console.log(`Additional defense failures among reached seeds: two guns ${JSON.stringify(summary.twoGunFailures)}; two + one per tower ${JSON.stringify(summary.outpostGunFailures)}.`);
}

function printReport(report) {
  const {facts, policies} = report;
  console.log(`starter-economy-test: ${facts.initialOre} starting ore; extractor ${facts.minePrice}, tower ${facts.towerPrice}, artillery ${facts.gunPrice}.`);
  for (const [name, {summary}] of Object.entries(policies)) printPolicy(name, summary);
  console.log(`Geometric ore lower bound: ${JSON.stringify(policies.area.summary.oracleOre)}; walking cells to its target: ${JSON.stringify(policies.area.summary.oracleWalkCells)}.`);
  console.log(`Margin after the geometric floor, one gun per minimum tower + two baseline guns, and spare tower/extractor: ${JSON.stringify(policies.area.summary.protectedFloorMargin)}.`);
  console.log(`Starter depletion, first sample: ${JSON.stringify(policies.nearby.rows[0].depletion)}.`);
  console.log('Eventual price-only budget. No timing, gun coverage, survival, ordinary-player average or all-seed guarantee.');
}

async function main(args) {
  const usage = 'usage: node tests/applications/starter-economy-test.mjs PROBE.wasm [--seed 1] [--output REPORT.json]';
  if (args[0] === '--help' || args[0] === '-h') {console.log(usage); return;}
  assert.ok(args.length > 0, usage);
  const options = configuration(args.slice(1)), path = resolve(args[0]), bytes = readFileSync(path);
  const instance = instantiate(loadWasm(bytes));
  try {
    const query = (seed, name, value = 0) => invokeEntry(instance, [queries[name], value, seed]);
    const facts = modelFacts((name, value) => query(1, name, value));
    const policies = Object.fromEntries(['nearby', 'area'].map(policy => {
      const rows = options.seeds.map(seed => seedResult((name, value) => query(seed, name, value), seed, facts, policy));
      return [policy, {rows, summary:summarize(rows, facts)}];
    }));
    const report = {test:'starter-economy-test', probe:{path, sha256:createHash('sha256').update(bytes).digest('hex')},
      policyDescriptions:{area:'Most unknown cells revealed; ties shortest visible hub walk, then cell index.',
        nearby:'Most unknown cells revealed per visible hub-walk cell; ties gain, walk, then cell index.'},
      assumptions:['Only level-one towers and extractors; no upgrades, disposal, refunds or losses.',
        'The first mine uses starting cash, then its finite reserve is completely extracted and delivered instantaneously.',
        'Paid construction completes immediately, resets builders and rebuilds transport; the real state validator checks each step.',
        'No elapsed time, threats, hauling delay or extra mining income. Defense allowances are prices, not placed coverage.',
        'Cost distributions include successful runs only; stopped seeds remain explicit and in all affordability denominators.',
        'The CI criterion adds one gun per geometric minimum tower, two baseline guns, and a spare tower/extractor allowance to the necessary floor. It does not establish successful scouting or defense.'],
      facts, policies};
    printReport(report);
    if (options.output) writeFileSync(options.output, `${JSON.stringify(report, null, 2)}\n`);
    assert.deepEqual(policies.area.summary.protectedFloorFailures, [], 'the geometric floor with defense prices must leave one tower/extractor allowance');
    console.log('PASS: model accounting and geometric budget guardrail. Scout failures above are diagnostic, not a survival pass.');
  } finally {closeInstance(instance);}
}

await main(process.argv.slice(2));
