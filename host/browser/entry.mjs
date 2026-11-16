// Wasm entry points.

// The program's own exports, its main and the memory its runtime stages
// Bytes in: its one module's.
export function programEntry(program) {
  const exports = program.exports ?? program.runtime.exports;
  return {exports, main: exports.main, memory: exports.memory};
}
