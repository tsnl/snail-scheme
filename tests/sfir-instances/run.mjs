import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

// ---- Check effects without calling an export after failed initialization ----

const [path, expected, history] = process.argv.slice(2);
const effects = [];
const module = await WebAssembly.compile(await readFile(path));
assert.deepEqual(WebAssembly.Module.imports(module), [
  { module: 'instance.probe', name: 'record', kind: 'function' },
]);
const instance = await WebAssembly.instantiate(module, {
  'instance.probe': { record(value) { effects.push(String(value)); } },
});
if (expected === 'trap') {
  assert.throws(() => instance.exports.main(), WebAssembly.RuntimeError);
} else {
  assert.equal(String(instance.exports.main()), expected);
  assert.equal(String(instance.exports.observed()), history);
}
assert.deepEqual(effects, [...history]);
console.log(`effects:${effects.join('')}`);
