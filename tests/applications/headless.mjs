// Integration contracts run the actual browser package. Fixture edits establish
// visibility/terminal boundaries; they never implement simulation transitions.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {ReducerRuntime} from '../../src/application/runtime.mjs';
import {openEnvironment, decodeObservation} from '../../apps/siegework/headless.mjs';
import {MAP_WIDTH,MAP_HEIGHT,colony, restoreColony, at, pixelAt, setWorker} from './colony-state.mjs';

const directory = resolve(process.argv[2]);
const manifest = JSON.parse(readFileSync(join(directory, 'manifest.json'))), bytes = readFileSync(join(directory, manifest.module));
const wait = {type: 'wait'};
let passed = 0;
async function test(name, run) { await run(); console.log(`ok ${++passed} - ${name}`); }
async function direct(seed = 1) {
  const runtime = new ReducerRuntime(); await runtime.replace(runtime.prepare(bytes, manifest));
  await runtime.initialize(1); await runtime.initialize(2);
  await runtime.dispatch(1, runtime.command('match', 'new-run-seed', [seed])); return runtime;
}
const send = (runtime, name, args = []) => runtime.dispatch(1, runtime.command('match', name, args));
const snapshot = async environment => (await environment.diagnostics()).snapshot;
const extractor = observation => ({type: 'build', ...observation.buildCandidates.find(value => value.kind === 1)});
async function start(environment) {
  const {observation} = await environment.observe(), action = extractor(observation);
  await environment.step(action, 0); return action;
}
async function fixtureEnvironment(edit, options = {}) {
  const dispatch = ReducerRuntime.prototype.dispatch;
  ReducerRuntime.prototype.dispatch = async function(owner, command, ...rest) {
    const output = await dispatch.call(this, owner, command, ...rest);
    if (owner === 1 && command.handler === this.command('match', 'new-run-seed', [1]).handler) {
      const world = colony(this.snapshot(1)); edit(world); await restoreColony(this, world);
    }
    return output;
  };
  try { return await openEnvironment(directory, options); }
  finally { ReducerRuntime.prototype.dispatch = dispatch; }
}

await test('default observations are player knowledge and the headless path does not render', async () => {
  assert.equal(manifest.settings.recording.enabled,false,'current-state observations do not need replay enabled');
  const view = ReducerRuntime.prototype.view;
  ReducerRuntime.prototype.view = () => { throw new Error('headless rendering'); };
  try {
    const environment = await openEnvironment(directory), {observation} = await environment.observe();
    assert.equal(observation.tick, 0); assert.equal(observation.started, 0); assert.equal(observation.ore, 160);
    assert.equal(observation.nests.length, 0); assert.equal(observation.enemies.length, 0);
    assert.ok(observation.tiles.length > 200 && observation.tiles.length < MAP_WIDTH * MAP_HEIGHT);
    assert.ok(observation.buildCandidates.every(candidate => candidate.kind === 1));
    assert.equal(observation.purchaseReasons.fabricate, 38);
    assert.equal('nestHp' in observation, false); assert.equal('oreRemaining' in observation, false);
    await assert.rejects(environment.diagnostics(), /disabled/); await start(environment);
    assert.equal((await environment.step(wait, 10)).info.ticksAdvanced, 10); await environment.close();
  } finally { ReducerRuntime.prototype.view = view; }
});

