import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {join} from 'node:path';
import {loadWasm, instantiate, invokeEntry, closeInstance} from '../../src/lofi/compiler/execute.mjs';

const directory = process.argv[2];
for (const route of ['source', 'received']) {
  for (const [entry, expected] of [['wide', 9223372036854775807n], ['halfway', 1 + 2 ** -23],
    ['subnormal', 2 ** -149], ['negative-zero', -0], ['conversion', 42n]]) {
    const instance = instantiate(loadWasm(readFileSync(join(directory, `precision-${route}-${entry}.wasm`))));
    try { assert.equal(invokeEntry(instance, []), expected, `${route}: ${entry}`); }
    finally { closeInstance(instance); }
  }
  const early = instantiate(loadWasm(readFileSync(join(directory, `precision-${route}-readiness.wasm`))));
  try { assert.throws(() => invokeEntry(early, []), /unreachable/, `${route}: premature read`); }
  finally { closeInstance(early); }
}
console.log('PASS parsed numeric precision, F32 rounding/subnormal, I64 width, signed zero, conversion and readiness traps');
