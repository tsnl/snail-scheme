// Wasm entry points.
import {programExports} from './load.mjs';

// ---- Wasm entries ----

// The program's own exports, its main and the memory its runtime stages
// Bytes in: a per-library build's last module and its runtime, or one
// linked module.
export function programEntry(program) {
  const exports = program.names ? programExports(program) : program.exports ?? program.runtime.exports;
  return {exports, main: exports.main, memory: program.linked ? program.runtime.exports.memory : exports.memory};
}
