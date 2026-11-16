// Linked files are objects of a workspace's store, named for the SHA-256
// of their bytes, and each host reads one when a task first asks for it.
//   node tests/script-resources.mjs ROOT
//
// A library links two files beside its source. A script built for node and
// for the browser each place them in the workspace's store, build/.snail-store,
// and view them at store/sha256/AB/DIGEST in their output, a link in a debug
// build and a copy beside the one linked module of a release one; the
// program prints the bytes of one,
// read in a task, natively and through the browser host's loader fetching
// the page's files over HTTP, which never fetches the file the program does
// not read.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstat, mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {createWasi, linkModule, linkProgram, objectPath, programExports, runMain} from '../host/browser/load.mjs';
import {createTasks, taskExports} from '../host/browser/tasks.mjs';

const execute = promisify(execFile), root = process.argv[2];
const project = await mkdtemp(join(tmpdir(), 'snail-workspace-resources-'));
const build = (target, ...flags) => execute(join(root, 'snail-scheme'), ['build', ...flags, '--target', target === 'cli' ? 'node' : 'browser', 'main.scm'], {cwd: project});
const output = join(project, 'build/main');
const run = path => execute(process.execPath, ['--no-warnings', join(root, 'host/native/run-snail.mjs'), path]);
const write = async (name, contents) => { await mkdir(join(project, name, '..'), {recursive: true}); await writeFile(join(project, name), contents); };
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const hero = Buffer.from([1, 2, 3, 255]), villain = Buffer.from([7]);
const resource = (directory, bytes) => readFile(join(directory, objectPath(digest(bytes))));
const viewed = async (directory, bytes) => (await lstat(join(directory, objectPath(digest(bytes))))).isSymbolicLink() ? 'link' : 'copy';

// The browser host fetches a static page's files relative to its module,
// so serve the output as a page's server would and read through it: the
// program a page names, a debug build's manifest or a release build's
// module. The program's lines, and the paths the page fetched.
async function pageOutput(directory, name) {
  const fetched = [];
  const server = createServer(async (request, response) => {
    const path = decodeURIComponent(new URL(request.url, 'http://page').pathname);
    fetched.push(path);
    try { response.end(await readFile(join(directory, path))); }
    catch { response.writeHead(404).end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}/${name}`, lines = [];
  try {
    const read = async file => {
      const response = await fetch(new URL(file, base));
      if (!response.ok) throw new Error(`${response.status} fetching ${file}`);
      return new Uint8Array(await response.arrayBuffer());
    };
    const wasi = createWasi({print: (fd, line) => lines.push(line)});
    let program;
    const tasks = createTasks(() => program && taskExports(program));
    const linked = name.endsWith('.wasm');
    program = await (linked ? linkModule : linkProgram)(read, name, wasi, {}, () => tasks);
    runMain(linked ? program.exports : programExports(program), tasks);
    try { await tasks.drive(); }
    finally { tasks.close(); }
    return {output: lines.join('\n'), fetched};
  } finally { server.close(); }
}

try {
  await write('src/assets/sprites.sld', `(define-library (assets sprites) (export hero villain) (import (snail core base) (snail shell resource))
    (begin (define (hero) (→ Resource) (link-file "art/hero.bin")) (define (villain) (→ Resource) (link-file "art/villain.bin"))))`);
  await write('src/assets/art/hero.bin', hero);
  await write('src/assets/art/villain.bin', villain);
  await write('main.scm', `(import (snail core base) (snail core io) (only (snail shell task) tasks) (snail shell resource) (assets sprites))
(define (main) (→ Unit) (! output-port resource tasks)
  (write-line (string-join (map (lambda (byte) (show (u8->i32 byte))) (array->list (read-resource (hero)))) ",")))\n`);
  await write('public/index.html', '<!doctype html><title>Resources</title>');

  await build('cli');
  assert.deepEqual(await resource(output, hero), hero, 'the node build places the file');
  assert.deepEqual(await resource(output, villain), villain);
  assert.equal(await viewed(output, hero), 'link', 'a debug build links to the store');
  assert.deepEqual(await readFile(join(project, 'build/.snail-store', objectPath(digest(hero)).replace(/^store\//, ''))), hero,
                   'the workspace store holds it');
  assert.equal((await run(join(output, 'main.manifest.datum'))).stdout, '1,2,3,255\n', 'the native host reads it when the task asks');
  await build('cli', '--release');
  assert.equal(await viewed(output, hero), 'copy', 'a release build copies it');
  assert.equal((await run(join(output, 'main.wasm'))).stdout, '1,2,3,255\n', 'beside its one module');

  await build('page');
  assert.deepEqual(await resource(output, hero), hero, 'the browser build places the file');
  const page = await pageOutput(output, 'main.manifest.datum');
  assert.equal(page.output, '1,2,3,255', 'the browser host fetches it beside the module');
  assert.ok(page.fetched.includes(`/${objectPath(digest(hero))}`), page.fetched.join(' '));
  assert.ok(!page.fetched.includes(`/${objectPath(digest(villain))}`), 'a file the program never reads is never fetched');
  await build('page', '--release');
  const released = await pageOutput(output, 'main.wasm');
  assert.equal(released.output, '1,2,3,255', 'a release page reads it beside its one module');
  assert.ok(!released.fetched.includes(`/${objectPath(digest(villain))}`), released.fetched.join(' '));

  await rm(join(project, 'src/assets/art/hero.bin'));
  await assert.rejects(build('cli'), /sprites\.sld:\d+:\d+: the library assets\.sprites links art\/hero\.bin, but there is no file at /);
  await write('src/assets/art/hero.bin', hero);

  console.log('script resources passed');
} finally {
  await rm(project, {recursive: true, force: true});
}
