// Local subprocess transports. Stdout is exclusively newline-delimited JSON;
// both protocols share the same environment and admit one request at a time.
import {once} from 'node:events';
import {openEnvironment, integer, object, MAP_WIDTH, MAP_HEIGHT} from './headless.mjs';

// ---- Bounded UTF-8 input and backpressured output ----

const maximumLineBytes = 65536;
async function* lines(input) {
  let parts = [], size = 0, oversized = false;
  for await (const chunk of input) {
    let start = 0;
    for (let index = 0; index <= chunk.length; index++) {
      if (index < chunk.length && chunk[index] !== 10) continue;
      const part = chunk.subarray(start, index); size += part.length;
      if (size > maximumLineBytes) { oversized = true; parts = []; }
      else if (!oversized) parts.push(part);
      if (index < chunk.length) {
        yield oversized ? null : Buffer.concat(parts);
        parts = []; size = 0; oversized = false;
      }
      start = index + 1;
    }
  }
  if (size) yield oversized ? null : Buffer.concat(parts);
}
function parseLine(line) {
  if (!line) throw new Error('input line exceeds 65536 bytes');
  return JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(line));
}
async function write(value) {
  if (!process.stdout.write(`${JSON.stringify(value)}\n`)) await once(process.stdout, 'drain');
}
const errorInfo = error => ({message: error.message, ...(error.info ? {info: error.info} : {})});
function requestId(value) {
  return typeof value === 'string' && value.length <= 128 || Number.isSafeInteger(value);
}

// ---- The common closed command surface ----

async function invoke(environment, method, args = {}) {
  switch (method) {
    case 'reset': object(args, ['seed'], method); return environment.reset(args.seed);
    case 'observe': object(args, [], method); return environment.observe();
    case 'step':
      object(args, ['action', 'ticks'], method);
      return environment.step(args.action, args.ticks);
    case 'checkpoint': object(args, [], method); return environment.checkpoint();
    case 'restore':
      object(args, ['checkpoint'], method);
      if (typeof args.checkpoint !== 'string' || args.checkpoint.length > 128) throw new Error('invalid checkpoint token');
      return environment.restore(args.checkpoint);
    case 'diagnostics': object(args, [], method); return environment.diagnostics();
    case 'close': object(args, [], method); await environment.close(); return {};
    default: throw new Error('unknown environment method');
  }
}
async function jsonl(environment, message) {
  object(message, ['id', 'method', 'params'], 'request');
  if (!requestId(message.id) || typeof message.method !== 'string') throw new Error('request requires id and method');
  const result = await invoke(environment, message.method, message.params);
  return {id: message.id, result};
}

// ---- MCP tools and lifecycle (2025-11-25) ----

const schema = properties => ({type: 'object', properties, additionalProperties: false});
const int = (minimum, maximum) => ({type: 'integer', minimum, maximum});
const cell = {...int(0, MAP_WIDTH * MAP_HEIGHT - 1), description: 'Absolute map cell x + y * 80; use a player-observed tile.cell or buildCandidate.cell.'};
const actionVariant = (type, properties = {}) => ({...schema({type: {const: type}, ...properties}), required: ['type', ...Object.keys(properties)]});
const actionSchema = {oneOf: [actionVariant('wait'), actionVariant('build', {
  kind: {...int(1, 3), description: '1 = extractor (first required purchase), 2 = artillery, 3 = observation tower.'}, cell}),
  actionVariant('upgrade', {cell}), actionVariant('cancel', {cell}), actionVariant('scavenge', {cell}), actionVariant('relocate', {from: cell, to: cell}),
  actionVariant('fabricate'), actionVariant('repair'), actionVariant('resign'), actionVariant('pause', {paused: {type: 'boolean'}})]};