await test('same seeds and public actions match exact browser World snapshots and observations', async () => {
  for (const seed of [1, 42, 65535]) {
    const environment = await openEnvironment(directory, {diagnostics: true}), runtime = await direct(seed);
    const initial = await environment.reset(seed), build = extractor(initial.observation);
    assert.deepEqual(await snapshot(environment), runtime.snapshot(1));
    const actions = [[{type: 'fabricate'}, 'fabricate-worker', [], 8],
      [build, 'build-cell', [build.kind, build.cell], 0], [wait, null, [], 30],
      [{type: 'fabricate'}, 'fabricate-worker', [], 2], [{type: 'repair'}, 'repair-hub', [], 0],
      [{type: 'pause', paused: true}, 'pause-colony', [1], 10], [wait, null, [], 5],
      [{type: 'pause', paused: false}, 'pause-colony', [0], 10],
      [{type: 'upgrade', cell: build.cell}, 'upgrade', [build.cell % MAP_WIDTH, Math.floor(build.cell / MAP_WIDTH)], 0],
      [{type: 'cancel', cell: build.cell}, 'cancel-building', [build.cell % MAP_WIDTH, Math.floor(build.cell / MAP_WIDTH)], 1],
      [{type: 'relocate', from: build.cell, to: build.cell + 1}, 'relocate-building', [build.cell, build.cell + 1], 1]];
    for (const [action, name, args, ticks] of actions) {
      const result = await environment.step(action, ticks);
      if (name) await send(runtime, name, args);
      for (let index = 0; index < ticks; index++) await send(runtime, 'advance');
      assert.deepEqual(await snapshot(environment), runtime.snapshot(1), `${seed}/${action.type}`);
      assert.deepEqual(result.observation, decodeObservation(runtime.observe()));
    }
    assert.deepEqual(await environment.reset(seed), initial);
    await environment.close(); await runtime.close();
  }
});

await test('complete request validation and FIFO ownership prevent partial malformed actions', async () => {
  for (const options of [{horizonTicks: null}, {maxTicksPerStep: null}, {reward: {tick: Infinity}}])
    await assert.rejects(openEnvironment(directory, options));
  const environment = await openEnvironment(directory, {diagnostics: true}), build = extractor((await environment.observe()).observation);
  const before = await snapshot(environment);
  for (const [action, ticks] of [[build, -1], [build, 601], [build, NaN], [build, 1.2],
    [{...build, kind: 4}, 1], [{...build, cell: (MAP_WIDTH*MAP_HEIGHT)}, 1], [{...build, extra: 1}, 1],
    [{type: 'new-run-seed'}, 1], [{type: 'pause', paused: 1}, 1], [null, 0]]) {
    await assert.rejects(environment.step(action, ticks)); assert.deepEqual(await snapshot(environment), before);
  }
  await assert.rejects(environment.reset(0)); await assert.rejects(environment.restore('unknown'));
  assert.deepEqual(await snapshot(environment), before);
  const pending = environment.step(build, 0); build.cell = 0;
  const next = environment.step(wait, 5), observation = environment.observe();
  await pending; assert.equal((await next).info.episodeTicks, 5); assert.equal((await observation).observation.tick, 5);
  await environment.close(); assert.equal(environment.close(), environment.close());
  await assert.rejects(environment.reset(1), /closed/); await assert.rejects(environment.observe(), /closed/);
});

await test('Scavenge exposes its quote and pending worker through the same headless action protocol', async () => {
  const environment = await fixtureEnvironment(world => {
    const site=at(world,12,22),point=pixelAt(world,12,22);
    world.started=true;world.spent=25;world.ore-=25;world.bots.length=1;setWorker(world,0,{x:12,y:22});
    world.buildings=[{id:world.nextId++,kind:3,...site,level:1,hp:90,stock:0,stage:2,cooldown:0,
      aimX:point.x,aimY:point.y,armed:0,source:0,moveX:-1,moveY:-1}];world.surveys.push({...site,radius:7});
  });
  const before=(await environment.observe()).observation,site=before.buildings[0];
  assert.equal(site.scavengeRefund,5);assert.equal(site.scavenging,0);
  const ordered=await environment.step({type:'scavenge',cell:site.cell},0);
  assert.equal(ordered.observation.ore,before.ore);assert.equal(ordered.observation.buildings[0].scavenging,1);
  const done=await environment.step(wait,21);assert.equal(done.observation.buildings.length,0);
  assert.equal(done.observation.ore,before.ore+5);await environment.close();
});

