import fs from 'node:fs';
import assert from 'node:assert/strict';
const [artifact, fixture] = process.argv.slice(2);
const cases = JSON.parse(fs.readFileSync(fixture, 'utf8'));
let args = [], output = '';
const imports = {oracle: {
  argument_length: index => BigInt(args[index].length),
  argument_character: (index, at) => args[index].codePointAt(Number(at)),
  emit_character: scalar => { output += String.fromCodePoint(scalar); },
}};
const bits = new DataView(new ArrayBuffer(8));
function fromBits(value) { bits.setBigUint64(0, BigInt(value)); return bits.getFloat64(0); }
function toBits(value) { bits.setFloat64(0, value); return bits.getBigUint64(0).toString(); }
const {instance} = await WebAssembly.instantiate(fs.readFileSync(artifact), imports);
instance.exports.main();
for (const item of cases) {
  args = [item.a, item.b]; output = '';
  let trapped = false, answer;
  try { answer = instance.exports.probe(BigInt(item.operation), fromBits(item.input)); }
  catch (error) {
    if (!(error instanceof WebAssembly.RuntimeError)) throw error;
    trapped = true;
  }
  assert.equal(trapped, Boolean(item.error), item.label);
  if (!trapped) {
    assert.equal(toBits(answer), item.bits, item.label);
    assert.equal(output, item.text, item.label);
  }
}
console.log(JSON.stringify({cases: cases.length, passed: true}));
