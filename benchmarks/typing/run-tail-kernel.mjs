import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { createFinalizers, createIdentityHasher } from '../../src/runtime/host.mjs';

// Snail's benchmark-only raw i32 export and C use the exact same timed driver.
// Instantiate and initialize Snail's linked runtime before starting the timer.
const module = await WebAssembly.compile(await readFile(process.argv[2]));
const wasi = new WASI({version: 'preview1', args: [process.argv[2]], returnOnExit: true});
let instance;
const finalizers = createFinalizers((kind, id) => instance.exports['snail:drop-resource'](kind, id));
instance = await WebAssembly.instantiate(module, {
  ...wasi.getImportObject(),
  env: {abort() {throw new Error('overflow');}},
  'snail.host': {'register-finalizer': finalizers.register, 'hash-identity': createIdentityHasher(), 'unregister-finalizer': finalizers.unregister},
});
if (instance.exports._start && wasi.start(instance) !== 0) throw new Error('kernel initialization');
const fibonacci = instance.exports.fibonacci;
const count = Number(process.argv[3] ?? 1048576);
for (let n = 0; n <= 12; ++n) fibonacci(n, 0, 1);
if (fibonacci(10, 2, 3) !== 233 || fibonacci(46, 0, 1) !== 1836311903) {
  throw new Error('Fibonacci seeds or i32 boundary');
}
function workload(repetitions) {
  let checksum = 0;
  for (let repeat = 0; repeat < repetitions; ++repeat) {
    for (let n = 22; n <= 25; ++n) checksum += (n + 1) * fibonacci(n, 0, 1);
  }
  return checksum;
}
if (workload(count) !== 4204971 * count) throw new Error('warmup checksum');
const start = process.hrtime.bigint();
const checksum = workload(count);
const finish = process.hrtime.bigint();
if (checksum !== 4204971 * count) throw new Error(`bad checksum: ${checksum}`);
console.log(`checksum: ${checksum}\nelapsed: ${Number(finish - start) / 1e9} s; repetitions: ${count}`);
