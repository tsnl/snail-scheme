// Project builds preserve compiler semantics and publish complete directories.
//   node tests/project-builds.mjs ROOT
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {chmod, mkdir, mkdtemp, readFile, realpath, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';

const execute = promisify(execFile);
const root = process.argv[2];
const project = await mkdtemp(join(tmpdir(), 'lofi-project-'));
const build = target => execute(join(root, 'lofi'), ['build', project, target]);
const output = target => join(project, 'build', target);
const source = '(import (lofi base) (lofi io) (greeting))\n(display greeting)\n';
const description = publicPath => `((build-target cli (program (entry "main.sld") (library-roots ("src"))))
 (build-target page (browser (entry "main.sld") (library-roots ("src")) (public "${publicPath}")))
 (build-target occupied (program (entry "main.sld") (library-roots ("src"))))
 (run-target dev (run cli (args ("ignored-by-build")))))`;

try {
  await mkdir(join(project, 'src'));
  await mkdir(join(project, 'public', 'nested'), {recursive: true});
  await writeFile(join(project, 'src/greeting.sld'), '(define-library (greeting) (export greeting) (import (lofi base)) (begin (: greeting String) (define greeting "hello project")))');
  await writeFile(join(project, 'main.sld'), source);
  await writeFile(join(project, 'project.datum'), description('public'));
  await writeFile(join(project, 'public/index.html'), '<!doctype html><title>Project</title>');
  await writeFile(join(project, 'public/nested/data.bin'), Buffer.from([0, 255, 127]));
  await writeFile(join(project, 'public/obsolete.txt'), 'first generation');

  await assert.rejects(build('missing'), /unknown project build target/);
  assert.equal((await build('cli')).stdout.trim(), output('cli'), 'building does not run launch commands');
  const executed = await execute(process.execPath, ['--no-warnings', join(root, 'scripts/run-lofi.mjs'), join(output('cli'), 'program.wasm')]);
  assert.equal(executed.stdout, 'hello project', 'entry and explicit library roots reach the existing compiler');

  await build('page');
  const first = await realpath(output('page'));
  assert.equal(await readFile(join(first, 'index.html'), 'utf8'), '<!doctype html><title>Project</title>');
  assert.deepEqual(await readFile(join(first, 'nested/data.bin')), Buffer.from([0, 255, 127]));
  assert.equal(await readFile(join(first, 'host.mjs'), 'utf8'), await readFile(join(root, 'src/app/host.mjs'), 'utf8'));

  await rm(join(project, 'public/obsolete.txt'));
  await build('page');
  const second = await realpath(output('page'));
  assert.notEqual(second, first);
  await assert.rejects(readFile(join(second, 'obsolete.txt')), {code: 'ENOENT'});
  assert.equal(await readFile(join(first, 'obsolete.txt'), 'utf8'), 'first generation', 'old readers keep their complete generation');

  await writeFile(join(project, 'main.sld'), '(import (lofi base)) (missing-function)');
  await assert.rejects(build('page'));
  assert.equal(await realpath(output('page')), second, 'failed compiler attempt leaves output unchanged');
  await writeFile(join(project, 'main.sld'), source);
  await mkdir(join(project, 'public/host.mjs'));
  await assert.rejects(build('page'), /conflicts with a build artifact/);
  assert.equal(await realpath(output('page')), second, 'failed packaging leaves output unchanged');
  await rm(join(project, 'public/host.mjs'), {recursive: true});
  await symlink(project, join(project, 'public/recursive-link'));
  await assert.rejects(build('page'), /cannot be symbolic links/);
  assert.equal(await realpath(output('page')), second);
  await rm(join(project, 'public/recursive-link'));

  if (process.getuid() !== 0) {
    await chmod(join(project, 'public/nested'), 0);
    try {
      await assert.rejects(build('page'), /cannot read directory/);
      assert.equal(await realpath(output('page')), second, 'an unreadable public directory is not silently omitted');
    } finally { await chmod(join(project, 'public/nested'), 0o755); }
  }

  await mkdir(output('occupied'));
  await writeFile(join(output('occupied'), 'keep.txt'), 'unmanaged');
  await assert.rejects(build('occupied'), /unmanaged project output/);
  assert.equal(await readFile(join(output('occupied'), 'keep.txt'), 'utf8'), 'unmanaged');
  await writeFile(join(project, 'project.datum'), description('.'));
  await assert.rejects(build('page'), /overlaps project build output/);
  assert.equal(await realpath(output('page')), second);
  console.log('project builds passed');
} finally {
  await rm(project, {recursive: true, force: true});
}
