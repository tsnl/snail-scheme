// Both backends consume the same module datum; native-only host checks live in C.
import { readFile, writeFile } from 'node:fs/promises';
const { instance } = await WebAssembly.instantiate(await readFile(process.argv[2]));
const wasm = instance.exports;
if (wasm.check() !== 0 || wasm.tail(2000000) !== 42n || wasm.root(500) !== 99n)
  throw new Error('Wasm reference result differs');
if (wasm['i31-s'](-2147483648) !== 0 || wasm['i31-s'](1073741824) !== -1073741824 ||
    wasm['i31-s'](-1) !== -1 || wasm['i31-u'](-1) !== 2147483647)
  throw new Error('Wasm i31 result differs');
if (wasm['i31-s'](1073741823) !== 1073741823 || wasm['i31-u'](1073741824) !== 1073741824 ||
    wasm['i31-s'](2147483647) !== -1 || !wasm['i31-eq-negative'](-1) ||
    !wasm['i31-eq-negative'](2147483647) || wasm['i31-eq-negative'](0))
  throw new Error('Wasm i31 boundary or equality differs');

const left = wasm.left(-9223372036854775808n);
if (wasm['read-parent'](left) !== -9223372036854775808n || !wasm['same-left'](left) ||
    wasm['is-right'](left) || !wasm.cyclic(left)) throw new Error('Wasm subtype identity differs');
try { wasm['read-right'](left); throw new Error('sibling cast did not trap'); }
catch (error) { if (!(error instanceof WebAssembly.RuntimeError)) throw error; }

// ---- Exact saturating conversions, including both source widths ----

function saturated(value, bits, signed) {
  const width = BigInt(bits), minimum = signed ? -(1n << (width - 1n)) : 0n;
  const maximum = (1n << (width - (signed ? 1n : 0n))) - 1n;
  if (Number.isNaN(value)) return 0n;
  if (value === Infinity) return maximum;
  if (value === -Infinity) return minimum;
  const integer = BigInt(Math.trunc(value));
  return integer < minimum ? minimum : integer > maximum ? maximum : integer;
}

const inputs = [NaN, Infinity, -Infinity, 0, -0, 1.9, -1.9, 2 ** 53 + 2];
for (const exponent of [31, 32, 63, 64]) {
  const boundary = 2 ** exponent;
  for (const precision of [24, 53])
    inputs.push(boundary, boundary - 2 ** (exponent - precision), boundary + 2 ** (exponent - precision + 1),
                -boundary, -boundary - 2 ** (exponent - precision + 1), -boundary + 2 ** (exponent - precision));
}
const conversions = [[32, 32, true], [32, 32, false], [32, 64, true], [32, 64, false],
                     [64, 32, true], [64, 32, false], [64, 64, true], [64, 64, false]];
const samples = inputs.map(input => ({ input: Object.is(input, -0) ? '-0' : String(input), results: conversions.map(([bits, source, signed]) => {
  const name = `sat-i${bits}-f${source}-${signed ? 's' : 'u'}`;
  const expected = BigInt.asUintN(bits, saturated(source === 32 ? Math.fround(input) : input, bits, signed));
  if (BigInt.asUintN(bits, BigInt(wasm[name](input))) !== expected)
    throw new Error(`${name}(${input}) differs from the integer reference`);
  return String(expected);
}) }));
if (process.argv[3]) await writeFile(process.argv[3], JSON.stringify(samples));

for (let kind = 0; kind < 13; kind++) {
  const { instance: fresh } = await WebAssembly.instantiate(await readFile(process.argv[2]));
  let trapped = false;
  try { fresh.exports.trap(kind); } catch (error) {
    if (!(error instanceof WebAssembly.RuntimeError)) throw error;
    trapped = true;
  }
  if (!trapped) throw new Error(`expected Wasm trap ${kind}`);
}
