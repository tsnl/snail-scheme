// Native target traversal through macros, producers and generated source.
//   node tests/project-artifacts.mjs ROOT
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {cp, mkdir, mkdtemp, readFile, readdir, realpath, rename, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {promisify} from 'node:util';
import {pathToFileURL} from 'node:url';

const execute = promisify(execFile), root = process.argv[2];
const project = await mkdtemp(join(tmpdir(), 'snail-project-artifacts-'));
const output = name => join(project, 'build', name);
const build = (name, env = process.env) => execute(join(root, 'snail'), ['build', project, name], {env, maxBuffer: 4 * 1024 * 1024});
const run = path => execute(process.execPath, ['--no-warnings', join(root, 'host/native/run-snail.mjs'), path]);
const artifact = name => `(import (snail-core base) (snail-core artifact))\n(artifact-bundle "${name}")\n`;

async function generations() {
  const counts = {};
  for (const name of await readdir(join(project, 'build'))) {
    if (!name.startsWith('.snail-')) continue;
    const target = await readFile(join(project, 'build', name, '.snail-target'), 'utf8');
    counts[target] = (counts[target] ?? 0) + 1;
  }
  return counts;
}

async function checkProgram(program, value) {
  const lines = (await run(program)).stdout.trim().split('\n');
  const paths = lines[0].split('|');
  assert.deepEqual(paths, [...paths].sort(), 'relative file names are sorted');
  assert.equal(new Set(paths).size, paths.length);
  assert.ok(paths.includes('program.wasm') && paths.includes('host.mjs') && paths.includes('index.html'));
  assert.ok(paths.includes('nested/.snail-target'), 'only the root ownership marker is excluded');
  assert.ok(paths.includes('.hidden') && paths.includes('quote".txt'));
  assert.ok(!paths.includes('.snail-target') && !paths.includes('.snail-publish'));
  assert.deepEqual(lines.slice(1), [`${value},0,255,`, `${value},0,255,`, '99,', `${value},0,255,`]);
}

// Producer cycles fail while the build is planned, before the producer that
// would close one runs. Each producer leaves a marker when it runs. A
// knot's producer imports, through a helper, the library it generates; a
// late cycle shows only once the first producer's output imports a second
// generated library, whose producer imports the first.
async function producerCycles() {
  const directory = await mkdtemp(join(tmpdir(), 'snail-producer-cycles-'));
  const write = (name, text) => mkdir(join(directory, name, '..'), {recursive: true}).then(() => writeFile(join(directory, name), text));
  const ran = name => readFile(join(directory, `${name}.ran`), 'utf8').then(() => true, () => false);
  const recipe = (name, imports, output) => `(generate-library (${name.replace('/', ' ')})
    (import (snail-core base) (snail-core io) (snail-core syntax) ${imports})
    (begin (write-file "${join(directory, `${name.replace('/', '-')}.ran`)}" "ran")
      (library-syntax (list "${name.replace('/', '" "')}") (list "value") (list (list "snail-core" "base") ${output})
        (list (form ":" (list (SymbolSyntax "value") (SymbolSyntax "String")))
              (form "define" (list (SymbolSyntax "value") (StringSyntax "${name}")))))))`;
  try {
    await write('project.datum', `((build-target knot (program (entry "knot.sld") (library-roots ("src"))))
      (build-target late (program (entry "late.sld") (library-roots ("src")))))`);
    await write('knot.sld', '(import (snail-core base) (sample knot)) (unit)');
    await write('src/sample/knot.sld', recipe('sample/knot', '(sample knot-helper)', ''));
    await write('src/sample/knot-helper.sld', '(define-library (sample knot-helper) (export) (import (sample knot)) (begin))');
    await write('late.sld', '(import (snail-core base) (g one)) (unit)');
    await write('src/g/one.sld', recipe('g/one', '', '(list "g" "two")'));
    await write('src/g/two.sld', recipe('g/two', '(g one)', ''));
    const build = name => execute(join(root, 'snail'), ['build', directory, name], {maxBuffer: 4 * 1024 * 1024});
    await assert.rejects(build('knot'), /library import cycle through sample\.knot/);
    assert.equal(await ran('sample-knot'), false, 'a producer in a cycle never runs');
    await assert.rejects(build('late'), /library import cycle through g\.one/);
    assert.deepEqual([await ran('g-one'), await ran('g-two')], [true, false], 'only the producer the cycle shows after runs');
  } finally {
    await rm(directory, {recursive: true, force: true});
  }
}

try {
  await producerCycles();
  await cp(join(root, 'tests/artifacts/project'), project, {recursive: true});
  await mkdir(join(project, 'client-public/nested'), {recursive: true});
  await mkdir(join(project, 'admin-public'));
  await writeFile(join(project, 'client-public/nested/data.bin'), Buffer.from([65, 0, 255]));
  await writeFile(join(project, 'client-public/nested/.snail-target'), 'ordinary nested file');
  await writeFile(join(project, 'client-public/.hidden'), 'hidden');
  await writeFile(join(project, 'client-public/quote".txt'), 'quoted');
  await writeFile(join(project, 'client-public/index.html'), '<!doctype html><title>client</title>');
  await mkdir(join(project, 'client-public/empty'));
  await writeFile(join(project, 'admin-public/admin.bin'), Buffer.from([99]));
  const source = await readFile(join(project, 'server.sld'), 'utf8');

  await build('server');
  const first = await realpath(output('server'));
  await checkProgram(join(first, 'program.wasm'), 65);
  assert.deepEqual(await generations(), {client: 1, admin: 1, server: 1}, 'repeated and nested requests build each target once');

  await writeFile(join(project, 'client-public/nested/data.bin'), Buffer.from([90, 0, 255]));
  await build('server');
  const second = await realpath(output('server'));
  await checkProgram(join(second, 'program.wasm'), 90);
  await checkProgram(join(first, 'program.wasm'), 65);
  assert.deepEqual(await generations(), {client: 2, admin: 2, server: 2}, 'each invocation regenerates dependencies and producers');

  const clientBeforeFailure = await realpath(output('client'));
  for (const prefix of [join(project, 'client-public'), join(project, 'build/.snail-')]) {
    const preload = pathToFileURL(join(root, 'tests/compiler-inputs/directory-failure.mjs')).href;
    await assert.rejects(build('client', {...process.env, SNAIL_TEST_DIRECTORY_FAILURE: prefix,
      NODE_OPTIONS: [process.env.NODE_OPTIONS, `--import=${preload}`].filter(Boolean).join(' ')}), /cannot read directory/);
    assert.equal(await realpath(output('client')), clientBeforeFailure, 'read failure never publishes a partial public tree or bundle');
  }

  for (const [name, error] of [['missing', /server.sld:2:.*unknown project build target/], ['server', /artifact target must be a browser build/]]) {
    await writeFile(join(project, 'server.sld'), artifact(name));
    await assert.rejects(build('server'), error);
    assert.equal(await realpath(output('server')), second);
  }

  // The last cycle shows only once client is built and the producer has
  // run; that generation goes with the failed build.
  const beforeCycles = await generations();
  await writeFile(join(project, 'client.sld'), artifact('client'));
  await assert.rejects(build('client'), /client -> client/);
  await writeFile(join(project, 'client.sld'), artifact('admin'));
  await writeFile(join(project, 'admin.sld'), '(import (snail-core base) (generated assets))\n(unit)\n');
  await assert.rejects(build('client'), /client -> admin -> client/, 'cycle discovered while compiling a producer');
  await writeFile(join(project, 'client.sld'), '(import (snail-core base)) (unit)\n');
  await assert.rejects(build('admin'), /artifact dependency cycle: admin -> admin/, 'cycle introduced by generated syntax');
  assert.deepEqual(await generations(), beforeCycles, 'a rejected cycle removes the generations its build created');

  await writeFile(join(project, 'client.sld'), '(import (snail-core base)) (unit)\n');
  await writeFile(join(project, 'admin.sld'), '(import (snail-core base)) (unit)\n');
  await writeFile(join(project, 'server.sld'), `${source}\n(missing-function)\n`);
  const priorClient = await realpath(output('client'));
  await assert.rejects(build('server'), /missing-function/);
  assert.equal(await realpath(output('server')), second, 'failed parent retains its prior completed output');
  assert.equal(await realpath(output('client')), priorClient, 'a failed parent publishes none of its dependencies');
  await checkProgram(join(second, 'program.wasm'), 90);

  // Artifact bytes do not depend on a generation path at runtime.
  await cp(join(second, 'program.wasm'), join(project, 'standalone.wasm'));
  await rename(join(project, 'build'), join(project, 'outputs-moved'));
  await checkProgram(join(project, 'standalone.wasm'), 90);
  console.log('project artifacts passed');
} finally {
  await rm(project, {recursive: true, force: true});
}
