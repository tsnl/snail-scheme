// A program waiting in `termination` observes SIGTERM or SIGINT as a value
// and exits cleanly; one that does not wait is ended by SIGTERM, as before.
// A signal forwarded alongside the one that ended a wait reaches the next.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {fileURLToPath} from 'node:url';
import {createTermination} from '../../host/native/process.mjs';

// A quick second Ctrl-C reaches the main thread while the first is still
// on its way to the waiting task, so both carry the same delivery count.
// The kernel can merge two signals sent at once, so the worker's side is
// driven directly, with the stamps the main thread would put on them.
async function doubleTap() {
  const waiting = new Int32Array(new SharedArrayBuffer(8)), termination = createTermination(waiting);
  const {signal} = new AbortController(), first = termination.wait(signal), stamp = Atomics.load(waiting, 1);
  termination.deliver({name: 'SIGINT', deliveries: stamp});
  termination.deliver({name: 'SIGINT', deliveries: stamp});
  assert.equal(await first, 2);
  assert.equal(Atomics.load(waiting, 0), 0, 'the first signal ended the wait');
  assert.equal(await termination.wait(signal), 2, 'the second reaches the next wait');
}

const runner = fileURLToPath(new URL('../../host/native/run-snail.mjs', import.meta.url)), program = process.argv[2];
const timeout = setTimeout(() => { throw new Error('termination test timed out'); }, 30_000);

// Runs the program and sends it `signal` once it reports being ready.
async function signalled(signal, ...arguments_) {
  const child = spawn(process.execPath, ['--no-warnings', runner, program, ...arguments_], {stdio: ['ignore', 'pipe', 'inherit']});
  let output = '', sent = false;
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', text => {
    output += text;
    if (!sent && output.endsWith('ready\n')) { sent = true; child.kill(signal); }
  });
  const [code, ended] = await once(child, 'close');
  return {code, signal: ended, output};
}

await doubleTap();
assert.deepEqual(await signalled('SIGTERM', 'wait'), {code: 0, signal: null, output: 'ready\nobserved Terminate\n'});
assert.deepEqual(await signalled('SIGINT', 'wait'), {code: 0, signal: null, output: 'ready\nobserved Interrupt\n'});
assert.deepEqual(await signalled('SIGTERM'), {code: null, signal: 'SIGTERM', output: 'ready\n'});
clearTimeout(timeout);
console.log('termination: observed by a waiting program, kept for its next wait when doubled, and the default for one that does not wait');
