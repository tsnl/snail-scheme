import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

let collects = 0;
let pairs = 0;
const { instance } = await WebAssembly.instantiate(readFileSync(process.argv[2]), {
  probe: {
    collect() {
      ++collects;
      global.gc();
      return 0;
    },
    'collect-two'() {
      ++pairs;
      global.gc();
    },
  },
});
assert.equal(instance.exports.run(0), 66n);
assert.equal(instance.exports.run(1), 66n);
assert.equal(instance.exports.arrays(), 42n);
assert.equal(collects, 12);
assert.equal(pairs, 2);
