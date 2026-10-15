import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';

// Compare complete small traces with the original call/cc algorithm after
// explicitly choosing the same left-to-right operand evaluation order.
const [artifact] = process.argv.slice(2);
const directory = path.dirname(new URL(import.meta.url).pathname);
const bytes = fs.readFileSync(artifact);
const cases = [[2, 1, 0], [6, 4, 2], [10, 6, 3], [1, 2, 3]];
for (const inputs of cases) {
  const expected = spawnSync(process.env.CHEZ || 'scheme',
    ['--script', path.join(directory, 'chez-observe.scm')],
    {input: inputs.join(' ') + '\n', encoding: 'utf8', timeout: 30000});
  assert.equal(expected.status, 0, expected.stderr);
  const rows = expected.stdout.trim().split('\n').map(line => line.trim().split(/\s+/).map(Number));
  const observed = [];
  const {instance} = await WebAssembly.instantiate(bytes, {
    benchmark: {input_i64: i => BigInt(inputs[i]), hide_i64: x => x, barrier: () => 1},
    observation: {event: (tag, x, y, z) => observed.push([tag, Number(x), Number(y), Number(z)])},
  });
  instance.exports.main();
  observed.length = 0;
  const result = instance.exports.bench(1n);
  observed.push([9, Number(result), 0, 0]);
  assert.deepEqual(observed, rows, `complete source trace for ${inputs}`);
  const counts = [0, 1, 2, 3].map(tag => rows.filter(row => row[0] === tag).length);
  console.log(JSON.stringify({inputs, result: Number(result), calls: counts[0],
    captures: counts[1], invocations: counts[2], peano_steps: counts[3]}));
}
