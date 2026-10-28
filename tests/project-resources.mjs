// Linked files ship beside the payload of every project build, under the
// name the compiler gives them, and each host reads them before the
// program starts.
//   node tests/project-resources.mjs ROOT
//
// A library links a file beside its source. A program target and a
// browser target each place it at resources/NAME in their output; the
// program prints the bytes it read, natively and through the browser
// host's loader fetching the page's files over HTTP. A development build
// places the file too, seen from outside `snail dev`
// (tests/development-service.mjs): once the file is edited, the next Build
// compiles nothing again, yet its generation holds and reads the new bytes.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:http';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {createWasi, instantiate, linkedFileImports} from '../host/browser/load.mjs';
import {startDevelopment} from './development-service.mjs';

const execute = promisify(execFile), root = process.argv[2];
const project = await mkdtemp(join(tmpdir(), 'snail-project-resources-'));
const build = target => execute(join(root, 'snail'), ['build', project, target]);
const run = path => execute(process.execPath, ['--no-warnings', join(root, 'host/native/run-snail.mjs'), path]);
const write = async (name, contents) => { await mkdir(join(project, name, '..'), {recursive: true}); await writeFile(join(project, name), contents); };
const resource = directory => readFile(join(directory, 'resources/assets.sprites/art/hero.bin'));

// The browser host fetches a static page's files relative to its module,
// so serve the output as a page's server would and read through it.
async function pageOutput(directory) {
  const server = createServer(async (request, response) => {
    try { response.end(await readFile(join(directory, decodeURIComponent(new URL(request.url, 'http://page').pathname)))); }
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
    const instance = await instantiate(module, {...wasi.getImportObject(), ...await linkedFileImports(read, module)});
    wasi.initialize(instance);
    instance.exports.main();
    return lines.join('\n');
  } finally { server.close(); }
}

try {
  await write('src/assets/sprites.sld', `(define-library (assets sprites) (export hero) (import (snail-core base) (snail-core resource))
    (begin (: hero Resource) (define hero (link-bytes "art/hero.bin"))))`);
  await write('src/assets/art/hero.bin', Buffer.from([1, 2, 3, 255]));
  await write('main.sld', `(import (snail-core base) (snail-core io) (snail-core resource) (assets sprites))
(write-line (string-join (map (lambda (byte) (show (u8->i32 byte))) (vector->list (read-resource hero))) ","))\n`);
  await write('public/index.html', '<!doctype html><title>Resources</title>');
  await write('project.datum', `((build-target cli (program (entry "main.sld") (library-roots ("src"))))
 (build-target page (browser (entry "main.sld") (library-roots ("src")) (public "public"))))`);

  await build('cli');
  assert.deepEqual(await resource(join(project, 'build/cli')), Buffer.from([1, 2, 3, 255]), 'the program target places the file');
  assert.equal((await run(join(project, 'build/cli/program.wasm'))).stdout, '1,2,3,255\n', 'the native host reads it before the program starts');

  await build('page');
  assert.deepEqual(await resource(join(project, 'build/page')), Buffer.from([1, 2, 3, 255]), 'the browser target places the file');
  assert.equal(await pageOutput(join(project, 'build/page')), '1,2,3,255', 'the browser host fetches it beside the module');

  await rm(join(project, 'src/assets/art/hero.bin'));
  await assert.rejects(build('cli'), /sprites\.sld:\d+:\d+: the library assets\.sprites links art\/hero\.bin, but there is no file at /);
  await write('src/assets/art/hero.bin', Buffer.from([1, 2, 3, 255]));

  const service = await startDevelopment(root, project);
  try {
    const output = (await service.settled(0)).published.targets.find(target => target.name === 'cli');
    assert.deepEqual(await resource(output.directory), Buffer.from([1, 2, 3, 255]), 'a development build places the file');
    assert.equal((await run(join(output.directory, 'modules.json'))).stdout, '1,2,3,255\n');
    await write('src/assets/art/hero.bin', Buffer.from([9, 8]));
    const next = (await service.rebuilt()).published.targets.find(target => target.name === 'cli');
    assert.equal(next.compiled, 0, 'a linked file\'s bytes are no build key');
    assert.notEqual(next.digest, output.digest, 'the generation holds the new bytes');
    assert.equal((await run(join(next.directory, 'modules.json'))).stdout, '9,8\n');
    const {code, signal, stderr} = await service.stop();
    assert.deepEqual({code, signal}, {code: 0, signal: null}, stderr);
  } finally { await service.stop(); }
  console.log('project resources passed');
} finally {
  await rm(project, {recursive: true, force: true});
}
