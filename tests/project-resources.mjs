// Linked files ship beside the payload of every project build, named for
// the SHA-256 of their bytes, and each host reads one when a task first
// asks for it.
//   node tests/project-resources.mjs ROOT
//
// A library links two files beside its source. A program target and a
// browser target each place them at resources/DIGEST in their output; the
// program prints the bytes of one, read in a task, natively and through
// the browser host's loader fetching the page's files over HTTP, which
// never fetches the file the program does not read. A development build
// places the file too, seen from outside `snail dev`
// (tests/development-service.mjs): once the file is edited, the next Build
// compiles the library that links it and its importer, whose generation
// holds and reads the new bytes under their own digest.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir, mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {createWasi, instantiate, linkedFileImports} from '../host/browser/load.mjs';
import {createTasks, taskExports} from '../host/browser/tasks.mjs';
import {startDevelopment} from './development-service.mjs';

const execute = promisify(execFile), root = process.argv[2];
const project = await mkdtemp(join(tmpdir(), 'snail-project-resources-'));
const build = target => execute(join(root, 'snail'), ['build', project, target]);
const run = path => execute(process.execPath, ['--no-warnings', join(root, 'host/native/run-snail.mjs'), path]);
const write = async (name, contents) => { await mkdir(join(project, name, '..'), {recursive: true}); await writeFile(join(project, name), contents); };
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const hero = Buffer.from([1, 2, 3, 255]), villain = Buffer.from([7]), edited = Buffer.from([9, 8]);
const resource = (directory, bytes) => readFile(join(directory, 'resources', digest(bytes)));

// The browser host fetches a static page's files relative to its module,
// so serve the output as a page's server would and read through it. The
// program's lines, and the paths the page fetched.
async function pageOutput(directory) {
  const fetched = [];
  const server = createServer(async (request, response) => {
    const path = decodeURIComponent(new URL(request.url, 'http://page').pathname);
    fetched.push(path);
    try { response.end(await readFile(join(directory, path))); }
    catch { response.writeHead(404).end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}/program.wasm`, lines = [];
  try {
    const read = async file => {
      const response = await fetch(new URL(file, base));
      if (!response.ok) throw new Error(`${response.status} fetching ${file}`);
      return new Uint8Array(await response.arrayBuffer());
    };
    const module = await WebAssembly.compile(await read('program.wasm'));
    const wasi = createWasi({print: (fd, line) => lines.push(line)});
    let instance;
    const tasks = createTasks(() => instance && taskExports({exports: instance.exports}));
    instance = await instantiate(module, {...wasi.getImportObject(), ...linkedFileImports(read, module, () => tasks)});
    wasi.initialize(instance);
    instance.exports.main();
    await tasks.drive();
    return {output: lines.join('\n'), fetched};
  } finally { server.close(); }
}

try {
  await write('src/assets/sprites.sld', `(define-library (assets sprites) (export hero villain) (import (snail core base) (snail shell resource))
    (begin (: hero Resource) (define hero (link-file "art/hero.bin")) (: villain Resource) (define villain (link-file "art/villain.bin"))))`);
  await write('src/assets/art/hero.bin', hero);
  await write('src/assets/art/villain.bin', villain);
  await write('main.sld', `(import (snail core base) (snail core io) (only (snail shell task) tasks dispatch-local) (snail shell resource) (assets sprites))
(dispatch-local (once (lambda () (write-line (string-join (map (lambda (byte) (show (u8->i32 byte))) (vector->list (read-resource hero))) ",")))))\n`);
  await write('public/index.html', '<!doctype html><title>Resources</title>');
  await write('project.datum', `((build-target cli (program (entry "main.sld") (library-roots ("src"))))
 (build-target page (browser (entry "main.sld") (library-roots ("src")) (public "public"))))`);

  await build('cli');
  assert.deepEqual(await resource(join(project, 'build/cli'), hero), hero, 'the program target places the file');
  assert.deepEqual((await readdir(join(project, 'build/cli/resources'))).sort(), [digest(hero), digest(villain)].sort());
  assert.equal((await run(join(project, 'build/cli/program.wasm'))).stdout, '1,2,3,255\n', 'the native host reads it when the task asks');

  await build('page');
  assert.deepEqual(await resource(join(project, 'build/page'), hero), hero, 'the browser target places the file');
  const page = await pageOutput(join(project, 'build/page'));
  assert.equal(page.output, '1,2,3,255', 'the browser host fetches it beside the module');
  assert.ok(page.fetched.includes(`/resources/${digest(hero)}`), page.fetched.join(' '));
  assert.ok(!page.fetched.includes(`/resources/${digest(villain)}`), 'a file the program never reads is never fetched');

  await rm(join(project, 'src/assets/art/hero.bin'));
  await assert.rejects(build('cli'), /sprites\.sld:\d+:\d+: the library assets\.sprites links art\/hero\.bin, but there is no file at /);
  await write('src/assets/art/hero.bin', hero);

  const service = await startDevelopment(root, project);
  try {
    const output = (await service.settled(0)).published.targets.find(target => target.name === 'cli');
    assert.deepEqual(await resource(output.directory, hero), hero, 'a development build places the file');
    assert.equal((await run(join(output.directory, 'modules.json'))).stdout, '1,2,3,255\n');
    await write('src/assets/art/hero.bin', edited);
    const next = (await service.rebuilt()).published.targets.find(target => target.name === 'cli');
    assert.equal(next.compiled, 2, 'the library that links the file, and its importer, compile again');
    assert.deepEqual(await resource(next.directory, edited), edited, 'the generation holds the new bytes');
    assert.equal((await run(join(next.directory, 'modules.json'))).stdout, '9,8\n');
    const {code, signal, stderr} = await service.stop();
    assert.deepEqual({code, signal}, {code: 0, signal: null}, stderr);
  } finally { await service.stop(); }
  console.log('project resources passed');
} finally {
  await rm(project, {recursive: true, force: true});
}
