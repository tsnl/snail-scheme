import assert from 'node:assert/strict';
import fs from 'node:fs';

// ---- Instantiate, initialize and validate outside the workload timer ----

const [artifact, specification, mode] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(specification, 'utf8'));
const scalars = [0, 233, 128512, 1114111, 769];
let instance;
let barriers = 0;
function verifyPayload(rounds) {
  assert.equal(instance.exports['probe-length'](), BigInt(config.inputs[0]));
  for (let index = 0; index < config.inputs[0]; index++) {
    const expected = config.operation === 'ref' || rounds === 0n
      ? scalars[index % scalars.length] : scalars[Number((rounds - 1n) % 5n)];
    assert.equal(instance.exports['probe-character'](BigInt(index)), expected, `scalar ${index}`);
  }
}
const imports = { benchmark: {
  input_i64: index => BigInt(config.inputs[index]),
  hide_i64: value => {
    if (mode === '--validate') {
      assert.equal(value, config.operation === 'ref' ? 0n : BigInt(barriers));
      if (config.operation === 'set') verifyPayload(BigInt(barriers));
      barriers++;
    }
    return value;
  },
}};
({ instance } = await WebAssembly.instantiate(fs.readFileSync(artifact), imports));
instance.exports.main();
assert.equal(barriers, 0);
if (mode === '--validate') verifyPayload(0n);

// ---- Time every native operation and its scalar acceptance check ----

const start = process.hrtime.bigint();
const count = BigInt(config.count);
const result = instance.exports.bench(count);
assert.equal(result.toString(), config.expected.toString());
const seconds = Number(process.hrtime.bigint() - start) / 1e9;
if (mode === '--validate') assert.equal(barriers, Number(count));
// Every final store is checked; these host calls occur after the workload timer.
verifyPayload(count);
console.log(JSON.stringify({ seconds, result: result.toString(),
  barriers: mode === '--validate' ? barriers : null,
  setup_barriers: mode === '--validate' ? 0 : null }));
