// Wasm entry points.
import {programExports} from './load.mjs';
import {hostExports} from './memory.mjs';

// ---- Wasm entries ----

export function programEntry(program, name = 'app_main') {
  const raw = program.names ? programExports(program) : program.exports ?? program.runtime.exports;
  const gc = program.runtime?.exports ?? raw;
  const exports = hostExports(raw, gc);
  return {exports, main: exports[name], gc, memory: program.linked ? program.runtime.exports.memory : exports.memory};
}