await test('horizon, pause, zero ticks, reward and opaque checkpoint accounting restore together', async () => {
  const environment = await openEnvironment(directory, {horizonTicks: 5, maxTicksPerStep: 8, reward: {tick: 0.25}});
  assert.equal((await environment.step(wait, 8)).info.episodeTicks, 0);
  await start(environment); const {checkpoint: zero} = await environment.checkpoint();
  assert.equal((await environment.step({type: 'pause', paused: true}, 8)).info.episodeTicks, 0);
  await environment.step({type: 'pause', paused: false}, 0);
  assert.equal((await environment.step(wait, 4)).reward, 1);
  const {checkpoint} = await environment.checkpoint(), result = await environment.step(wait, 8);
  assert.equal(result.terminated, false); assert.equal(result.truncated, true); assert.equal(result.reward, 0.25);
  assert.equal(result.info.ticksAdvanced, 1); assert.equal(result.info.episodeReward, 1.25);
  await assert.rejects(environment.step(wait, 0), /ended/);
  const restored = await environment.restore(checkpoint);
  assert.equal(restored.info.episodeTicks, 4); assert.equal(restored.info.episodeReward, 1);
  assert.deepEqual(await environment.step(wait, 8), result);
  await environment.restore(zero); assert.equal((await environment.observe()).info.episodeTicks, 0);
  await environment.reset(1); await assert.rejects(environment.restore(checkpoint), /unknown/);
  await environment.close();
});

await test('game-rejected purchases preserve their decision and still perform the explicitly requested wait', async () => {
  const environment = await openEnvironment(directory), opening = await environment.step({type: 'fabricate'}, 5);
  assert.equal(opening.observation.hub.notice, 38); assert.equal(opening.observation.ore, 160); assert.equal(opening.info.ticksAdvanced, 0);
  const build = await start(environment), rejected = await environment.step(build, 3);
  assert.equal(rejected.info.buildReason, 3); assert.equal(rejected.observation.ore, 135);
  assert.equal(rejected.info.ticksAdvanced, 3); await environment.close();
});

await test('hidden nest health and enemies do not appear through observations or action previews', async () => {
  const runtime = await direct(), world = colony(runtime.snapshot(1)); world.started = true;
  await restoreColony(runtime, world); const before = decodeObservation(runtime.observe()), nest = world.nests[0];
  nest.hp = 13; world.enemies.push({id: world.nextId++, x: nest.x * 40 + 20, y: nest.y * 40 + 20,
    hp: 80, kind: 0, target: 0, path: []});
  await restoreColony(runtime, world); assert.deepEqual(decodeObservation(runtime.observe()), before);
  world.surveys.push({x: nest.x, y: nest.y, radius: 4}); await restoreColony(runtime, world);
  const known = decodeObservation(runtime.observe()); assert.equal(known.enemies.length, 0);
  assert.deepEqual(known.nests, [{id: nest.id, cell: nest.x + nest.y * MAP_WIDTH, hp: -1}]);
  for (const tile of known.tiles.filter(tile => !tile.visible)) {
    assert.equal(tile.oreRemaining, -1); assert.equal(tile.rockRemaining, -1);
    assert.equal(known.buildCandidates.some(candidate => candidate.cell === tile.cell), false);
  }
  world.bots[0].x = nest.x * 40 + 20; world.bots[0].y = nest.y * 40 + 20;
  await restoreColony(runtime, world); const visible = decodeObservation(runtime.observe());
  assert.equal(visible.nests[0].hp, 13); assert.equal(visible.enemies.length, 1);
  assert.ok(world.deposits.some(deposit => !visible.tiles.some(tile => tile.cell === deposit.cell)));
  await runtime.close();
});

