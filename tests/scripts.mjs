// Scripts: a source file built and run for an explicit target, with its
// imports under its workspace's src/ and its output at build/PATH.
//   node tests/scripts.mjs ROOT
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdir, mkdtemp, readFile, readdir, realpath, rm, stat, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {promisify} from 'node:util';

const execute = promisify(execFile), root = process.argv[2];
const workspace = await mkdtemp(join(tmpdir(), 'snail-scripts-'));
const command = (...args) => execute(join(root, 'snail-scheme'), args, {cwd: workspace});
const write = async (name, text) => {
  await mkdir(dirname(join(workspace, name)), {recursive: true});
  await writeFile(join(workspace, name), text);
};
const script = `(import (snail core base) (snail core io) (tools greeting))
(write-line (greeting))
(match (command-line) ((Cons _ rest) (for-each write-line rest)) ((Nil) (unit)))
`;

try {
  await write('src/tools/greeting.sld', '(define-library (tools greeting) (export greeting) (import (snail core base)) (begin (define (greeting) (→ String) "hello from src")))');
  await write('apps/hello/main.scm', script);

  const output = join(workspace, 'build/apps/hello/main');
  assert.equal((await command('build', '--target', 'node', 'apps/hello/main.scm')).stdout.trim(), output,
    'the output is the script path without its extension');
  const generation = await realpath(output);
  assert.equal(dirname(generation), dirname(output), 'the generation lies beside its link');
  const files = async directory => (await readdir(directory)).filter(name => !name.startsWith('.'));
  assert.deepEqual(await files(generation), ['main.wasm'], 'a build is one linked module, named for the script');

  for (const target of ['node', 'wasmtime']) {
    const ran = await command('run', '--target', target, 'apps/hello/main.scm', 'one', 'two words');
    assert.equal(ran.stdout, 'hello from src\none\ntwo words\n', `${target} runs the script with its arguments`);
  }

  const debugSize = (await stat(join(generation, 'main.wasm'))).size;
  await command('build', '--release', '--target', 'node', 'apps/hello/main.scm');
  const release = await realpath(output);
  assert.deepEqual(await files(release), ['main.wasm'], 'a release build is the same module');
  assert.ok((await stat(join(release, 'main.wasm'))).size < debugSize, 'which wasm-opt made smaller');
  for (const target of ['node', 'wasmtime']) {
    const ran = await command('run', '--release', '--target', target, 'apps/hello/main.scm', 'one');
    assert.equal(ran.stdout, 'hello from src\none\n', `${target} runs the release build`);
  }

  await write('apps/hello/public/index.html', '<!doctype html><title>Hello</title>');
  await command('build', '--target', 'browser', 'apps/hello/main.scm');
  const page = await realpath(output);
  assert.match(await readFile(join(page, 'index.html'), 'utf8'), /content="\.\/main\.wasm"/,
    'a page names its module');
  assert.ok((await readdir(page)).includes('host.mjs'), 'a page holds the browser host');
  await assert.rejects(command('run', '--target', 'browser', 'apps/hello/main.scm'), /a page is not run here/);
  await command('build', '--release', '--target', 'browser', 'apps/hello/main.scm');
  assert.match(await readFile(join(await realpath(output), 'index.html'), 'utf8'), /content="\.\/main\.wasm"/,
    'as a release page does');

  await assert.rejects(command('run', '--target', 'deno', 'apps/hello/main.scm'), /unknown target deno/);
  await assert.rejects(command('run', '--target', 'node', 'apps/missing.scm'), /there is no script at/);
  const outside = await mkdtemp(join(tmpdir(), 'snail-no-workspace-'));
  try {
    await writeFile(join(outside, 'lost.scm'), script);
    await assert.rejects(execute(join(root, 'snail-scheme'), ['build', '--target', 'node', join(outside, 'lost.scm')]),
      /no folder above .*lost\.scm holds src\//);
  } finally { await rm(outside, {recursive: true, force: true}); }
  assert.match((await command('wat', '--target', 'node', 'apps/hello/main.scm')).stdout, /^\(module/);
  console.log('scripts passed');
} finally {
  await rm(workspace, {recursive: true, force: true});
}
