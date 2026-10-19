// A deliberately optimistic capacity guardrail, not a survival bot or an exact
// economy optimizer. Prices, production cadence, shot damage and complete wave
// health come from max-dps-probe.sld executing the actual Scheme model in Wasm.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/compiler/execute.mjs';

const repository = fileURLToPath(new URL('../..', import.meta.url));
const settings = JSON.parse(readFileSync(resolve(repository, 'apps/siegework/settings.json')));
const queries = {initialOre:0, initialWorkers:1, buildingCost:2, upgradeCost:3,
  workerCost:4, assemblyTicks:5, workerLimit:6, buildingLimit:7, shotDamage:8,
  cooldownTicks:9, productionTicks:10, nextWave:11, waveHealth:12, waveSize:13,
  waveKind:14, depositRate:15, mapWidth:16, mapHeight:17, hubX:18, hubY:19,
  bossPeriod:20, levelLimit:21, mineSlots:22};

// ---- Parse the experiment, then obtain its inputs from the game ----

function configuration(args) {
  const options = {discoveryMinutes:3, multiplier:0.5, minutes:360, seed:1, output:null};
  const names = {'--discovery-minutes':'discoveryMinutes', '--multiplier':'multiplier',
    '--minutes':'minutes', '--seed':'seed', '--output':'output'};
  for (let index = 0; index < args.length; index += 2) {
    const name = names[args[index]], value = args[index + 1];
    assert.ok(name && value !== undefined, `unknown or incomplete option: ${args[index]}`);
    options[name] = name === 'output' ? resolve(value) : Number(value);
  }
  assert.ok(Number.isFinite(options.discoveryMinutes) && options.discoveryMinutes > 0);
  assert.ok(Number.isFinite(options.multiplier) && options.multiplier > 0 && options.multiplier <= 1);
  assert.ok(Number.isFinite(options.minutes) && options.minutes > 0 && options.minutes <= 1440);
  assert.ok(Number.isInteger(options.seed) && options.seed >= 1 && options.seed <= 65535);
  return options;
}

function modelFacts(query) {
  const facts = Object.fromEntries(['initialOre', 'initialWorkers', 'workerCost', 'assemblyTicks',
    'workerLimit', 'buildingLimit', 'cooldownTicks', 'productionTicks', 'bossPeriod'].map(name => [name, query(name)]));
  facts.tickSeconds = settings.tickMilliseconds / 1000;
  facts.mineLevels = query('levelLimit', 1); facts.gunLevels = query('levelLimit', 2);
  facts.mineCosts = [0, query('buildingCost', 1), ...Array.from({length:facts.mineLevels - 1}, (_, i) => query('upgradeCost', 11 + i))];
  facts.gunCosts = [0, query('buildingCost', 2), ...Array.from({length:facts.gunLevels - 1}, (_, i) => query('upgradeCost', 21 + i))];
  facts.shotDamage = [0, ...Array.from({length:facts.gunLevels}, (_, i) => query('shotDamage', i + 1))];
  facts.mineSlots = [0, ...Array.from({length:facts.mineLevels}, (_, i) => query('mineSlots', i + 1))];
  assert.ok(Object.values(facts).every(value => Array.isArray(value) || value > 0), 'invalid model observation');
  return facts;
}

function resourceSites(query) {
  const width = query('mapWidth'), height = query('mapHeight'), x = query('hubX'), y = query('hubY'), sites = [];
  for (let cell = 0; cell < width * height; cell++) {
    const rate = query('depositRate', cell), a = cell % width, b = Math.floor(cell / width);
    if (rate > 0) sites.push({cell, x:a, y:b, rate, distance:Math.abs(a - x) + Math.abs(b - y), level:0});
  }
  return sites.sort((a, b) => a.distance - b.distance || a.cell - b.cell);
}

function wavesThrough(query, horizon) {
  const waves = [];
  for (let tick = query('nextWave', 0); tick <= horizon; tick = query('nextWave', tick)) {
    const next = query('nextWave', tick), hp = query('waveHealth', tick), count = query('waveSize', tick);
    assert.ok(next > tick, 'wave schedule must progress');
    assert.ok(hp > 0 && count > 0, 'every scheduled wave must produce enemies');
    waves.push({tick, deadline:next, hp, count, kind:query('waveKind', tick)});
  }
  assert.ok(waves.length > 0, 'the horizon must include at least one wave');
  return waves;
}

// ---- Invest first in productive mine slots, then spend the rest on guns ----

function miningSlots(state, facts) {
  return state.sites.flatMap(site => Array(facts.mineSlots[site.level]).fill(site.rate)).sort((a, b) => b - a);
}

function resourceOrder(state, facts) {
  const slots = miningSlots(state, facts), workers = state.workers + state.assembling.length;
  if (slots.length > workers && workers < facts.workerLimit) return {kind:'worker', cost:facts.workerCost};
  const leastUseful = slots.length < facts.workerLimit ? 0 : slots[facts.workerLimit - 1];
  const site = state.sites.filter(site => site.level < facts.mineLevels && site.rate > leastUseful)
    .sort((a, b) => b.rate - a.rate || a.cell - b.cell)[0];
  if (!site || (site.level === 0 && buildingCount(state) >= facts.buildingLimit)) return null;
  return {kind:'mine', site, cost:facts.mineCosts[site.level + 1]};
}

