import { readFile } from 'node:fs/promises';
const { instance } = await WebAssembly.instantiate(await readFile(process.argv[2]));
const wasm = instance.exports;
if (wasm.check() !== 0 || wasm['call-grouped'](41) !== 42)
  throw new Error('recursive group identity or folded evaluation changed');
if (!Object.is(wasm['negative-zero'](), -0) || wasm['escaped-name']() !== 19)
  throw new Error('WAT spelling changed a value or export name');
if (wasm['nan-payload']() !== 0x7ff8000000000005n ||
    BigInt.asUintN(64, wasm['negative-nan-payload']()) !== 0xfff8000000000005n)
  throw new Error('NaN sign or payload changed');
if (wasm['wide-float']() !== 0x43e0000000000000n ||
    wasm['large-float']() !== 0x4415af1d78b58c40n ||
    BigInt.asUintN(64, wasm['signed-boundary']()) !== 0x8000000000000000n ||
    BigInt.asUintN(64, wasm['all-bits']()) !== 0xffffffffffffffffn)
  throw new Error('integer-spelled float or i64 boundary changed');
let trapped = false;
try { wasm['call-singleton'](41); } catch (error) {
  if (!(error instanceof WebAssembly.RuntimeError)) throw error;
  trapped = true;
}
if (!trapped) throw new Error('a singleton merged with a recursion group member');
