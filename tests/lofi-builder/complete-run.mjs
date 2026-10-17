import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/compiler/execute.mjs';

const directory = process.argv[2];
const provider = new WebAssembly.Instance(new WebAssembly.Module(readFileSync(join(directory, 'complete-provider.wasm'))));
for (const suffix of ['generated', 'source', 'parsed']) {
  const code = loadWasm(readFileSync(join(directory, `complete-${suffix}.wasm`)));
  for (let repeat = 0; repeat < 2; ++repeat) {
    const instance = instantiate(code, new Map([['tests.builder', provider]]));
    for (const input of [-7, 0, 9, 42]) {
      globalThis.gc?.();
      assert.equal(invokeEntry(instance, [input]), input * 3 + 20, `${suffix}: ${input}`);
    }
    closeInstance(instance);
  }
  const literals = instantiate(loadWasm(readFileSync(join(directory, `complete-${suffix}-literals.wasm`))));
  assert.equal(invokeEntry(literals, []), 66, 'inspection changed owned literal data');
  closeInstance(literals);
  const linked = new WebAssembly.Module(readFileSync(join(directory, `complete-${suffix}.linked.wasm`)));
  assert.deepEqual(WebAssembly.Module.imports(linked), []);
  const api = new WebAssembly.Instance(linked).exports;
  api.main();
  for (const input of [-7, 0, 9, 42]) assert.equal(api.entry(input), input * 3 + 20);
}
console.log('PASS complete generated/source/parsed equivalence, typed views, literals and independent Wasm instances');