await test('actual victory takes precedence over the horizon and cannot earn terminal reward twice', async () => {
  const environment = await fixtureEnvironment(world => {
    const nest = world.nests[0]; world.started = true; world.nests.forEach(value => value.hp = 0); nest.hp = 6;
    world.spent = 50; world.ore = 110;
    world.buildings.push({id: world.nextId++, kind: 2, x: nest.x, y: nest.y + 4, level: 1, hp: 100,
      stock: 0, stage: 2, cooldown: 0, aimX: nest.x * 40 + 20, aimY: (nest.y + 4) * 40 + 20,
      armed: 0, source: 0, moveX: -1, moveY: -1});
    world.surveys.push({x: nest.x, y: nest.y + 4, radius: 6});
  }, {horizonTicks: 1});
  const result = await environment.step(wait, 5);
  assert.equal(result.terminated, true); assert.equal(result.truncated, false); assert.equal(result.reward, 1);
  assert.equal(result.info.outcome, 'victory'); assert.equal(result.info.ticksAdvanced, 1);
  const {checkpoint} = await environment.checkpoint(); await environment.restore(checkpoint);
  await assert.rejects(environment.step(wait, 0), /ended/); await environment.close();
});

await test('actual hub destruction is a terminal loss, not horizon truncation', async () => {
  const environment = await fixtureEnvironment(world => {
    const hub = world.surveys[0]; world.started = true; world.hull = 1; world.tick = 9;
    world.enemies.push({id: world.nextId++, x: hub.x * 40 + 20, y: hub.y * 40 + 20,
      hp: 80, kind: 0, target: 0, path: []});
  }, {horizonTicks: 1});
  const result = await environment.step(wait, 5);
  assert.equal(result.terminated, true); assert.equal(result.truncated, false); assert.equal(result.reward, -1);
  assert.equal(result.info.outcome, 'defeat'); await environment.close();
});

await test('resign is a distinct intact terminal result with zero advanced ticks and no defeat reward', async () => {
  const environment=await openEnvironment(directory,{diagnostics:true});await start(environment);
  const before=colony(await snapshot(environment)),result=await environment.step({type:'resign'},20);
  assert.equal(result.terminated,true);assert.equal(result.truncated,false);assert.equal(result.info.outcome,'resigned');
  assert.equal(result.info.ticksAdvanced,0);assert.equal(result.reward,0);assert.equal(result.observation.hull,300);
  assert.equal(result.observation.tiles.length,(MAP_WIDTH*MAP_HEIGHT));assert.deepEqual(colony(await snapshot(environment)),{...before,outcome:4});
  await assert.rejects(environment.step(wait,1),/episode ended/);await environment.reset(1);
  assert.equal((await environment.observe()).observation.outcome,0);await environment.close();
});

await test('partial simulation faults report confirmed progress and require fresh-instance recovery', async () => {
  const environment = await openEnvironment(directory), build = await start(environment);
  const {checkpoint} = await environment.checkpoint(), dispatch = ReducerRuntime.prototype.dispatch;
  let ticks = 0;
  ReducerRuntime.prototype.dispatch = async function(owner, command, ...rest) {
    if (owner === 1 && command.handler === this.command('match', 'advance').handler && ++ticks === 2)
      throw new Error('private diagnostic must not reach a policy');
    return dispatch.call(this, owner, command, ...rest);
  };
  try {
    await assert.rejects(environment.step(wait, 3), error => {
      assert.doesNotMatch(error.message, /private diagnostic/);
      assert.deepEqual(error.info, {ticksRequested: 3, confirmedTicksAdvanced: 1, episodeTicks: 1, recoveryRequired: true}); return true;
    });
  } finally { ReducerRuntime.prototype.dispatch = dispatch; }
  await assert.rejects(environment.observe(), /faulted/); await assert.rejects(environment.checkpoint(), /faulted/);
  await environment.restore(checkpoint); assert.equal((await environment.step(wait, 3)).info.episodeTicks, 3);
  await environment.reset(1); assert.equal((await environment.step(build, 0)).info.buildReason, 0); await environment.close();
});

