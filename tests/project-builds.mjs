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
const project = await mkdtemp(join(tmpdir(), 'snail-project-'));
const build = target => execute(join(root, 'snail'), ['build', project, target]);
const output = target => join(project, 'build', target);
const source = '(import (snail core base) (snail core io) (greeting))\n(define (main) (→ Unit) (! output-port) (display (greeting)))\n';
const description = publicPath => `((build-target cli (program (entry "main.sld") (library-roots ("src"))))
 (build-target page (browser (entry "main.sld") (library-roots ("src")) (public "${publicPath}")))
 (build-target occupied (program (entry "main.sld") (library-roots ("src"))))
 (run-target dev (run cli (args ("ignored-by-build")))))`;

try {
  await mkdir(join(project, 'src'));
  await mkdir(join(project, 'public', 'nested'), {recursive: true});
  await writeFile(join(project, 'src/greeting.sld'), '(define-library (greeting) (export greeting) (import (snail core base)) (begin (define (greeting) (→ String) "hello project")))');
  await writeFile(join(project, 'main.sld'), source);
  await writeFile(join(project, 'project.datum'), description('public'));
  await writeFile(join(project, 'public/index.html'), '<!doctype html><title>Project</title>');
  await writeFile(join(project, 'public/nested/data.bin'), Buffer.from([0, 255, 127]));
  await writeFile(join(project, 'public/obsolete.txt'), 'first generation');

  await assert.rejects(build('missing'), /unknown project build target/);
  assert.equal((await build('cli')).stdout.trim(), output('cli'), 'building does not run launch commands');
  const executed = await execute(process.execPath, ['--no-warnings', join(root, 'host/native/run-snail.mjs'), join(output('cli'), 'program.wasm')]);
  assert.equal(executed.stdout, 'hello project', 'entry and explicit library roots reach the existing compiler');

  await build('page');
  const first = await realpath(output('page'));
  assert.equal(await readFile(join(first, 'index.html'), 'utf8'), '<!doctype html><head><link id="snail-web-app" rel="manifest" href="./manifest.webmanifest"><title>Project</title>');
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
  await writeFile(join(project, 'public/manifest.webmanifest'), customManifest);
  await rm(join(project, 'public/obsolete.txt'));
  await build('page');
  const second = await realpath(output('page'));
  assert.notEqual(second, first);
  assert.equal(await readFile(join(second, 'manifest.webmanifest'), 'utf8'), customManifest, 'custom manifest replaces the default whole');
  await assert.rejects(readFile(join(second, 'obsolete.txt')), {code: 'ENOENT'});
  assert.equal(await readFile(join(first, 'obsolete.txt'), 'utf8'), 'first generation', 'old readers keep their complete generation');

  await writeFile(join(project, 'main.sld'), '(import (snail core base)) (define (main) (→ Unit) (missing-function))');
  await assert.rejects(build('page'));
  assert.equal(await realpath(output('page')), second, 'failed compiler attempt leaves output unchanged');
  await writeFile(join(project, 'main.sld'), source);
  await mkdir(join(project, 'public/host.mjs'));
  await assert.rejects(build('page'), /conflicts with a build artifact/);
  assert.equal(await realpath(output('page')), second, 'failed packaging leaves output unchanged');
  await rm(join(project, 'public/host.mjs'), {recursive: true});
  // This program links no files, but a build of one that does writes store/.
  await mkdir(join(project, 'public/store'));
  await assert.rejects(build('page'), /conflicts with a build artifact: .*store/);
  assert.equal(await realpath(output('page')), second, 'a reserved name is refused in every build');
  await rm(join(project, 'public/store'), {recursive: true});
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
  // Selecting a type emits an ordinary Application call, including task effects.
  await mkdir(join(project, 'src', 'typed'), {recursive: true});
  await writeFile(join(project, 'src', 'typed', 'entry.sld'), `(define-library (typed entry)
    (export Printer Missing Generic)
    (import (snail core base) (snail core io) (snail shell application) (snail shell task))
    (begin
      (record Printer ()) (record Missing ()) (record (Generic A) ())
      (instance (Application (! output-port tasks) Printer)
        (define (start (entry (Entry Printer))) (→ Unit) (! output-port tasks) (yield) (write-line "typed entry")))))`);
  const selected = type => `((build-target selected
    (program (entry ((typed entry) ${type})) (library-roots ("src")))))`;
  await writeFile(join(project, 'project.datum'), selected('Printer'));
  await build('selected');
  const typed = await execute(process.execPath, ['--no-warnings', join(root, 'host/native/run-snail.mjs'),
    join(output('selected'), 'program.wasm')]);
  assert.equal(typed.stdout.trim(), 'typed entry');
  for (const type of ['Missing', 'Unknown', 'Generic']) {
    await writeFile(join(project, 'project.datum'), selected(type));
    await assert.rejects(build('selected'), type === 'Missing' ? /no instance/ : /not a type|type arguments/);
  }
  console.log('project builds passed');
} finally {
  await rm(project, {recursive: true, force: true});
}
