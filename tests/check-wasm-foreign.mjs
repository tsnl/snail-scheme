import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const module = await WebAssembly.compile(await readFile(process.argv[2]));
const imports = {};
for (const entry of WebAssembly.Module.imports(module)) {
  imports[entry.module] ??= {};
  imports[entry.module][entry.name] = () => {
    throw new Error(`Unexpected import: ${entry.module}/${entry.name}`);
  };
}
let instance;
imports.example['snail:+'] = (argumentsRoot) => {
  const api = instance.exports;
  assert.equal(api.length(argumentsRoot), 2);
  const first = api.at(argumentsRoot, 0);
  const second = api.at(argumentsRoot, 1);
  assert.equal(api.as_integer(first), 1n);
  assert.equal(api.as_integer(second), 2n);
  api.release(first);
  api.release(second);
  return api.integer(42n);
};
instance = await WebAssembly.instantiate(module, imports);
assert.equal(instance.exports.snail_main(), 45);
assert.equal(instance.exports.awi_live_roots.value, 0);
console.log('Overlapping core and foreign binding identities passed');
