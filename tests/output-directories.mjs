// Public compiler outputs: execute the published artifact, retain a last
// successful build on failure, and never remove unrelated directory contents.
//   node tests/output-directories.mjs ROOT
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdir, mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';

const execute = promisify(execFile);
const root = process.argv[2];
const directory = await mkdtemp(join(tmpdir(), 'lofi-outputs-'));
const lofi = (...args) => execute(join(root, 'lofi'), args, {cwd: directory});
const run = file => execute(process.execPath, ['--no-warnings', join(root, 'scripts/run-lofi.mjs'), file]);

try {
  const source = join(directory, 'main.sld');
  const output = join(directory, 'built');
  const program = join(output, 'program.wasm');
  await writeFile(source, '(import (lofi base) (lofi io))\n(display "first")\n');
  await assert.rejects(lofi('compile', source), /requires -o DIRECTORY/);
  await lofi('compile', '-o', output, source);
  assert.deepEqual(await readdir(output), ['program.wasm'], 'intermediates stay private');
  assert.equal((await run(program)).stdout, 'first');

  await writeFile(join(output, 'keep.txt'), 'unrelated');
  await writeFile(source, '(import (lofi base) (lofi io))\n(display "second")\n');
  assert.equal((await lofi('run', '-o', output, source)).stdout, 'second');
  const successful = await readFile(program);
  await writeFile(source, '(import (lofi base))\n(no-such-function)\n');
  await assert.rejects(lofi('compile', '-o', output, source));
  assert.deepEqual(await readFile(program), successful, 'failed compilation preserves the last build');
  assert.equal((await run(program)).stdout, 'second');
  assert.equal(await readFile(join(output, 'keep.txt'), 'utf8'), 'unrelated');
  assert.deepEqual((await readdir(output)).sort(), ['keep.txt', 'program.wasm']);

  const fibonacci = join(root, 'examples/fibonacci.sld');
  const file = join(directory, 'existing-file');
  await writeFile(file, 'keep this file');
  await assert.rejects(lofi('compile', '-o', file, fibonacci), /cannot create output directory/);
  assert.equal(await readFile(file, 'utf8'), 'keep this file');

  const blocked = join(directory, 'blocked');
  await mkdir(join(blocked, 'program.wasm'), {recursive: true});
  await writeFile(join(blocked, 'program.wasm', 'keep.txt'), 'keep this directory');
  await assert.rejects(lofi('compile', '-o', blocked, fibonacci), /cannot publish program/);
  assert.deepEqual(await readdir(blocked), ['program.wasm'], 'failed publication cleans its staging directory');
  assert.equal(await readFile(join(blocked, 'program.wasm', 'keep.txt'), 'utf8'), 'keep this directory');

  await assert.rejects(lofi('run', '-o', output, join(root, 'tests/tasks/failure.sld')));
  assert.notDeepEqual(await readFile(program), successful, 'execution failure does not undo a successful build');
  assert.equal(await readFile(join(output, 'keep.txt'), 'utf8'), 'unrelated');
  console.log('output directories passed');
} finally {
  await rm(directory, {recursive: true, force: true});
}