const tools = [
  {name: 'siegework_reset', description: 'Start a fresh seeded episode. The first explicit extractor starts its simulation clock.', inputSchema: schema({seed: int(1, 65535)})},
  {name: 'siegework_observe', description: 'Player knowledge only. Arrays are paged independently; counts report omitted entries. Build candidates are previews, not guaranteed purchases. Grid cells use cell=x+y*80; worker/enemy x,y use world units (40 per cell, center at grid*40+20). Terrain: 0 rock, 1 ground, 2 water. Unknown reserves/HP are -1. Building kinds: 1 extractor, 2 artillery, 3 observation tower.',
    inputSchema: schema({offset: int(0, 65535), limit: int(1, 256)})},
  {name: 'siegework_step', description: 'Submit one player action, then at most ticks explicit simulation ticks. A rejected purchase still performs the requested wait. Arrays default to the first 32 entries.',
    inputSchema: schema({action: actionSchema, ticks: {...int(0, 600), description: 'Simulation ticks after the action; 10 ticks = one game second. Defaults to 1. Zero submits the action without advancing time.'}})},
  {name: 'siegework_checkpoint', description: 'Retain an opaque checkpoint in this process (maximum 16); reset clears checkpoints.', inputSchema: schema({})},
  {name: 'siegework_restore', description: 'Restore an opaque checkpoint including episode horizon and reward accounting.',
    inputSchema: {...schema({checkpoint: {type: 'string', maxLength: 128}}), required: ['checkpoint']}}
];
function page(result, offset = 0, limit = 32) {
  if (!result.observation) return result;
  const observation = {...result.observation}, collections = {};
  for (const key of ['tiles', 'buildings', 'workers', 'enemies', 'nests', 'buildCandidates']) {
    const all = observation[key]; observation[key] = all.slice(offset, offset + limit);
    collections[key] = {total: all.length, returned: observation[key].length, omitted: all.length - observation[key].length};
  }
  return {...result, observation, page: {offset, limit, collections}};
}
class ProtocolError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
function protocol(condition, code, message) {
  if (!condition) throw new ProtocolError(code, message);
}
async function callTool(environment, params) {
  protocol(params && typeof params === 'object' && !Array.isArray(params), -32602, 'invalid tools/call params');
  protocol(tools.some(tool => tool.name === params.name), -32602, 'unknown tool');
  protocol(params.arguments === undefined || params.arguments && typeof params.arguments === 'object'
    && !Array.isArray(params.arguments), -32602, 'tool arguments must be an object');
  try {
    const args = params.arguments ?? {}, method = params.name.slice('siegework_'.length);
    let offset = 0, limit = 32;
    if (method === 'observe') {
      object(args, ['offset', 'limit'], 'observe');
      offset = integer(args.offset === undefined ? 0 : args.offset, 0, 65535, 'offset');
      limit = integer(args.limit === undefined ? 32 : args.limit, 1, 256, 'limit');
    }
    const result = page(await invoke(environment, method, method === 'observe' ? {} : args), offset, limit);
    return {content: [{type: 'text', text: JSON.stringify(result)}], structuredContent: result, isError: false};
  } catch (error) { return {content: [{type: 'text', text: JSON.stringify(errorInfo(error))}], isError: true}; }
}
async function mcp(environment, message, state) {
  protocol(message && !Array.isArray(message) && message.jsonrpc === '2.0' && typeof message.method === 'string', -32600, 'invalid JSON-RPC request');
  const notification = !Object.hasOwn(message, 'id');
  const validParams = message.params === undefined || message.params && typeof message.params === 'object' && !Array.isArray(message.params);
  if (notification) {
    if (validParams && message.method === 'notifications/initialized' && state.initialized) state.ready = true;
    return null;
  }
  protocol(requestId(message.id), -32600, 'invalid request id');
  protocol(validParams, -32602, 'params must be an object');
  let result;
  switch (message.method) {
    case 'initialize':
      protocol(!state.initialized, -32600, 'already initialized');
      protocol(typeof message.params?.protocolVersion === 'string' && message.params?.capabilities
        && typeof message.params.capabilities === 'object' && !Array.isArray(message.params.capabilities)
        && typeof message.params?.clientInfo?.name === 'string'
        && typeof message.params.clientInfo.version === 'string', -32602, 'invalid initialize params');
      state.initialized = true;
      result = {protocolVersion: '2025-11-25', capabilities: {tools: {}}, serverInfo: {name: 'siegework', version: '1.0.0'}}; break;
    case 'ping': result = {}; break;
    case 'tools/list':
      protocol(state.ready, -32000, 'initialize and send notifications/initialized first');
      protocol(!message.params?.cursor, -32602, 'invalid tools/list params');
      result = {tools}; break;
    case 'tools/call':
      protocol(state.ready, -32000, 'initialize and send notifications/initialized first');
      result = await callTool(environment, message.params); break;
    default: throw new ProtocolError(-32601, 'method not found');
  }
  return {jsonrpc: '2.0', id: message.id, result};
}

// ---- A local process owns the environment lifetime ----

function options(argv) {
  const config = {}, paths = []; let mcpMode = false;
  for (const arg of argv) {
    if (arg === '--mcp') mcpMode = true;
    else if (arg === '--diagnostics') config.diagnostics = true;
    else if (arg.startsWith('--horizon=')) config.horizonTicks = Number(arg.slice(10));
    else if (arg.startsWith('--max-ticks=')) config.maxTicksPerStep = Number(arg.slice(12));
    else if (arg.startsWith('--')) throw new Error(`unknown option ${arg}`);
    else paths.push(arg);
  }
  if (paths.length !== 1) throw new Error('usage: node apps/siegework/environment-cli.mjs [--mcp] [--horizon=12000] [--max-ticks=600] [--diagnostics] PACKAGE');
  return {config, directory: paths[0], mcpMode};
}
async function serve(environment, mcpMode) {
  const state = {initialized: false, ready: false};
  for await (const line of lines(process.stdin)) {
    let message, parsed = false;
    try {
      message = parseLine(line); parsed = true;
      const response = await (mcpMode ? mcp(environment, message, state) : jsonl(environment, message));
      if (response) await write(response);
      if (!mcpMode && message.method === 'close') break;
    } catch (error) {
      const id = requestId(message?.id) ? message.id : null;
      await write(mcpMode ? {jsonrpc: '2.0', id, error: {code: error.code ?? (parsed ? -32600 : -32700), message: error.message}}
        : {id, error: errorInfo(error)});
    }
  }
}
try {
  const {config, directory, mcpMode} = options(process.argv.slice(2));
  tools.find(tool => tool.name === 'siegework_step').inputSchema.properties.ticks.maximum = config.maxTicksPerStep ?? 600;
  const environment = await openEnvironment(directory, config);
  try { await serve(environment, mcpMode); }
  finally { await environment.close(); process.stdin.destroy(); }
} catch (error) { process.stderr.write(`${error.message}\n`); process.exitCode = 1; }