await test('observation, decoding and pre-step inspection faults share a private recovery boundary', async () => {
  const environment = await openEnvironment(directory), secret = new Error('private World diagnostic: nest hp=13');
  for (const [reader, operation, decode] of [['observe', 'observe', false], ['observe', 'observe', true],
    ['observe', 'step', false], ['inspect', 'step', false]]) {
    await environment.reset(1); await start(environment); await environment.step(wait, 3);
    const before = await environment.observe(), {checkpoint} = await environment.checkpoint();
    const original = ReducerRuntime.prototype[reader], ticks = operation === 'step' ? 2 : 0;
    ReducerRuntime.prototype[reader] = () => { if (decode) return [[999]]; throw secret; };
    try {
      await assert.rejects(operation === 'step' ? environment.step(wait, ticks) : environment.observe(), error => {
        assert.equal(error.message, 'simulation operation failed; reset or restore a checkpoint');
        if (decode) assert.match(error.cause.message, /unsupported observation row/);
        else assert.equal(error.cause, secret);
        assert.deepEqual(error.info, {ticksRequested: ticks, confirmedTicksAdvanced: reader === 'observe' && operation === 'step' ? 2 : 0,
          episodeTicks: reader === 'observe' && operation === 'step' ? 5 : 3, recoveryRequired: true});
        return true;
      });
    } finally { ReducerRuntime.prototype[reader] = original; }
    await assert.rejects(environment.observe(), /faulted/); await assert.rejects(environment.step(wait, 0), /faulted/);
    await assert.rejects(environment.checkpoint(), /faulted/);
    assert.deepEqual(await environment.restore(checkpoint), before); await environment.step(wait, 0);
    const observe = ReducerRuntime.prototype.observe;
    ReducerRuntime.prototype.observe = () => { throw secret; };
    try { await assert.rejects(environment.observe(), /simulation operation failed/); }
    finally { ReducerRuntime.prototype.observe = observe; }
    const reset = await environment.reset(42); assert.equal(reset.info.seed, 42); assert.equal(reset.info.episodeTicks, 0);
    await environment.observe();
  }
  await environment.close();
});

await test('failed reset and restore candidates sanitize errors without replacing the healthy episode', async () => {
  const environment = await openEnvironment(directory, {reward: {tick: 0.25}});
  await start(environment); await environment.step(wait, 3);
  const saved = await environment.observe(), {checkpoint} = await environment.checkpoint();
  await environment.step(wait, 2); const before = await environment.observe();
  for (const operation of [() => environment.reset(42), () => environment.restore(checkpoint)]) {
    const observe = ReducerRuntime.prototype.observe, secret = new Error('private candidate World diagnostic: nest hp=13');
    ReducerRuntime.prototype.observe = () => { throw secret; };
    try {
      await assert.rejects(operation(), error => {
        assert.equal(error.message, 'simulation preparation failed; current episode was not replaced');
        assert.equal(error.cause, secret);
        assert.deepEqual(error.info, {episodeTicks: 5, episodeReward: 1.25, recoveryRequired: false}); return true;
      });
    } finally { ReducerRuntime.prototype.observe = observe; }
    assert.deepEqual(await environment.observe(), before); await environment.step(wait, 0);
  }
  assert.deepEqual(await environment.restore(checkpoint), saved); await environment.close();
});

await test('checkpoint IDs are scoped, bounded, opaque and independent of the hidden World', async () => {
  const first = await openEnvironment(directory), second = await openEnvironment(directory);
  const checkpoint = await first.checkpoint(); assert.deepEqual(Object.keys(checkpoint), ['checkpoint']);
  await assert.rejects(second.restore(checkpoint.checkpoint), /unknown/);
  for (let index = 1; index < 16; index++) await first.checkpoint();
  await assert.rejects(first.checkpoint(), /limit/); await first.reset(1); await first.checkpoint();
  await first.close(); await second.close();
});

