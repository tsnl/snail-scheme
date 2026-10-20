// The browser's compiled reducer owns the game. This host owns only request
// ordering, episode limits, public observations and an optional research reward.
import {readFile} from 'node:fs/promises';
import {resolve, join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {ReducerRuntime} from '../../src/application/runtime.mjs';

// ---- Parse complete requests before any transition ----

export function integer(value, minimum, maximum, name) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum)
    throw new Error(`${name} must be an integer in ${minimum}..${maximum}`);
  return value;
}
export function object(value, keys, name) {
  if (!value || typeof value !== 'object' || Array.isArray(value)
      || Object.keys(value).some(key => !keys.includes(key))) throw new Error(`invalid ${name} fields`);
  return value;
}
export function parseAction(action, width = 64, height = 64) {
  object(action, ['type', 'kind', 'cell', 'from', 'to', 'paused'], 'action');
  const cell = value => integer(value, 0, width * height - 1, 'cell');
  switch (action.type) {
    case 'wait': case 'fabricate': case 'repair': case 'resign':
      object(action, ['type'], 'action'); return {type: action.type};
    case 'build':
      object(action, ['type', 'kind', 'cell'], 'action');
      return {type: 'build', kind: integer(action.kind, 1, 3, 'kind'), cell: cell(action.cell)};
    case 'upgrade': case 'cancel': case 'scavenge':
      object(action, ['type', 'cell'], 'action'); return {type: action.type, cell: cell(action.cell)};
    case 'relocate':
      object(action, ['type', 'from', 'to'], 'action');
      return {type: 'relocate', from: cell(action.from), to: cell(action.to)};
    case 'pause':
      object(action, ['type', 'paused'], 'action');
      if (typeof action.paused !== 'boolean') throw new Error('paused must be a boolean');
      return {type: 'pause', paused: action.paused};
    default: throw new Error('unknown action type');
  }
}
function commandFor(action, width) {
  switch (action.type) {
    case 'wait': return null;
    case 'build': return ['build-cell', [action.kind, action.cell]];
    case 'upgrade': return ['upgrade', [action.cell % width, Math.floor(action.cell / width)]];
    case 'scavenge': return ['scavenge-building', [action.cell % width, Math.floor(action.cell / width)]];
    case 'cancel': return ['cancel-building', [action.cell % width, Math.floor(action.cell / width)]];
    case 'relocate': return ['relocate-building', [action.from, action.to]];
    case 'fabricate': return ['fabricate-worker', []];
    case 'repair': return ['repair-hub', []];
    case 'resign': return ['resign', []];
    case 'pause': return ['pause-colony', [Number(action.paused)]];
  }
}
const defaultReward = Object.freeze({victory: 1, defeat: -1, delivered: 0, hull: 0, casualties: 0, tick: 0});
function parseReward(value = {}) {
  object(value, Object.keys(defaultReward), 'reward');
  const weights = {...defaultReward, ...value};
  if (Object.values(weights).some(weight => !Number.isFinite(weight) || Math.abs(weight) > 1e6))
    throw new Error('reward weights must be finite numbers with magnitude at most 1000000');
  return Object.freeze(weights);
}
function parseOptions(options) {
  object(options, ['horizonTicks', 'maxTicksPerStep', 'reward', 'diagnostics'], 'options');
  const {horizonTicks = 12000, maxTicksPerStep = 600, reward, diagnostics = false} = options;
  if (typeof diagnostics !== 'boolean')
    throw new Error('diagnostics must be a boolean');
  return {horizonTicks: integer(horizonTicks, 1, 10000000, 'horizonTicks'),
    maxTicksPerStep: integer(maxTicksPerStep, 1, 6000, 'maxTicksPerStep'),
    reward: parseReward(reward), diagnostics};
}

// ---- Decode the Scheme-owned observation rows, never the World codec ----

