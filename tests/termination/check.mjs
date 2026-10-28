// A program waiting in `termination` observes SIGTERM or SIGINT as a value
// and exits cleanly; one that does not wait is ended by SIGTERM, as before.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {fileURLToPath} from 'node:url';

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

assert.deepEqual(await signalled('SIGTERM', 'wait'), {code: 0, signal: null, output: 'ready\nobserved Terminate\n'});
assert.deepEqual(await signalled('SIGINT', 'wait'), {code: 0, signal: null, output: 'ready\nobserved Interrupt\n'});
assert.deepEqual(await signalled('SIGTERM'), {code: null, signal: 'SIGTERM', output: 'ready\n'});
clearTimeout(timeout);
console.log('termination: observed by a waiting program, and the default for one that does not wait');