function subprocess(input, args = [], nodeArgs = []) {
  const child = spawnSync(process.execPath, [...nodeArgs, resolve(import.meta.dirname, '../../apps/siegework/environment-cli.mjs'), ...args, directory],
    {input, encoding: 'utf8', timeout: 30000, maxBuffer: 8 * 1024 * 1024});
  assert.ifError(child.error); assert.equal(child.status, 0, child.stderr); assert.equal(child.stderr, '');
  return child.stdout.trim().split('\n').map(line => JSON.parse(line));
}
const wire = messages => messages.map(message => typeof message === 'string' ? message : JSON.stringify(message)).join('\n') + '\n';
await test('JSONL subprocess validates framing and recovers after malformed and oversized requests', async () => {
  const output = subprocess(wire([{id: 1, method: 'reset', params: {seed: 42}}, '{', 'x'.repeat(65537),
    {id: 2, method: 'step', params: {action: {type: 'fabricate'}, ticks: -1}},
    {id: 6, method: 'step', params: {action: null, ticks: 1}},
    {id: 7, method: 'step', params: {action: {type: 'fabricate'}, ticks: null}},
    {id: 3, method: 'observe'}, {id: 4, method: 'diagnostics'}, {id: 5, method: 'close'}]));
  assert.equal(output.length, 9); assert.equal(output[0].result.observation.seed, 42);
  assert.ok(output[1].error); assert.match(output[2].error.message, /65536/); assert.ok(output[3].error);
  assert.ok(output[4].error); assert.ok(output[5].error);
  assert.equal(output[6].result.observation.ore, 160); assert.equal(output[6].result.observation.hub.notice, 0);
  assert.match(output[7].error.message, /disabled/); assert.deepEqual(output[8].result, {});
});

await test('MCP subprocess negotiates lifecycle, lists tools, pages knowledge and separates protocol/tool errors', async () => {
  const rpc = (id, method, params) => ({jsonrpc: '2.0', id, method, ...(params ? {params} : {})});
  const output = subprocess(wire([rpc(1, 'tools/list'), rpc(2, 'initialize', {protocolVersion: '2025-11-25',
    capabilities: {}, clientInfo: {name: 'integration-check', version: '1'}}),
    {jsonrpc: '2.0', method: 'notifications/initialized'}, rpc(3, 'ping'), rpc(4, 'tools/list'),
    rpc(5, 'tools/call', {name: 'siegework_reset', arguments: {seed: 1}}),
    rpc(6, 'tools/call', {name: 'siegework_observe', arguments: {limit: 1, offset: 0}}),
    rpc(7, 'tools/call', {name: 'siegework_step', arguments: {action: {type: 'build', kind: 9, cell: 0}, ticks: 1}}),
    rpc(8, 'tools/call', {name: 'unknown'}), rpc(9, 'tools/call', {name: 'siegework_observe', arguments: []}),
    rpc(10, 'unknown'), '{', rpc(11, 'tools/call', {name: 'siegework_observe', arguments: {offset: 1, limit: 1}})
  ]), ['--mcp']);
  assert.equal(output.length, 12); const byId = new Map(output.map(message => [message.id, message]));
  assert.equal(byId.get(1).error.code, -32000); assert.equal(byId.get(2).result.protocolVersion, '2025-11-25');
  assert.deepEqual(byId.get(3).result, {}); assert.equal(byId.get(4).result.tools.length, 5);
  assert.equal(byId.get(5).result.isError, false); const page = byId.get(6).result.structuredContent;
  assert.equal(page.observation.tiles.length, 1); assert.ok(page.page.collections.tiles.omitted > 200);
  assert.equal(byId.get(7).result.isError, true); assert.equal(byId.get(8).error.code, -32602);
  assert.equal(byId.get(9).error.code, -32602); assert.equal(byId.get(10).error.code, -32601);
  assert.equal(byId.get(null).error.code, -32700);
  assert.equal(byId.get(11).result.structuredContent.observation.hub.notice, 0);
  assert.notEqual(byId.get(11).result.structuredContent.observation.tiles[0].cell, page.observation.tiles[0].cell);
});

