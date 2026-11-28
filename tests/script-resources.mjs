// Linked files are objects of a build's store, named for the SHA-256 of
// their bytes, and each host reads one when a task first asks for it.
//   node tests/script-resources.mjs ROOT
//
// A library links two files beside its source. A script built for node and
// for the browser each place them in the workspace's store,
// build/.snail-store, and name them at store/sha256/AB/DIGEST beside the
// program's module, debug or release, as hard links: every script's builds
// share one copy, and each output still holds its files. The program
// prints the bytes of one, read in a task, natively and through the
// browser host's loader fetching the page's files over HTTP, which never
// fetches the file the program does not read. The store remembers each
// file's digest with its size and modification time, which a build trusts
// while they hold.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, realpath, rm, stat, symlink, writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {blobPartSize, createWasi, linkModule, objectPath, partPath, runMain} from '../host/browser/load.mjs';
import {createTasks, taskExports} from '../host/browser/tasks.mjs';

const execute = promisify(execFile), root = process.argv[2];
const project = await mkdtemp(join(tmpdir(), 'snail-workspace-resources-'));
const build = (target, ...flags) => execute(join(root, 'snail-scheme'), ['build', ...flags, '--target', target === 'cli' ? 'node' : 'browser', 'main.scm'], {cwd: project});
const output = join(project, 'build/main');
const run = path => execute(process.execPath, ['--no-warnings', join(root, 'host/native/run-snail.mjs'), path]);
const write = async (name, contents) => { await mkdir(join(project, name, '..'), {recursive: true}); await writeFile(join(project, name), contents); };
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const hero = Buffer.from([1, 2, 3, 255]), villain = Buffer.from([7, 8, 9, 10]);
const resource = (directory, bytes) => readFile(join(directory, objectPath(digest(bytes))));

