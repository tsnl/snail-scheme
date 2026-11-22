// One build embedding another: a server script's generated library builds
// a client page (tests/embedding) and links every file of it. Producers
// run in every build, so a changed client file reaches the next server.
// A script whose producer builds that script is refused, by name.
// A producer that needs its own library, at once or once another
// producer has run, is an import cycle, and a producer in one never runs.
//   node tests/embedding.mjs ROOT
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {cp, mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';

const execute = promisify(execFile), root = process.argv[2];
const snail = (directory, ...args) =>
  execute(join(root, 'snail-scheme'), args, {cwd: directory, maxBuffer: 4 * 1024 * 1024});

async function embedding() {
  const workspace = await mkdtemp(join(tmpdir(), 'snail-embedding-'));
  try {
    await cp(join(root, 'tests/embedding'), workspace, {recursive: true});
    await mkdir(join(workspace, 'client/public/nested'));
    await writeFile(join(workspace, 'client/public/nested/data.bin'), Buffer.from([65, 0, 255]));
    const served = async () => (await snail(workspace, 'run', '--target', 'node', 'server.scm')).stdout.trim().split('\n');
    const first = await served();
    const paths = first.slice(0, -1).map(line => line.split(' ')[0]);
    assert.deepEqual(paths, [...paths].sort(), 'files are listed in path order');
    for (const path of ['index.html', 'host.mjs', 'main.wasm', 'nested/data.bin'])
      assert.ok(paths.includes(path), `the client's ${path} is linked`);
    assert.ok(first.includes('nested/data.bin 3'));
    assert.equal(first.at(-1), '65,0,255');
    assert.match(await readFile(join(workspace, 'build/client/main/index.html'), 'utf8'), /client/,
                 'the producer publishes the client build in the workspace');
    await writeFile(join(workspace, 'client/public/nested/data.bin'), Buffer.from([90, 0, 255]));
    assert.equal((await served()).at(-1), '90,0,255', 'the next build embeds the changed file');
    await assert.rejects(snail(workspace, 'build', '--target', 'node', 'own.scm'),
                         /a script's build embeds itself: \S*own\.scm → \S*own\.scm/);
  } finally {
    await rm(workspace, {recursive: true, force: true});
  }
}

// Each producer leaves a marker when it runs. A knot's producer imports,
// through a helper, the library it generates; a late cycle shows only once
// the first producer's output imports a second generated library, whose
// producer imports the first.
async function producerCycles() {
  const workspace = await mkdtemp(join(tmpdir(), 'snail-producer-cycles-'));
  const write = (name, text) => mkdir(join(workspace, name, '..'), {recursive: true}).then(() => writeFile(join(workspace, name), text));
  const ran = name => readFile(join(workspace, `${name}.ran`), 'utf8').then(() => true, () => false);
  const recipe = (name, imports, output) => `(generate-library (${name.replace('/', ' ')})
    (import (snail core base) (snail core io) (snail shell syntax) ${imports})
    (lambda ((fs Fs))
      (write-file fs "${join(workspace, `${name.replace('/', '-')}.ran`)}" "ran")
      (library-syntax (list "${name.replace('/', '" "')}") (list "value") (list (list "snail" "core" "base") ${output})
        (list (form "define" (list (form "value" (Nil))
              (form "→" (list (SymbolSyntax "String")))
              (StringSyntax "${name}")))))))`;
  try {
    await write('knot.scm', '(import (snail core base) (sample knot)) (define (main) (→ Unit) (unit))');
    await write('src/sample/knot.sld', recipe('sample/knot', '(sample knot-helper)', ''));
    await write('src/sample/knot-helper.sld', '(define-library (sample knot-helper) (export) (import (sample knot)) (begin))');
    await write('late.scm', '(import (snail core base) (g one)) (define (main) (→ Unit) (unit))');
    await write('src/g/one.sld', recipe('g/one', '', '(list "g" "two")'));
    await write('src/g/two.sld', recipe('g/two', '(g one)', ''));
    const build = name => snail(workspace, 'build', '--target', 'node', name);
    await assert.rejects(build('knot.scm'), /library import cycle through sample\.knot/);
    assert.equal(await ran('sample-knot'), false, 'a producer in a cycle never runs');
    await assert.rejects(build('late.scm'), /library import cycle through g\.one/);
    assert.deepEqual([await ran('g-one'), await ran('g-two')], [true, false], 'only the producer the cycle shows after runs');
  } finally {
    await rm(workspace, {recursive: true, force: true});
  }
}

await producerCycles();
await embedding();
console.log('embedding: a build embeds another through a producer; cycles of producers and of builds fail');
