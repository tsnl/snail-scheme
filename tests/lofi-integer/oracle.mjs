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
const {instance} = await WebAssembly.instantiate(fs.readFileSync(artifact), imports);
instance.exports.main();
for (const item of cases) {
  args = [item.a, item.b]; output = '';
  let trapped = false;
  try { assert.equal(instance.exports['integer-probe'](BigInt(item.operation)), 1n); }
  catch (error) {
    if (!(error instanceof WebAssembly.RuntimeError)) throw error;
    trapped = true;
  }
  assert.equal(trapped, Boolean(item.error), item.label);
  if (!trapped) assert.equal(output, item.expected, item.label);
}
console.log(JSON.stringify({cases: cases.length, passed: true}));
