import assert from 'node:assert/strict';
import fs from 'node:fs';

// ---- Rust's independent UTF-8 oracle, one record per Unicode scalar ----

const [modulePath, oraclePath] = process.argv.slice(2);
const oracle = fs.readFileSync(oraclePath);
assert.equal(oracle.length % 12, 0);
const {instance} = await WebAssembly.instantiate(fs.readFileSync(modulePath));
assert.equal(instance.exports.main(), 0n);
for (let offset = 0; offset < oracle.length; offset += 12) {
  const scalar = BigInt(oracle.readUInt32LE(offset));
  const packed = oracle.readBigUInt64LE(offset + 4);
  assert.equal(instance.exports['encode-scalar'](scalar), packed, `encode U+${scalar.toString(16)}`);
  assert.equal(instance.exports['decode-scalar'](packed), scalar, `decode U+${scalar.toString(16)}`);
}
console.log(`scalars ${oracle.length / 12}`);
