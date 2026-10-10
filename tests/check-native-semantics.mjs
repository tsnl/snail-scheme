// The same binary supplies both engines; native-only host checks live in C.
import { readFile } from 'node:fs/promises';
const { instance } = await WebAssembly.instantiate(await readFile(process.argv[2]));
const wasm = instance.exports;
if (wasm.check() !== 0 || wasm.tail(2000000) !== 42n || wasm.root(500) !== 99n)
  throw new Error('Wasm reference result differs');
if (wasm['i31-s'](-2147483648) !== 0 || wasm['i31-s'](1073741824) !== -1073741824 ||
    wasm['i31-s'](-1) !== -1 || wasm['i31-u'](-1) !== 2147483647)
  throw new Error('Wasm i31 result differs');
for (let kind = 0; kind < 12; kind++) {
  const { instance: fresh } = await WebAssembly.instantiate(await readFile(process.argv[2]));
  let trapped = false;
  try { fresh.exports.trap(kind); } catch (error) {
    if (!(error instanceof WebAssembly.RuntimeError)) throw error;
    trapped = true;
  }
  if (!trapped) throw new Error(`expected Wasm trap ${kind}`);
}
