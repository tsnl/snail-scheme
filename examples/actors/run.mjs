import { spawn } from '../../runtime/actors.mjs';

const artifact = process.argv[2];
if (!artifact) throw new Error('usage: node examples/actors/run.mjs build/counter.wasm');
const first = await spawn(artifact);
let second;
try {
  second = await spawn(artifact);
  const counter = first.connect();
  const observer = first.connect();
  console.log('first:', await counter.call('(add 3)'));
  console.log('second:', await second.connect().call('(value)'));
  counter.close();
  console.log('first through another connection:', await observer.call('(value)'));
  console.log('data stays data:', await observer.call('(echo (set! count 99))'));
} finally {
  await first.stop();
  if (second) await second.stop();
}