function buildingCount(state) { return state.guns.length + state.sites.filter(site => site.level > 0).length; }

function gunOrder(state, facts) {
  const options = state.guns.flatMap((level, index) => level >= facts.gunLevels ? [] :
    [{kind:'upgrade', index, cost:facts.gunCosts[level + 1], damage:facts.shotDamage[level + 1] - facts.shotDamage[level]}]);
  if (buildingCount(state) < facts.buildingLimit)
    options.push({kind:'gun', cost:facts.gunCosts[1], damage:facts.shotDamage[1]});
  return options.filter(order => order.damage > 0).sort((a, b) => b.damage / b.cost - a.damage / a.cost)[0];
}

function buyAvailable(state, facts, tick) {
  for (;;) {
    const order = resourceOrder(state, facts) ?? gunOrder(state, facts);
    if (!order || order.cost > state.ore) return;
    state.ore -= order.cost; state.spent += order.cost;
    if (order.kind === 'worker') state.assembling.push(tick + facts.assemblyTicks);
    else if (order.kind === 'mine') order.site.level++;
    else if (order.kind === 'gun') state.guns.push(1);
    else state.guns[order.index]++;
  }
}

function economyTick(state, facts, tick) {
  state.workers += state.assembling.filter(due => due <= tick).length;
  state.assembling = state.assembling.filter(due => due > tick);
  if (tick > 0 && tick % facts.productionTicks === 0) {
    const income = miningSlots(state, facts).slice(0, state.workers).reduce((sum, rate) => sum + rate, 0);
    state.ore += income; state.produced += income;
  }
  buyAvailable(state, facts, tick);
  assert.equal(state.ore + state.spent, facts.initialOre + state.produced, 'ore must be conserved');
  assert.ok(state.ore >= 0, 'purchases cannot borrow future income');
}

function fleetDps(state, facts) {
  return state.guns.reduce((sum, level) => sum + facts.shotDamage[level], 0) / (facts.cooldownTicks * facts.tickSeconds);
}

function inventory(state, facts) {
  return {guns:state.guns.length, gunLevels:state.guns.reduce((counts, level) =>
    ({...counts, [level]:(counts[level] ?? 0) + 1}), {}), workers:state.workers,
    mines:state.sites.filter(site => site.level > 0).length, ore:state.ore,
    produced:state.produced, spent:state.spent, theoreticalDps:fleetDps(state, facts)};
}

// ---- Damage exists only after a wave arrives; each next wave is a deadline ----

function applyCapacity(wave, dps, tick, seconds) {
  const damage = dps * seconds;
  wave.capacity += damage;
  if (wave.remaining > 0 && damage >= wave.remaining) wave.clearTick = tick + wave.remaining / damage;
  wave.remaining = Math.max(0, wave.remaining - damage);
}

function finishWave(wave, state, facts) {
  wave.margin = wave.capacity / wave.hp;
  wave.passed = wave.remaining <= 1e-7;
  wave.clearSeconds = wave.clearTick === null ? null : (wave.clearTick - wave.tick) * facts.tickSeconds;
  wave.end = inventory(state, facts);
  return wave;
}

export function capacityRun(facts, sites, waves, options) {
  const state = {ore:facts.initialOre, workers:facts.initialWorkers, assembling:[], sites:[], guns:[], produced:0, spent:0};
  const discoveryTicks = Math.max(1, Math.round(options.discoveryMinutes * 60 / facts.tickSeconds));
  const results = []; let active = null, next = 0, discovered = 0;
  for (let tick = 0; tick < waves.at(-1).deadline; tick++) {
    if (active && tick === active.deadline) {results.push(finishWave(active, state, facts)); active = null;}
    if (tick % discoveryTicks === 0 && discovered < sites.length) state.sites.push({...sites[discovered++], discoveredTick:tick});
    economyTick(state, facts, tick);
    if (waves[next]?.tick === tick) active = {...waves[next++], remaining:waves[next - 1].hp, capacity:0, clearTick:null, start:inventory(state, facts)};
    if (active) applyCapacity(active, fleetDps(state, facts) * options.multiplier, tick, facts.tickSeconds);
  }
  results.push(finishWave(active, state, facts));
  return {passed:results.every(wave => wave.passed), waves:results, inventory:inventory(state, facts),
    observedUntilMinutes:waves.at(-1).deadline * facts.tickSeconds / 60,
    discoveredSites:state.sites.map(({x, y, rate, level, discoveredTick}) => ({x, y, rate, level, discoveredTick}))};
}

// ---- A concise report; the optional JSON retains every wave and assumption ----