await test('MCP rejects malformed parameter objects without acknowledging invalid notifications', async () => {
  const rpc = (id, method, params) => ({jsonrpc: '2.0', id, method, params});
  const initialize = capabilities => ({protocolVersion: '2025-11-25', capabilities, clientInfo: {name: 'shape-check', version: '1'}});
  const output = subprocess(wire([rpc(1, 'initialize', initialize([])), rpc(2, 'initialize', initialize({})),
    {jsonrpc: '2.0', method: 'notifications/initialized', params: 123}, rpc(3, 'tools/list'),
    rpc(4, 'ping', 123), rpc(5, 'ping', []), rpc(6, 'ping', null),
    {jsonrpc: '2.0', method: 'notifications/initialized', params: []}, rpc(7, 'tools/list'),
    {jsonrpc: '2.0', method: 'notifications/initialized', params: {}}, rpc(8, 'tools/list'), rpc(9, 'ping', {})]), ['--mcp']);
  assert.equal(output.length, 9); const byId = new Map(output.map(message => [message.id, message]));
  for (const id of [1, 4, 5, 6]) assert.equal(byId.get(id).error.code, -32602);
  assert.equal(byId.get(2).result.protocolVersion, '2025-11-25');
  for (const id of [3, 7]) assert.equal(byId.get(id).error.code, -32000);
  assert.equal(byId.get(8).result.tools.length, 5); assert.deepEqual(byId.get(9).result, {});
});

await test('JSONL and MCP serialize safe observation errors without exposing their trusted Node cause', async () => {
  const preload = `import {ReducerRuntime} from ${JSON.stringify(new URL('../../src/application/runtime.mjs', import.meta.url).href)};
    const observe = ReducerRuntime.prototype.observe; let calls = 0;
    ReducerRuntime.prototype.observe = function() {
      if (++calls === 2) throw new Error('private World diagnostic: nest hp=13');
      return observe.call(this);
    };`;
  const nodeArgs = ['--import', `data:text/javascript,${encodeURIComponent(preload)}`];
  const output = subprocess(wire([{id: 1, method: 'observe'}, {id: 2, method: 'step', params: {ticks: 0}},
    {id: 3, method: 'reset'}, {id: 4, method: 'observe'}, {id: 5, method: 'close'}]), [], nodeArgs);
  assert.doesNotMatch(JSON.stringify(output), /private World|nest hp/);
  assert.match(output[0].error.message, /simulation operation failed/); assert.equal(output[0].error.info.recoveryRequired, true);
  assert.match(output[1].error.message, /faulted/); assert.equal(output[3].result.observation.tick, 0);
  const rpc = (id, method, params) => ({jsonrpc: '2.0', id, method, params});
  const mcp = subprocess(wire([rpc(1, 'initialize', {protocolVersion: '2025-11-25', capabilities: {}, clientInfo: {name: 'fault-check', version: '1'}}),
    {jsonrpc: '2.0', method: 'notifications/initialized'}, rpc(2, 'tools/call', {name: 'siegework_observe'}),
    rpc(3, 'tools/call', {name: 'siegework_step', arguments: {ticks: 0}}),
    rpc(4, 'tools/call', {name: 'siegework_reset'}), rpc(5, 'tools/call', {name: 'siegework_observe'})]), ['--mcp'], nodeArgs);
  assert.doesNotMatch(JSON.stringify(mcp), /private World|nest hp/);
  assert.equal(mcp[1].result.isError, true); assert.equal(JSON.parse(mcp[1].result.content[0].text).info.recoveryRequired, true);
  assert.match(mcp[2].result.content[0].text, /faulted/); assert.equal(mcp[4].result.structuredContent.observation.tick, 0);
});

await test('bounded batch diagnostic reports observation sizes and actual simulation throughput', async () => {
  const environment = await openEnvironment(directory), initial = await environment.observe();
  await start(environment); const begin = performance.now(), result = await environment.step(wait, 600);
  console.log(JSON.stringify({diagnostic: 'headless batch (not a clean benchmark)', generation: manifest.generation,
    ticksAdvanced: result.info.ticksAdvanced, milliseconds: Math.round(performance.now() - begin),
    initialObservationBytes: Buffer.byteLength(JSON.stringify(initial.observation)),
    tick600ObservationBytes: Buffer.byteLength(JSON.stringify(result.observation))}));
  assert.equal(result.info.ticksAdvanced, 600); assert.equal(result.observation.tick, 600); await environment.close();
});
console.log(`${passed} headless environment checks passed`);