// The browser host fetches a static page's files relative to its module,
// so serve the output as a page's server would and read through it: the
// module a page names. The program's lines, and the paths the page fetched.
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
      return response.arrayBuffer();
    };
    const wasi = createWasi({print: (fd, line) => lines.push(line)});
    let program;
    const tasks = createTasks(() => program && taskExports(program), {reportError(error) { throw error; }});
    program = await linkModule(read, name, wasi, {}, () => tasks);
    runMain(program.exports, tasks);
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
  await write('main.scm', `(import (snail core base) (snail core io) (snail shell resource) (assets sprites))
(define (main (out OutputPort) (resources Resources)) (→ Unit)
  (write-line out (string-join (map (lambda (byte) (show (u8->i32 byte))) (array->list (read-resource resources (hero)))) ",")))\n`);
  const tile = Buffer.from([1, 8, 3]);
  await write('main.resources/maps/tile.bin', tile);
  await write('main.resources/copy.bin', villain);
  const catalog = {'copy.bin': {sha256: digest(villain), size: villain.length},
    'maps/tile.bin': {sha256: digest(tile), size: tile.length}};
  await write('public/index.html', '<!doctype html><title>Resources</title>');

  assert.equal(blobPartSize, 25 * 1024 * 1024);
  const hostFormat = await readFile(join(root, 'host/browser/blob-format.mjs'), 'utf8');
  await build('cli');
  assert.equal(await readFile(join(output, 'host/browser/blob-format.mjs'), 'utf8'), hostFormat);
  assert.deepEqual(JSON.parse(await readFile(join(output, 'resources.json'))), catalog);
  assert.deepEqual(await resource(output, tile), tile, 'server bundles publish unlinked files');
  assert.deepEqual(await resource(output, hero), hero, 'the node build places the file');
  assert.deepEqual(await resource(output, villain), villain);
  assert.equal((await run(join(output, 'main.wasm'))).stdout, '1,2,3,255\n', 'the native host reads it when the task asks');
  // A file is hashed once, not every build: the store remembers its
  // digest, and a build that finds the file unchanged in size and time
  // trusts it, as make trusts a time, here even when it is false.
  const digests = join(project, 'build/.snail-store/digests'), remembered = await readFile(digests, 'utf8');
  for (const [name, bytes] of [['hero', hero], ['villain', villain]])
    assert.match(remembered, new RegExp(`^${digest(bytes)} ${bytes.length} \\d+ \\S*art/${name}\\.bin$`, 'm'));
  await writeFile(digests, remembered.replace(`${digest(hero)} `, `${digest(villain)} `));
  await build('cli');
  assert.equal((await run(join(output, 'main.wasm'))).stdout, '7,8,9,10\n', 'a remembered digest is trusted');
  await writeFile(digests, remembered);
  await build('cli');
  // The workspace's store holds each file once, and every build names it
  // from there: a rebuild, a release build and another script's build all
  // share the one copy, and each output still holds its files without it.
  const shared = join(project, 'build/.snail-store'), inode = async directory => (await stat(join(directory, objectPath(digest(hero))))).ino;
  const stored = (await stat(join(shared, objectPath(digest(hero)).replace(/^store\//, '')))).ino;
  assert.equal(await inode(output), stored, 'a build names the store\'s object');
  const first = await realpath(output);
  await build('cli', '--release');
  assert.notEqual(await realpath(output), first);
  assert.equal(await inode(output), stored, 'a release build names it too');
  await write('tools/other.scm', await readFile(join(project, 'main.scm')));
  await execute(join(root, 'snail-scheme'), ['build', '--target', 'node', 'tools/other.scm'], {cwd: project});
  assert.equal(await inode(join(project, 'build/tools/other')), stored, 'as another script\'s build does');
  await rm(shared, {recursive: true});
  assert.deepEqual(await resource(output, hero), hero, 'and an output outlives the store');
  assert.equal((await run(join(output, 'main.wasm'))).stdout, '1,2,3,255\n', 'beside its optimized module');

  await build('page');
  assert.equal(await readFile(join(output, 'blob-format.mjs'), 'utf8'), hostFormat);
  assert.deepEqual(JSON.parse(await readFile(join(output, 'resources.json'))), catalog);
  const module = new WebAssembly.Module(await readFile(join(output, 'main.wasm')));
  assert.ok(!WebAssembly.Module.imports(module).some(i => i.module === 'snail.runtime.link' && i.name === digest(tile)));
  assert.deepEqual(await resource(output, tile), tile, 'static hosts publish the same files');
  assert.deepEqual(await resource(output, hero), hero, 'the browser build places the file');
  const page = await pageOutput(output, 'main.wasm');
  assert.equal(page.output, '1,2,3,255', 'the browser host fetches it beside the module');
  assert.ok(page.fetched.includes(`/${objectPath(digest(hero))}`), page.fetched.join(' '));
  assert.ok(!page.fetched.includes(`/${objectPath(digest(villain))}`), 'a file the program never reads is never fetched');
  await build('page', '--release');
  const released = await pageOutput(output, 'main.wasm');
  assert.equal(released.output, '1,2,3,255', 'a release page reads it the same way');
  assert.ok(!released.fetched.includes(`/${objectPath(digest(villain))}`), released.fetched.join(' '));

  // An edited file is new bytes under a new name, copied.
  await write('src/assets/art/hero.bin', Buffer.from([9, 9]));
  await build('cli');
  assert.equal((await run(join(output, 'main.wasm'))).stdout, '9,9\n', 'an edited file is placed anew');
  await rm(join(project, 'src/assets/art/hero.bin'));
  await assert.rejects(build('cli'), /sprites\.sld:\d+:\d+: the library assets\.sprites links art\/hero\.bin, but there is no file at /);
  await write('src/assets/art/hero.bin', hero);

  await symlink(join(project, 'main.scm'), join(project, 'main.resources/link'));
  await assert.rejects(build('page'), /resource must be a regular file/);
  await rm(join(project, 'main.resources/link'));
  await write('public/resources.json', '{}');
  await assert.rejects(build('page'), /public file conflicts with a build artifact/);
  await rm(join(project, 'public/resources.json'));

  // The identical file is both published by name and linked by the program.
  const large = Buffer.alloc(blobPartSize + 3, 17);
  large.set([93, 94, 95, 96], blobPartSize - 1);
  await write('main.resources/large.bin', large);
  await write('main.resources/exact.bin', large.subarray(0, blobPartSize));
  await write('main.resources/empty.bin', Buffer.alloc(0));
  await write('main.scm', `(import (snail core base) (snail core io) (snail shell resource))
    (define (main (out OutputPort) (resources Resources)) (→ Unit)
      (let ((b (read-resource resources (link-file "main.resources/large.bin"))))
        (write-line out (string-join (list (show (array-length b))
          (show (u8->i32 (array-ref b ${blobPartSize - 1}))) (show (u8->i32 (array-ref b ${blobPartSize})))
          (show (u8->i32 (array-ref b ${blobPartSize + 2})))) ","))))`);
  const sha = digest(large), paths = [partPath(sha, 0), partPath(sha, 1)];
  const expected = `${large.length},93,94,96`;
  await build('cli');
  const manifest = JSON.parse(await readFile(join(output, 'resources.json')));
  const compiled = new WebAssembly.Module(await readFile(join(output, 'main.wasm')));
  assert.ok(WebAssembly.Module.imports(compiled).some(i => i.module === 'snail.runtime.link' && i.name === `${sha}:${large.length}:${blobPartSize}`));
  assert.deepEqual(manifest['large.bin'], {sha256: sha, size: large.length});
  for (const file of ['empty.bin', 'exact.bin']) {
    const {sha256, size} = manifest[file];
    assert.equal((await stat(join(output, objectPath(sha256)))).size, size);
    await assert.rejects(stat(join(output, partPath(sha256, 0))), {code: 'ENOENT'});
  }
  await assert.rejects(stat(join(output, objectPath(sha))), {code: 'ENOENT'});
  for (const [i, path] of paths.entries()) {
    const file = await stat(join(output, path));
    assert.equal(file.size, i === 0 ? blobPartSize : 3);
    assert.equal(file.ino, (await stat(join(shared, path.slice('store/'.length)))).ino);
  }
  assert.equal((await run(join(output, 'main.wasm'))).stdout.trim(), expected);
  await rm(join(shared, paths[1].slice('store/'.length)));
  await build('page');
  const multipart = await pageOutput(output, 'main.wasm');
  assert.equal(multipart.output, expected);
  assert.deepEqual(multipart.fetched.filter(path => path.startsWith('/store/')), paths.map(path => '/' + path));
  // Correct length and wrong contents must fail the full digest check.
  await writeFile(join(output, paths[1]), Buffer.from([0, 0, 0]));
  await assert.rejects(pageOutput(output, 'main.wasm'), /SHA-256/);
  console.log('script resources passed');
} finally {
  await rm(project, {recursive: true, force: true});
}
