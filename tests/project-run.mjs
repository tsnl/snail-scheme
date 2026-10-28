// Named runs become the freshly built program, with ordinary shell IO/status.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdtemp, readFile, realpath, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {promisify} from 'node:util';

const execute = promisify(execFile), root = process.argv[2];
const project = await mkdtemp(join(tmpdir(), 'snail-run-project-'));
const caller = await mkdtemp(join(tmpdir(), 'snail-run-caller-'));
const source = finish => `(import (snail core base) (snail core io))
  (for-each write-line (command-line))
  (write-line (match (read-line) ((Some line) line) ((None) "EOF")))
  (write-file "run-cwd.txt" "caller")
  ${finish}`;
const run = (name, args = []) => execute(join(root, 'snail'), ['run', project, name, ...args],
  {cwd: caller, timeout: 120_000, killSignal: 'SIGKILL'});

async function ready(child) {
  await new Promise((resolve, reject) => {
    let text = '';
    child.stdout.on('data', chunk => { text += chunk; if (text.includes('ready\n')) resolve(); });
    child.once('error', reject);
    child.once('exit', () => reject(new Error('program exited before readiness')));
  });
}

try {
  await writeFile(join(project, 'project.datum'), `(
    (build-target program (program (entry "main.sld")))
    (run-target app (run program (args ("configured" "" "λ")))))`);
  await writeFile(join(project, 'main.sld'), source('(unit)'));
  const execution = run('app', ['--flag', 'quote" with spaces', '$(shell-looking)']);
  execution.child.stdin.end('from stdin\n');
  const result = await execution, lines = result.stdout.split('\n');
  const first = await realpath(join(project, 'build/program'));
  assert.equal(lines[0], join(first, 'program.wasm'), 'argv names the exact generation');
  assert.match(dirname(lines[0]), /\/\.snail-[^/]+$/);
  assert.deepEqual(lines.slice(1), ['configured', '', 'λ', '--flag', 'quote" with spaces', '$(shell-looking)', 'from stdin', '']);
  assert.equal(result.stderr, '');
  assert.equal(await readFile(join(caller, 'run-cwd.txt'), 'utf8'), 'caller');

  await writeFile(join(project, 'main.sld'), source('(panic "run failure")'));
  const failure = run('app');
  failure.child.stdin.end('status\n');
  await assert.rejects(failure, error => error.code === 1 && /run failure/.test(error.stderr) && error.stdout.endsWith('status\n'));
  const beforeFailure = await realpath(join(project, 'build/program'));
  await writeFile(join(project, 'main.sld'), '(import (snail core base)) (missing-function)');
  await assert.rejects(run('app'), error => error.code === 1 && error.stdout === '' && /missing-function/.test(error.stderr));
  assert.equal(await realpath(join(project, 'build/program')), beforeFailure, 'failed rebuild never runs the preceding output');
  for (const name of ['missing', 'program']) {
    await assert.rejects(run(name), error => error.code === 1 && error.stdout === '' && /unknown project run target/.test(error.stderr));
  }

  // The original CLI PID is now the application; no signal forwarding exists.
  await writeFile(join(project, 'main.sld'), '(import (snail core base) (snail core io)) (write-line "ready") (read-line)');
  for (const signal of ['SIGINT', 'SIGTERM']) {
    const waiting = run('app'), stopped = assert.rejects(waiting, {signal});
    await ready(waiting.child);
    assert.equal(waiting.child.kill(signal), true);
    await stopped;
  }
} finally {
  await rm(project, {recursive: true, force: true});
  await rm(caller, {recursive: true, force: true});
}
console.log('project run: immutable output, arguments, stdin, working directory, status and signals');
