import fs from 'node:fs';
import assert from 'node:assert/strict';
const [plain, counted] = await Promise.all(process.argv.slice(2).map(async file => (await WebAssembly.instantiate(fs.readFileSync(file))).instance.exports));
for (const exports of [plain,counted]) {
 assert.equal(exports.branch(),42);
 assert.equal(exports.effects.value,7);
 assert.throws(() => exports.trap(), WebAssembly.RuntimeError);
 assert.equal(exports.effects.value,9);
}
assert.equal(counted['entry:branch'].value,1n);
assert.equal(counted['entry:trap'].value,1n);
assert.equal(counted['site:branch:0'].value,1n);
assert.equal(counted['site:trap:0'].value,1n);
console.log('PASS named operand branch, operand trap, effect order, request counts');
