import { readFile } from 'node:fs/promises';

const bytes = await readFile(process.argv[2]);
const { instance } = await WebAssembly.instantiate(bytes, {env: {abort() {throw new Error('overflow');}}});
const fibonacci = instance.exports.fibonacci;
const count = Number(process.argv[3] ?? 64);
for (let n = 0; n <= 12; ++n) fibonacci(n, 0);
let checksum = 0;
const start = process.hrtime.bigint();
for (let repeat = 0; repeat < count; ++repeat) {
  for (let n = 22; n <= 25; ++n) checksum += (n + 1) * fibonacci(n, 0);
}
const finish = process.hrtime.bigint();
if (checksum !== 4204971 * count) throw new Error(`bad checksum: ${checksum}`);
console.log(`checksum: ${checksum}\nelapsed: ${Number(finish - start) / 1e9} s; repetitions: ${count}`);
