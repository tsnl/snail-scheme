import fs from 'node:fs';

const [path, expected] = process.argv.slice(2);
const {instance} = await WebAssembly.instantiate(fs.readFileSync(path));
let value;
try {
  value = String(instance.exports.main());
} catch (error) {
  if (expected !== 'trap' || !(error instanceof WebAssembly.RuntimeError)) throw error;
  value = 'trap';
}
if (value !== expected) throw new Error(`expected ${expected}, received ${value}`);
let trapped = false;
try { instance.exports.main(); }
catch (error) { trapped = error instanceof WebAssembly.RuntimeError; }
if (!trapped) throw new Error('main initialized twice');
console.log(value);
