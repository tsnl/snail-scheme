import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';

// ---- Separate guest-start resource diagnostic ----

const [filename, ...args] = process.argv.slice(2);
if (!filename) throw new Error('usage: resource-wasi.mjs MODULE.wasm [ARGUMENT ...]');
const wasi = new WASI({ version: 'preview1', args: [filename, ...args],
  env: process.env, preopens: { '/': process.cwd() }, returnOnExit: true });
const module = await WebAssembly.compile(await readFile(filename));
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
const beforeMemory = process.memoryUsage();
const before = process.resourceUsage();
const code = wasi.start(instance);
const after = process.resourceUsage();
const afterMemory = process.memoryUsage();
const delta = Object.fromEntries(['userCPUTime', 'systemCPUTime', 'minorPageFault',
  'majorPageFault', 'voluntaryContextSwitches', 'involuntaryContextSwitches',
  'fsRead', 'fsWrite'].map(key => [key, after[key] - before[key]]));
const counters = Object.fromEntries(Object.entries(instance.exports)
  .filter(([name]) => name.startsWith('control_'))
  .map(([name, value]) => [name, value.value.toString()]));
console.error(`Resource: ${JSON.stringify({
  kind: 'separate WASI.start resource diagnostic; no performance sample',
  before, after, delta, beforeMemory, afterMemory,
  finalLinearMemoryBytes: instance.exports.memory.buffer.byteLength,
  counterValues: counters,
  units: { userCPUTime: 'microseconds', systemCPUTime: 'microseconds',
    maxRSS: 'KiB process lifetime high-water mark', memoryUsage: 'bytes' },
})}`);
process.exitCode = code;
