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
const project = await mkdtemp(join(tmpdir(), 'lofi-project-artifacts-'));
const output = name => join(project, 'build', name);
const build = (name, env = process.env) => execute(join(root, 'lofi'), ['build', project, name], {env, maxBuffer: 4 * 1024 * 1024});
const run = path => execute(process.execPath, ['--no-warnings', join(root, 'scripts/run-lofi.mjs'), path]);
const artifact = name => `(import (lofi base) (lofi artifact))\n(artifact-bundle "${name}")\n`;

async function generations() {
  const counts = {};
  for (const name of await readdir(join(project, 'build'))) {
    if (!name.startsWith('.lofi-')) continue;
    const target = await readFile(join(project, 'build', name, '.lofi-target'), 'utf8');
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
  assert.ok(paths.includes('nested/.lofi-target'), 'only the root ownership marker is excluded');
  assert.ok(paths.includes('.hidden') && paths.includes('quote".txt'));
  assert.ok(!paths.includes('.lofi-target') && !paths.includes('.lofi-publish'));
  assert.deepEqual(lines.slice(1), [`${value},0,255,`, `${value},0,255,`, '99,', `${value},0,255,`]);
}

try {
  await cp(join(root, 'tests/artifacts/project'), project, {recursive: true});
  await mkdir(join(project, 'client-public/nested'), {recursive: true});
  await mkdir(join(project, 'admin-public'));
  await writeFile(join(project, 'client-public/nested/data.bin'), Buffer.from([65, 0, 255]));
  await writeFile(join(project, 'client-public/nested/.lofi-target'), 'ordinary nested file');
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
  for (const prefix of [join(project, 'client-public'), join(project, 'build/.lofi-')]) {
    const preload = pathToFileURL(join(root, 'tests/compiler-inputs/directory-failure.mjs')).href;
    await assert.rejects(build('client', {...process.env, LOFI_TEST_DIRECTORY_FAILURE: prefix,
      NODE_OPTIONS: [process.env.NODE_OPTIONS, `--import=${preload}`].filter(Boolean).join(' ')}), /cannot read directory/);
    assert.equal(await realpath(output('client')), clientBeforeFailure, 'read failure never publishes a partial public tree or bundle');
  }

  for (const [name, error] of [['missing', /server.sld:2:.*unknown project build target/], ['server', /artifact target must be a browser build/]]) {
    await writeFile(join(project, 'server.sld'), artifact(name));
    await assert.rejects(build('server'), error);
    assert.equal(await realpath(output('server')), second);
  }

  await writeFile(join(project, 'client.sld'), artifact('client'));
  await assert.rejects(build('client'), /client -> client/);
  await writeFile(join(project, 'client.sld'), artifact('admin'));
  await writeFile(join(project, 'admin.sld'), '(import (lofi base) (generated assets))\n(unit)\n');
  await assert.rejects(build('client'), /client -> admin -> client/, 'cycle discovered while compiling a producer');

  await writeFile(join(project, 'client.sld'), '(import (lofi base)) (unit)\n');
  await writeFile(join(project, 'admin.sld'), '(import (lofi base)) (unit)\n');
  await writeFile(join(project, 'server.sld'), `${source}\n(missing-function)\n`);
  const priorClient = await realpath(output('client'));
  await assert.rejects(build('server'), /missing-function/);
  assert.equal(await realpath(output('server')), second, 'failed parent retains its prior completed output');
  assert.notEqual(await realpath(output('client')), priorClient, 'successful dependencies remain published');
  await checkProgram(join(second, 'program.wasm'), 90);

  // Artifact bytes do not depend on a generation path at runtime.
  await cp(join(second, 'program.wasm'), join(project, 'standalone.wasm'));
  await rename(join(project, 'build'), join(project, 'outputs-moved'));
  await checkProgram(join(project, 'standalone.wasm'), 90);
  console.log('project artifacts passed');
} finally {
  await rm(project, {recursive: true, force: true});
}