const fields = (names, values) => Object.fromEntries(names.split(' ').map((name, index) => [name, values[index]]));
export function decodeObservation(rows) {
  const result = {tiles: [], buildings: [], workers: [], enemies: [], nests: [], buildCandidates: []};
  for (const [tag, ...values] of rows) {
    switch (tag) {
      case 0: Object.assign(result, fields('version width height cellSize ticksPerSecond seed', values)); break;
      case 1: Object.assign(result, fields('tick outcome paused started ore hull', values)); break;
      case 2: Object.assign(result, fields('produced delivered spent lostOre kills casualties', values)); break;
      case 3: result.hub = fields('x y capacityLevel capacity pendingWorkers notice', values); break;
      case 4: result.purchaseReasons = fields('fabricate repair upgradeHub', values); break;
      case 10: result.tiles.push(fields('cell visible terrain depositRate oreRemaining rockRemaining', values)); break;
      case 20: result.buildings.push(fields('id kind cell level hp stage', values)); break;
      case 21: Object.assign(result.buildings.at(-1), fields('id stock armed cooldown moveX moveY', values)); break;
      case 22: Object.assign(result.buildings.at(-1), fields('id scavengeRefund scavenging', values)); break;
      case 30: result.workers.push(fields('id x y hp job cargo', values)); break;
      case 40: result.enemies.push(fields('id x y hp kind rank', values)); break;
      case 50: result.nests.push(fields('id cell hp', values)); break;
      case 60: result.buildCandidates.push(fields('cell kind', values)); break;
      default: throw new Error('unsupported observation row');
    }
  }
  if (result.version !== 1 || !result.hub) throw new Error('unsupported player observation');
  return result;
}

// ---- One FIFO, one authoritative runtime, separate episode accounting ----

