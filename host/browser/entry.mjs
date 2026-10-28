// Wasm entry points.
import {programExports} from './load.mjs';

// ---- Wasm entries ----

export function programEntry(program, name = 'app_main') {
  const exports = program.names ? programExports(program) : program.exports ?? program.runtime.exports;
  return {exports, main: exports[name], memory: program.linked ? program.runtime.exports.memory : exports.memory};
}