const assumptions = [
  'One initially known resource site; one further actual map deposit every discovery interval, nearest Manhattan distance first.',
  'Discovery is free. Mining slots and hired workers are paid at actual prices; hiring retains its assembly delay without occupying an existing miner.',
  'Construction, mine upgrades, artillery kit deliveries, worker relocation and hauling are instantaneous; all workers may mine.',
  'Prioritize productive mining slots and workers, saving for the next resource purchase; spend remaining ore on the best damage-per-ore artillery purchase.',
  'Use the actual building and worker limits. Existing assets are never lost; no ore is spent on towers, shields, repairs or exploring.',
  'Shots use maximum point-blank damage with perfect target allocation, no overkill, unlimited target access and no range or obstruction loss.',
  'The multiplier reduces that theoretical continuous DPS. Unused damage is discarded; each wave must clear before the next spawn.',
  'Wave budgets are independent: a missed deadline fails the test, and surviving HP does not carry into later windows.',
  'This checks one optimistic investment policy over the stated horizon. Passing does not establish real-map survival, optimal play or a nest victory.'
];

function describeWave(wave, facts, multiplier) {
  const minute = (wave.tick * facts.tickSeconds / 60).toFixed(1);
  const dps = wave.start.theoreticalDps * multiplier;
  return `${minute}m: ${wave.count} enemies / ${wave.hp} HP; ${dps.toFixed(1)} effective DPS at spawn; ` +
    `${wave.clearSeconds === null ? 'MISSED deadline' : `cleared in ${wave.clearSeconds.toFixed(2)}s`}; capacity ${wave.margin.toFixed(2)}x HP`;
}

function printReport(report) {
  const {facts, options, result} = report, weakest = result.waves.reduce((a, b) => a.margin < b.margin ? a : b);
  console.log(`max-dps-test ${result.passed ? 'PASS' : 'FAIL'}: discovery ${options.discoveryMinutes}m, multiplier ${options.multiplier}, seed ${options.seed}`);
  console.log(`Coverage: waves spawning through ${options.minutes}m; final wave checked through its next spawn at ${result.observedUntilMinutes}m.`);
  console.log(`Model: ${facts.initialOre} starting ore / ${facts.initialWorkers} workers; mine costs ${facts.mineCosts.slice(1)}; gun costs ${facts.gunCosts.slice(1)}; maximum shots ${facts.shotDamage.slice(1)} every ${facts.cooldownTicks * facts.tickSeconds}s.`);
  console.log(`First wave: ${describeWave(result.waves[0], facts, options.multiplier)}`);
  console.log(`Tightest wave: ${describeWave(weakest, facts, options.multiplier)}`);
  const bosses = result.waves.filter(wave => wave.kind === 2);
  for (const wave of new Set([bosses[0], bosses.at(-1)].filter(Boolean))) console.log(`Boss wave: ${describeWave(wave, facts, options.multiplier)}`);
  console.log(`${result.waves.filter(wave => wave.passed).length}/${result.waves.length} waves clear before the next; ${result.inventory.guns} guns, ${result.inventory.mines} mines, ${result.inventory.workers} workers at the end.`);
  console.log('Wave windows are independent: surviving HP from a failed window is not carried into later windows.');
  console.log('Optimistic bound: free discovery, construction, relocation and hauling; perfect range/target access; no losses. This is not a survival or victory proof.');
}

async function main(args) {
  const usage = 'usage: scripts/max-dps-test [--discovery-minutes 3] [--multiplier 0.5] [--minutes 360] [--seed 1] [--output REPORT.json]';
  if (args[0] === '--help' || args[0] === '-h') {console.log(usage); return;}
  assert.ok(args.length > 0, usage);
  const options = configuration(args.slice(1)), path = resolve(args[0]), bytes = readFileSync(path);
  const instance = instantiate(loadWasm(bytes));
  try {
    const query = (name, value = 0) => invokeEntry(instance, [queries[name], value, options.seed]);
    const facts = modelFacts(query), sites = resourceSites(query), waves = wavesThrough(query, options.minutes * 60 / facts.tickSeconds);
    checkCapacityContract(facts);
    const report = {test:'max-dps-test', probe:{path, sha256:createHash('sha256').update(bytes).digest('hex')},
      options, assumptions, facts, result:capacityRun(facts, sites, waves, options)};
    printReport(report);
    if (options.output) writeFileSync(options.output, `${JSON.stringify(report, null, 2)}\n`);
    if (!report.result.passed) process.exitCode = 1;
  } finally { closeInstance(instance); }
}

// ---- Tests ----

function checkCapacityContract(facts) {
  const fixed = {...facts, initialOre:facts.gunCosts[1], buildingLimit:1};
  const wave = {tick:1000, deadline:1000 + facts.cooldownTicks, hp:facts.shotDamage[1], count:1, kind:0};
  const options = {discoveryMinutes:3, multiplier:1};
  assert.equal(capacityRun(fixed, [], [wave], options).passed, true, 'one firing period supplies exactly one shot');
  assert.equal(capacityRun(fixed, [], [wave], {...options, multiplier:0.5}).passed, false, 'the utilization multiplier affects the deadline');
  assert.equal(capacityRun(fixed, [], [{...wave, hp:wave.hp * 2}], options).passed, false, 'idle time cannot bank damage');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await main(process.argv.slice(2));