export async function openEnvironment(directory, options = {}) {
  const config = parseOptions(options), path = resolve(directory);
  const manifest = JSON.parse(await readFile(join(path, 'manifest.json'), 'utf8'));
  if (manifest.settings?.id !== 'siegework-colony-v13' || manifest.settings.observation?.version !== 1)
    throw new Error('expected a Siegework World13 package with observation version 1; rebuild the application');
  const bytes = await readFile(join(path, manifest.module));
  const environment = new SiegeworkEnvironment(bytes, manifest, config);
  try { await environment.reset(1); return environment; }
  catch (error) { await environment.close(); throw error; }
}
class SiegeworkEnvironment {
  #bytes; #manifest; #config; #runtime; #tail = Promise.resolve(); #closing; #faulted = false;
  #elapsed = 0; #reward = 0; #checkpoints = new Map(); #indices;
  constructor(bytes, manifest, config) {
    this.#bytes = bytes; this.#manifest = manifest; this.#config = config;
    this.#indices = new Map(manifest.settings.recording.inspection.fields.map((name, index) => [name, index]));
  }
  #enqueue(operation) {
    if (this.#closing) return Promise.reject(new Error('environment is closed'));
    const result = this.#tail.then(operation);
    this.#tail = result.catch(() => {});
    return result;
  }
  #healthy() {
    if (!this.#runtime) throw new Error('reset the environment first');
    if (this.#faulted) throw new Error('environment faulted; reset or restore a checkpoint');
  }
  #stat(name) { return this.#runtime.inspect(this.#indices.get(name)); }
  #stats(ticksRequested) {
    try { return Object.fromEntries(['tick', 'outcome', 'delivered', 'hull', 'casualties'].map(name => [name, this.#stat(name)])); }
    catch (cause) { throw this.#simulationFailure(cause, ticksRequested); }
  }
  #simulationFailure(cause, ticksRequested = 0, elapsed = this.#elapsed) {
    this.#faulted = true;
    const error = new Error('simulation operation failed; reset or restore a checkpoint', {cause});
    error.info = {ticksRequested, confirmedTicksAdvanced: this.#elapsed - elapsed,
      episodeTicks: this.#elapsed, recoveryRequired: true};
    return error;
  }
  async #fresh(seed, snapshot) {
    const runtime = new ReducerRuntime();
    try {
      await runtime.replace(runtime.prepare(this.#bytes, this.#manifest));
      await runtime.initialize(1); await runtime.initialize(2);
      if (snapshot) await runtime.restore(1, snapshot);
      else await runtime.dispatch(1, runtime.command('match', 'new-run-seed', [seed]));
      return {runtime, observation: decodeObservation(runtime.observe())};
    } catch (cause) {
      await runtime.close();
      const error = new Error('simulation preparation failed; current episode was not replaced', {cause});
      error.info = {episodeTicks: this.#elapsed, episodeReward: this.#reward, recoveryRequired: this.#faulted};
      throw error;
    }
  }
  async #install(candidate, elapsed = 0, reward = 0) {
    const previous = this.#runtime;
    this.#runtime = candidate.runtime; this.#elapsed = elapsed; this.#reward = reward; this.#faulted = false;
    await previous?.close();
    return this.#result(candidate.observation);
  }
  reset(seed = 1) {
    return this.#enqueue(async () => {
      integer(seed, 1, 65535, 'seed');
      const candidate = await this.#fresh(seed);
      const result = await this.#install(candidate);
      this.#checkpoints.clear(); return result;
    });
  }
  observe() {
    return this.#enqueue(() => {
      this.#healthy();
      try { return this.#result(decodeObservation(this.#runtime.observe())); }
      catch (cause) { throw this.#simulationFailure(cause); }
    });
  }
  #result(observation, extra = {}) {
    const terminated = observation.outcome !== 0, truncated = !terminated && this.#elapsed >= this.#config.horizonTicks;
    return {observation, info: {generation: this.#manifest.generation, seed: observation.seed,
      simulationTick: observation.tick, elapsedSeconds: observation.tick / observation.ticksPerSecond,
      episodeTicks: this.#elapsed, episodeReward: this.#reward, horizonTicks: this.#config.horizonTicks,
      maxTicksPerStep: this.#config.maxTicksPerStep,
      terminated, truncated, outcome: ({0: 'ongoing', 1: 'defeat', 3: 'victory', 4: 'resigned'})[observation.outcome] ?? 'ended', ...extra}};
  }
  step(action = {type: 'wait'}, ticks = 1) {
    // Capture input now; a caller cannot change the request while it waits.
    try { action = parseAction(action); integer(ticks, 0, this.#config.maxTicksPerStep, 'ticks'); }
    catch (error) { return Promise.reject(error); }
    return this.#enqueue(() => this.#step(action, ticks));
  }
  async #step(action, ticks) {
    this.#healthy();
    const before = this.#stats(ticks), elapsed = this.#elapsed;
    if (before.outcome !== 0 || this.#elapsed >= this.#config.horizonTicks)
      throw new Error('episode ended; reset or restore a checkpoint');
    try {
      const decision = await this.#act(action);
      await this.#advance(ticks);
      const observation = decodeObservation(this.#runtime.observe()), reward = this.#score(before, observation);
      this.#reward += reward;
      const result = this.#result(observation, {ticksRequested: ticks, ticksAdvanced: this.#elapsed - elapsed, ...decision});
      return {...result, reward, terminated: result.info.terminated, truncated: result.info.truncated};
    } catch (cause) { throw this.#simulationFailure(cause, ticks, elapsed); }
  }
  async #act(action) {
    const command = commandFor(action, 64);
    if (!command) return {};
    const output = await this.#runtime.dispatch(1, this.#runtime.command('match', ...command));
    // Match replies update presentation only. Headless policies have no Client
    // selection to settle; the immutable World is the same browser transition.
    if (action.type === 'build') return {buildReason: output.effects[0].command.args[1]};
    return {};
  }
  async #advance(ticks) {
    for (let index = 0; index < ticks && this.#elapsed < this.#config.horizonTicks; index++) {
      if (this.#stat('outcome') !== 0) break;
      const before = this.#stat('tick');
      await this.#runtime.dispatch(1, this.#runtime.command('match', 'advance'));
      const advanced = this.#stat('tick') - before;
      this.#elapsed += advanced;
      if (advanced === 0) break; // Unstarted/paused are fixed points; the horizon is below the clock cap.
    }
  }
  #score(before, after) {
    const weights = this.#config.reward;
    return (after.outcome === 3 ? weights.victory : after.outcome === 1 ? weights.defeat : 0)
      + ['delivered', 'hull', 'casualties', 'tick'].reduce((sum, name) => sum + weights[name] * (after[name] - before[name]), 0);
  }
  checkpoint() {
    return this.#enqueue(() => {
      this.#healthy();
      if (this.#checkpoints.size >= 16) throw new Error('checkpoint limit reached (16); reset starts a new checkpoint set');
      const checkpoint = randomUUID();
      this.#checkpoints.set(checkpoint, {snapshot: this.#runtime.snapshot(1), elapsed: this.#elapsed, reward: this.#reward});
      return {checkpoint};
    });
  }
  restore(checkpoint) {
    return this.#enqueue(async () => {
      const saved = this.#checkpoints.get(checkpoint);
      if (!saved) throw new Error('unknown checkpoint in this environment');
      return this.#install(await this.#fresh(undefined, saved.snapshot), saved.elapsed, saved.reward);
    });
  }
  diagnostics() {
    return this.#enqueue(() => {
      this.#healthy();
      if (!this.#config.diagnostics) throw new Error('privileged diagnostics are disabled');
      return {snapshot: this.#runtime.snapshot(1), inspection: Object.fromEntries([...this.#indices].map(([name]) => [name, this.#stat(name)]))};
    });
  }
  close() {
    return this.#closing ??= this.#tail.then(async () => {
      await this.#runtime?.close(); this.#checkpoints.clear(); this.#runtime = undefined;
    });
  }
}
