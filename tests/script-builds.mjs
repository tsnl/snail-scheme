// Script builds publish complete generations: a page's public folder and
// host, a web-app manifest, and a failed build that changes nothing.
//   node tests/script-builds.mjs ROOT
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {chmod, mkdir, mkdtemp, readFile, realpath, rm, symlink, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';

const execute = promisify(execFile);
const root = process.argv[2];
const project = await mkdtemp(join(tmpdir(), 'snail-workspace-'));
const scripts = {cli: ['node', 'cli.scm'], page: ['browser', 'page/main.scm'], occupied: ['node', 'occupied.scm']};
const build = target => execute(join(root, 'snail-scheme'), ['build', '--target', scripts[target][0], scripts[target][1]], {cwd: project});
const output = target => join(project, 'build', scripts[target][1].replace(/\.scm$/, ''));
const source = '(import (snail core base) (snail core io) (greeting))\n(display (greeting))\n';

try {
  await mkdir(join(project, 'src'));
  await mkdir(join(project, 'page/public/nested'), {recursive: true});
  await writeFile(join(project, 'src/greeting.sld'), '(define-library (greeting) (export greeting) (import (snail core base)) (begin (define (greeting) (→ String) "hello project")))');
  for (const file of ['cli.scm', 'page/main.scm', 'occupied.scm']) await writeFile(join(project, file), source);
  const pub = name => join(project, 'page/public', name);
  await writeFile(pub('index.html'), '<!doctype html><title>Project</title>');
  await writeFile(pub('nested/data.bin'), Buffer.from([0, 255, 127]));
  await writeFile(pub('obsolete.txt'), 'first generation');

  assert.equal((await build('cli')).stdout.trim(), output('cli'), 'building does not run the program');
  const executed = await execute(process.execPath, ['--no-warnings', join(root, 'host/native/run-snail.mjs'), join(output('cli'), 'cli.manifest.datum')]);
  assert.equal(executed.stdout, 'hello project', 'the workspace src/ reaches the compiler');

  await build('page');
  const first = await realpath(output('page'));
  assert.equal(await readFile(join(first, 'index.html'), 'utf8'), '<!doctype html><head><link id="snail-web-app" rel="manifest" href="./manifest.webmanifest"><meta name="snail-modules" content="./main.manifest.datum"><title>Project</title>');
  const webApp = JSON.parse(await readFile(join(first, 'manifest.webmanifest'), 'utf8'));
  assert.equal(webApp.id, undefined); assert.equal(webApp.start_url, './'); assert.equal(webApp.scope, './');
  assert.equal(webApp.display, 'standalone');
  for (const size of [192, 512]) {
    const png = await readFile(join(first, `snail-icon-${size}.png`));
    assert.equal(png.readUInt32BE(16), size); assert.equal(png.readUInt32BE(20), size);
  }
  assert.deepEqual(await readFile(join(first, 'nested/data.bin')), Buffer.from([0, 255, 127]));
  assert.equal(await readFile(join(first, 'host.mjs'), 'utf8'), await readFile(join(root, 'host/browser/host.mjs'), 'utf8'));

  const customManifest = JSON.stringify({id:'/custom-project-app', name:'My application', start_url:'./', display:'fullscreen'});
  await writeFile(pub('manifest.webmanifest'), customManifest);
  await rm(pub('obsolete.txt'));
  await build('page');
  const second = await realpath(output('page'));
  assert.notEqual(second, first);
  assert.equal(await readFile(join(second, 'manifest.webmanifest'), 'utf8'), customManifest, 'custom manifest replaces the default whole');
  await assert.rejects(readFile(join(second, 'obsolete.txt')), {code: 'ENOENT'});
  assert.equal(await readFile(join(first, 'obsolete.txt'), 'utf8'), 'first generation', 'old readers keep their complete generation');

  await writeFile(join(project, 'page/main.scm'), '(import (snail core base)) (missing-function)');
  await assert.rejects(build('page'));
  assert.equal(await realpath(output('page')), second, 'failed compiler attempt leaves output unchanged');
  await writeFile(join(project, 'page/main.scm'), source);
  await mkdir(pub('host.mjs'));
  await assert.rejects(build('page'), /conflicts with a build artifact/);
  assert.equal(await realpath(output('page')), second, 'failed packaging leaves output unchanged');
  await rm(pub('host.mjs'), {recursive: true});
  // Every build writes store/, which holds the program's objects.
  await mkdir(pub('store'));
  await assert.rejects(build('page'), /conflicts with a build artifact: .*store/);
  assert.equal(await realpath(output('page')), second, 'a reserved name is refused in every build');
  await rm(pub('store'), {recursive: true});
  await symlink(project, pub('recursive-link'));
  await assert.rejects(build('page'), /cannot be symbolic links/);
  assert.equal(await realpath(output('page')), second);
  await rm(pub('recursive-link'));

  if (process.getuid() !== 0) {
    await chmod(pub('nested'), 0);
    try {
      await assert.rejects(build('page'), /cannot read directory/);
      assert.equal(await realpath(output('page')), second, 'an unreadable public directory is not silently omitted');
    } finally { await chmod(pub('nested'), 0o755); }
  }

  await mkdir(output('occupied'));
  await writeFile(join(output('occupied'), 'keep.txt'), 'unmanaged');
  await assert.rejects(build('occupied'), /unmanaged build output/);
  assert.equal(await readFile(join(output('occupied'), 'keep.txt'), 'utf8'), 'unmanaged');
  console.log('script builds passed');
} finally {
  await rm(project, {recursive: true, force: true});
}
