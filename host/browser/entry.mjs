// Wasm entry points and their dynamically installed effect handlers.
import {programExports} from './load.mjs';

// ---- Wasm entries ----

export function programEntry(program, name = 'app_main') {
  const exports = program.names ? programExports(program) : program.exports ?? program.runtime.exports;
  return {exports, main: exports[name], memory: program.linked ? program.runtime.exports.memory : exports.memory,
          get handlers() {
            const modules = program.linked ? [program.runtime.exports, ...[...program.linked.values()].map(instance => instance.exports)] : [program.exports];
            return modules.flatMap(exports => Object.entries(exports).filter(([name]) => name.startsWith('handler.')).map(([, value]) => value));
          }};
}

// A foreign Bytes argument borrows staging memory. Own its bytes before any
// await or another Wasm call can overwrite or grow the buffer.
export function byteSnapshot(memory, address) {
  const pointer = address >>> 0, buffer = memory.buffer;
  const length = new DataView(buffer).getUint32(pointer, true);
  return new Uint8Array(buffer, pointer + 4, length).slice();
}
