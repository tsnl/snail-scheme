// `snail-scheme run` becomes the freshly built program, with ordinary shell
// IO and status.
//   node tests/script-run.mjs ROOT
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdir, mkdtemp, readFile, realpath, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {promisify} from 'node:util';

const execute = promisify(execFile), root = process.argv[2];
const project = await mkdtemp(join(tmpdir(), 'snail-run-workspace-'));
const caller = await mkdtemp(join(tmpdir(), 'snail-run-caller-'));
const source = finish => `(import (snail core base) (snail core io))
  (define (main (in InputPort) (out OutputPort) (fs Fs)) (→ Unit) (! mut)
    (for-each (lambda (argument) (write-line out argument)) (command-line))
  (write-line out (match (read-line in) ((Some line) line) ((None) "EOF")))
  (write-file fs "run-cwd.txt" "caller")
  ${finish})`;
const run = (args = []) => execute(join(root, 'snail-scheme'), ['run', '--target', 'node', join(project, 'main.scm'), ...args],
  {cwd: caller, timeout: 120_000, killSignal: 'SIGKILL'});

async function ready(child, marker = 'ready\n') {
  await new Promise((resolve, reject) => {
    let text = '';
    child.stdout.on('data', chunk => { text += chunk; if (text.includes(marker)) resolve(); });
    child.once('error', reject);
    child.once('exit', () => reject(new Error('program exited before readiness')));
  });
}

try {
  await mkdir(join(project, 'src'));
  await writeFile(join(project, 'main.scm'), source('(unit)'));
  const execution = run(['', 'λ', '--flag', 'quote" with spaces', '$(shell-looking)']);
  execution.child.stdin.end('from stdin\n');
  const result = await execution, lines = result.stdout.split('\n');
  const first = await realpath(join(project, 'build/main'));
  assert.equal(lines[0], join(first, 'main.wasm'), 'argv names the exact generation');
  assert.match(dirname(lines[0]), /\/\.snail-[^/]+$/);
  assert.deepEqual(lines.slice(1), ['', 'λ', '--flag', 'quote" with spaces', '$(shell-looking)', 'from stdin', '']);
  assert.equal(result.stderr, '');
  assert.equal(await readFile(join(caller, 'run-cwd.txt'), 'utf8'), 'caller');

  // A character read flushes an unterminated prompt, then shares stdin with lines.
  await writeFile(join(project, 'main.scm'), `(import (snail core base) (snail core io))
    (define (main (in InputPort) (out OutputPort)) (→ Unit) (! mut)
      (write-string out "prompt> ")
    (write out (read-char in)) (newline out)
    (write out (read-line in)) (newline out)
    (write out (read-char in)) (newline out))`);
  const prompted = run();
  await ready(prompted.child, 'prompt> ');
  prompted.child.stdin.end('λ😀tail\n');
  assert.equal((await prompted).stdout, 'prompt> (Some #\\λ)\n(Some "😀tail")\n(None)\n');

  await writeFile(join(project, 'main.scm'), source('(panic "run failure")'));
  const failure = run();
  failure.child.stdin.end('status\n');
  await assert.rejects(failure, error => error.code === 1 && /run failure/.test(error.stderr) && error.stdout.endsWith('status\n'));
  const beforeFailure = await realpath(join(project, 'build/main'));
  await writeFile(join(project, 'main.scm'), '(import (snail core base)) (define (main) (→ Unit) (missing-function))');
  await assert.rejects(run(), error => error.code === 1 && error.stdout === '' && /missing-function/.test(error.stderr));
  assert.equal(await realpath(join(project, 'build/main')), beforeFailure, 'failed rebuild never runs the preceding output');

  // The original CLI PID is now the application; no signal forwarding exists.
  await writeFile(join(project, 'main.scm'), '(import (snail core base) (snail core io)) (define (main (in InputPort) (out OutputPort)) (→ Unit) (! mut) (write-line out "ready") (read-line in) (unit))');
  for (const signal of ['SIGINT', 'SIGTERM']) {
    const waiting = run(), stopped = assert.rejects(waiting, {signal});
    await ready(waiting.child);
    assert.equal(waiting.child.kill(signal), true);
    await stopped;
  }
} finally {
  await rm(project, {recursive: true, force: true});
  await rm(caller, {recursive: true, force: true});
}
console.log('script run: immutable output, arguments, stdin, working directory, status and signals');
