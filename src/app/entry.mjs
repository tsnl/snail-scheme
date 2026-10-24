// Wasm entry points and their dynamically installed effect handlers.
import {programExports} from './load.mjs';

// ---- Wasm entries ----

const entered = new WeakSet();

export function programEntry(program, name = 'app_main') {
  const modules = program.linked ? [program.runtime.exports, ...[...program.linked.values()].map(instance => instance.exports)] : [program.exports];
  const exports = program.names ? programExports(program) : program.exports ?? program.runtime.exports;
  return {exports, main: exports[name], memory: program.linked ? program.runtime.exports.memory : exports.memory,
          handlers: modules.flatMap(exports => Object.entries(exports).filter(([name]) => name.startsWith('handler.')).map(([, value]) => value))};
}

// Dynamic handler globals belong to one invocation, including while suspended.
// Restore after settlement, before anyone observes completion or reuses them.
export async function runEntry(entry, ...args) {
  if (entry.handlers.some(global => entered.has(global))) throw new Error('Wasm entries with shared handlers must not overlap');
  const saved = entry.handlers.map(global => [global, global.value]);
  saved.forEach(([global]) => entered.add(global));
  try { return await WebAssembly.promising(entry.main)(...args); }
  finally { saved.forEach(([global, value]) => { global.value = value; entered.delete(global); }); }
}

// A foreign Bytes argument borrows staging memory. Own its bytes before any
// await or another Wasm call can overwrite or grow the buffer.
export function byteSnapshot(memory, address) {
  const pointer = address >>> 0, buffer = memory.buffer;
  const length = new DataView(buffer).getUint32(pointer, true);
  return new Uint8Array(buffer, pointer + 4, length).slice();
}
